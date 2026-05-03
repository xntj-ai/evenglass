import { initLogger, logError, logInfo } from "@services/logger";
import { initSentry } from "@services/sentry";
import { mountDebugOverlay } from "@debug/eruda";
import { $isEnrolled } from "@shared/store";
import { renderEnrollmentForm } from "@features/enrollment";
import { startInputRelay } from "@features/input-relay";
import { connectChannel } from "@transport/channel";
import { flushQueue, watchOnlineForFlush } from "@transport/uplink";
import { waitForEvenAppBridge } from "@bridge/index";

async function bootstrap(): Promise<void> {
  initLogger();
  initSentry();

  if (import.meta.env.VITE_DEBUG_OVERLAY === "true") {
    await mountDebugOverlay();
  }

  const root = document.getElementById("app");
  if (!root) {
    logError("missing #app root element");
    return;
  }

  watchOnlineForFlush();

  if (!$isEnrolled.get()) {
    renderEnrollmentForm(root, () => {
      void enterRelayMode(root);
    });
    return;
  }

  await enterRelayMode(root);
}

async function enterRelayMode(root: HTMLElement): Promise<void> {
  root.innerHTML = `<div class="status">evenglass · running</div>`;

  void flushQueue();

  try {
    await waitForEvenAppBridge();
  } catch (err) {
    logError("bridge init failed", err);
  }

  try {
    await connectChannel();
    logInfo("channel connected");
  } catch (err) {
    logError("channel connect failed (will retry via socket reconnect)", err);
  }

  try {
    await startInputRelay();
    logInfo("input relay started");
  } catch (err) {
    logError("input relay failed", err);
  }
}

bootstrap().catch((err) => {
  console.error("bootstrap failed", err);
});
