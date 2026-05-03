// Ambient declarations for the Even Hub native bridge that the Even App
// container exposes on `window`. These mirror the public surface of
// @evenrealities/even_hub_sdk @ v1.7+; replace this hand-rolled stub once
// the real SDK package is available on the registry.

export {};

declare global {
  interface EvenBridgeEvents {
    /** Single-tap on either touch pad. `side: "left" | "right"`. */
    tap: { side: "left" | "right"; ts: number };
    /** Long press (>=500 ms). */
    long_press: { side: "left" | "right"; ts: number };
    /** Forward/backward swipe along the temple. */
    swipe: { side: "left" | "right"; direction: "forward" | "backward"; ts: number };
    /** Head gestures (nod / shake) reported by the IMU. */
    gesture: { kind: "nod" | "shake"; ts: number };
    /** Microphone PCM frames; emitted only after `audioControl(true)`. */
    audio_pcm: { bytes: ArrayBuffer; sample_rate: number; ts: number };
  }

  interface EvenBridge {
    readonly version: string;
    /** Returns once the bridge is fully wired (BLE connected + auth done). */
    waitReady(): Promise<void>;
    /** Subscribe to a typed event; returns unsubscribe handle. */
    on<E extends keyof EvenBridgeEvents>(
      event: E,
      handler: (payload: EvenBridgeEvents[E]) => void,
    ): () => void;
    /** Toggle G2 microphone capture. */
    audioControl(enabled: boolean): Promise<void>;
    /** Render a text page on G2 (deferred to milestone D). */
    displayText?(lines: string[]): Promise<void>;
  }

  interface Window {
    EvenHub?: EvenBridge;
  }
}
