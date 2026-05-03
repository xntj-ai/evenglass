// Channel re-export hub. Currently only `g2:device:<id>` exists; future
// metrics / display channels will land here too.

export { connectChannel, disconnectChannel, getActiveChannel } from "./socket";
