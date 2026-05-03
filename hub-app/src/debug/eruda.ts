// Lazy-loaded Eruda devtools overlay — only included in the bundle when
// VITE_DEBUG_OVERLAY=true (set in .env.development). Production builds
// tree-shake this away because the dynamic import is gated.

export async function mountDebugOverlay(): Promise<void> {
  const { default: eruda } = await import("eruda");
  eruda.init();
}
