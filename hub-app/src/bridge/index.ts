// Even Hub bridge entry point. Real implementation (waitForEvenAppBridge,
// safe-call wrapper, event subscription) lands in milestone 3 task 3.1.
// This stub keeps the bundle compiling and gives the rest of the app a
// stable import path to migrate from.

export type EvenBridge = {
  ready: boolean;
};

export const bridge: EvenBridge = {
  ready: false,
};
