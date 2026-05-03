import { initLogger } from "@services/logger";
import { initSentry } from "@services/sentry";
import { mountDebugOverlay } from "@debug/eruda";

async function bootstrap() {
  initLogger();
  initSentry();

  if (import.meta.env.VITE_DEBUG_OVERLAY === "true") {
    await mountDebugOverlay();
  }

  const root = document.getElementById("app");
  if (root) {
    root.textContent = "evenglass hub-app — milestone C scaffold";
  }
}

bootstrap().catch((err) => {
  console.error("bootstrap failed", err);
});
