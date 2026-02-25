import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig({
  build: {
    target: "esnext",
    rollupOptions: {
      input: {
        index: resolve(__dirname, "index.html"),
        app: resolve(__dirname, "app.html"),
        login: resolve(__dirname, "login.html"),
        signup: resolve(__dirname, "signup.html"),
        forgotPassword: resolve(__dirname, "forgot-password.html"),
        resetPassword: resolve(__dirname, "reset-password.html"),
      },
    },
  },
});
