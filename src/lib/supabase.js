import { createClient } from "@supabase/supabase-js";

const DEFAULT_SUPABASE_URL = "https://jlrlwfpbrxlitdiobkgy.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY = "sb_publishable_43K-wSq-e_datCcSKN9yzA_tkWeAW0h";

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || DEFAULT_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;
const usingFallbackConfig = !import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY;

let supabaseClient;
let fallbackConfigWarned = false;

export function getSupabaseClient() {
  if (!supabaseClient) {
    if (usingFallbackConfig && !fallbackConfigWarned) {
      console.warn("Supabase env vars are missing. Falling back to default project config.");
      fallbackConfigWarned = true;
    }
    supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }
  return supabaseClient;
}

export function getEmailVerificationRedirectUrl() {
  return `${window.location.origin}/login?email_verified=1`;
}

export function getPasswordResetRedirectUrl() {
  return `${window.location.origin}/reset-password`;
}
