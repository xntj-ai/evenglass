// Renders the initial G2 screen content via the Hub SDK. The Even Hub
// runtime requires `createStartUpPageContainer` to be called before any
// other UI/input bridge operation — without it user input (Up / Down /
// Click / Double Click) is silently dropped.
//
// We render a single full-screen list container with one item so that:
//   1. There is always something visible on the glasses display.
//   2. The list captures user input events (isEventCapture=1) which the
//      simulator's bottom buttons (and later the real glasses temple
//      touch surface) can drive — those events flow through
//      `onEvenHubEvent` into our input-relay and up to the server.

import {
  CreateStartUpPageContainer,
  ListContainerProperty,
  ListItemContainerProperty,
  StartUpPageCreateResult,
} from "@evenrealities/even_hub_sdk";

import { waitForEvenAppBridge } from "@bridge/index";
import { logError, logInfo } from "@services/logger";

const G2_SCREEN_WIDTH = 576;
const G2_SCREEN_HEIGHT = 288;

const STATUS_LIST_CONTAINER_ID = 1;

export async function mountStartupPage(): Promise<void> {
  const bridge = await waitForEvenAppBridge();

  const statusList = new ListContainerProperty({
    xPosition: 0,
    yPosition: 0,
    width: G2_SCREEN_WIDTH,
    height: G2_SCREEN_HEIGHT,
    containerID: STATUS_LIST_CONTAINER_ID,
    containerName: "evenglass-status",
    itemContainer: new ListItemContainerProperty({
      itemCount: 1,
      itemName: ["evenglass · running"],
    }),
    isEventCapture: 1,
  });

  const result = await bridge.createStartUpPageContainer(
    new CreateStartUpPageContainer({
      containerTotalNum: 1,
      listObject: [statusList],
    }),
  );

  if (result === StartUpPageCreateResult.success) {
    logInfo("G2 startup page mounted");
  } else {
    logError("G2 startup page mount failed", { result });
  }
}
