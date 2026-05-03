import { initLogger, logError, logInfo } from "@services/logger";
import { initSentry } from "@services/sentry";
import { mountDebugOverlay } from "@debug/eruda";
import { $isEnrolled } from "@shared/store";
import { renderEnrollmentForm } from "@features/enrollment";
import { startInputRelay } from "@features/input-relay";
import { mountStartupPage } from "@features/g2-display";
import { startAudioRelay, type AudioRelayHandle } from "@features/audio-relay";
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
  // Mic toggle is a temporary D1a affordance — D1b replaces this with a
  // server-pushed "start_audio" command so the PC PTT key drives the
  // mic, not a button on the Hub App.
  root.innerHTML = `
    <div class="status">evenglass · running</div>
    <button id="mic-toggle" type="button" disabled>🎙 Start mic</button>
    <div class="mic-state" id="mic-state">idle</div>
  `;

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
    await mountStartupPage();
  } catch (err) {
    logError("G2 startup page mount failed", err);
  }

  try {
    await startInputRelay();
    logInfo("input relay started");
  } catch (err) {
    logError("input relay failed", err);
  }

  wireMicToggle();
}

function wireMicToggle(): void {
  const button = document.getElementById("mic-toggle") as HTMLButtonElement | null;
  const state = document.getElementById("mic-state");
  if (!button || !state) return;

  let handle: AudioRelayHandle | null = null;
  let busy = false;

  const setIdle = () => {
    button.textContent = "🎙 Start mic";
    state.textContent = "idle";
  };
  const setActive = () => {
    button.textContent = "🎙 Stop mic";
    state.textContent = "streaming";
  };

  button.disabled = false;
  setIdle();

  button.addEventListener("click", async () => {
    if (busy) return;
    busy = true;
    button.disabled = true;

    try {
      if (handle) {
        await handle.stop();
        handle = null;
        setIdle();
      } else {
        handle = await startAudioRelay();
        setActive();
      }
    } catch (err) {
      logError("mic toggle failed", err);
      state.textContent = "error";
    } finally {
      busy = false;
      button.disabled = false;
    }
  });
}

bootstrap().catch((err) => {
  console.error("bootstrap failed", err);
});
