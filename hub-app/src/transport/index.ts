// Server transport entry point. Real socket/channel/uplink implementations
// land in milestone 3 tasks 3.2 / 3.3.

export const TRANSPORT_API_BASE = import.meta.env.VITE_API_BASE ?? "";
export const TRANSPORT_WSS_BASE = import.meta.env.VITE_WSS_BASE ?? "";
