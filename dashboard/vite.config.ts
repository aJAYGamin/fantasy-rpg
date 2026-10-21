import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// The web app lives in web/. In development `/api` goes to the Fastify server.
export default defineConfig({
  root: "web",
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/api": "http://127.0.0.1:4517" },
  },
  build: {
    outDir: "../dist/web",
    emptyOutDir: true,
  },
});
