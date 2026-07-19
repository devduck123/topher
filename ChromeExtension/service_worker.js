import {boundedNativeResponse, createRequestHandler} from "./protocol.js";

const NATIVE_HOST_NAME = "dev.topher.chrome_bridge";
const MINIMUM_RECONNECT_DELAY_MILLISECONDS = 1000;
const MAXIMUM_RECONNECT_DELAY_MILLISECONDS = 30000;

const handleRequest = createRequestHandler(chrome);
let nativePort = null;
let reconnectDelayMilliseconds = MINIMUM_RECONNECT_DELAY_MILLISECONDS;
let reconnectTimer = null;

function connectNativeHost() {
  if (nativePort !== null) {
    return;
  }

  try {
    const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
    nativePort = port;
    reconnectDelayMilliseconds = MINIMUM_RECONNECT_DELAY_MILLISECONDS;

    port.onMessage.addListener(async (message) => {
      const response = await handleRequest(message);
      if (nativePort === port) {
        port.postMessage(boundedNativeResponse(response, message?.requestID));
      }
    });

    port.onDisconnect.addListener(() => {
      if (nativePort === port) {
        nativePort = null;
      }
      scheduleReconnect();
    });
  } catch {
    nativePort = null;
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  if (reconnectTimer !== null) {
    return;
  }
  const delay = reconnectDelayMilliseconds;
  reconnectDelayMilliseconds = Math.min(
    MAXIMUM_RECONNECT_DELAY_MILLISECONDS,
    reconnectDelayMilliseconds * 2,
  );
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectNativeHost();
  }, delay);
}

chrome.runtime.onInstalled.addListener(connectNativeHost);
chrome.runtime.onStartup.addListener(connectNativeHost);
connectNativeHost();
