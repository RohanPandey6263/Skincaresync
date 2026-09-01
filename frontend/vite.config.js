import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: "dist",
    // A production build shipped a 1 MB source map alongside the bundle, which
    // publishes the full unminified source to anyone who opens devtools. Set
    // BUILD_SOURCEMAP=1 when you need one for a specific debugging session.
    sourcemap: process.env.BUILD_SOURCEMAP === "1",
  },
});
