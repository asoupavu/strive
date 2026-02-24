import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ReminderRow = {
  user_id: string;
  email: string;
  handle: string | null;
  local_date: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const REMINDER_FROM_EMAIL = Deno.env.get("REMINDER_FROM_EMAIL") ?? "";
const SITE_URL = Deno.env.get("SITE_URL") ?? "https://strive.vercel.app";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function reminderHtml(handle: string | null) {
  const greet = handle ? `Hey @${handle}` : "Hey";
  return `
    <div style="font-family: Arial, sans-serif; line-height: 1.45; color: #1f2a37;">
      <p>${greet} 👋</p>
      <p>Quick morning nudge 🌞</p>
      <p>Don’t forget to check off today’s habits on <a href="${SITE_URL}" style="color:#c24d2c; font-weight:700; text-decoration:none;">Strive</a> ✅</p>
      <p>Small wins stack up. You got this 💪</p>
      <p style="margin-top: 18px;">- Strive</p>
    </div>
  `.trim();
}

async function sendReminderEmail(to: string, handle: string | null) {
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: REMINDER_FROM_EMAIL,
      to,
      subject: "🌞 quick strive reminder",
      html: reminderHtml(handle),
    }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`Resend failed (${resp.status}): ${body}`);
  }
}

Deno.serve(async () => {
  if (!RESEND_API_KEY || !REMINDER_FROM_EMAIL) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "Missing RESEND_API_KEY or REMINDER_FROM_EMAIL",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const { data, error } = await supabase.rpc("get_due_reminder_recipients");
  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const recipients = (data ?? []) as ReminderRow[];
  let sent = 0;
  let failed = 0;

  for (const row of recipients) {
    try {
      await sendReminderEmail(row.email, row.handle);
      const { error: logError } = await supabase.from("reminder_email_logs").insert({
        user_id: row.user_id,
        local_date: row.local_date,
      });
      if (logError && !String(logError.message).toLowerCase().includes("duplicate")) {
        throw logError;
      }
      sent += 1;
    } catch (err) {
      failed += 1;
      console.error("Reminder send failed", row.user_id, err);
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      checked: recipients.length,
      sent,
      failed,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
