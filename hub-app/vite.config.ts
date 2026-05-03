import { defineConfig } from "vite";
import path from "node:path";

// Even Hub WebView is Chromium-based (HarmonyOS 4.x / Even App container);
// targeting modern Chromium directly avoids legacy polyfill bloat.
export default defineConfig({
  root: ".",
  base: "./",
  build: {
    target: "es2022",
    outDir: "dist",
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          phoenix: ["phoenix"],
          sentry: ["@sentry/browser"],
        },
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@bridge": path.resolve(__dirname, "./src/bridge"),
      "@transport": path.resolve(__dirname, "./src/transport"),
      "@features": path.resolve(__dirname, "./src/features"),
      "@services": path.resolve(__dirname, "./src/services"),
      "@shared": path.resolve(__dirname, "./src/shared"),
      "@debug": path.resolve(__dirname, "./src/debug"),
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
});
