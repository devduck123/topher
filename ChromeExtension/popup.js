export const YOUTUBE_ORIGIN_PATTERN = "https://www.youtube.com/*";

export async function hasYouTubeAccess(chromeAPI) {
  return chromeAPI.permissions.contains({origins: [YOUTUBE_ORIGIN_PATTERN]});
}

export async function requestYouTubeAccess(chromeAPI) {
  return chromeAPI.permissions.request({origins: [YOUTUBE_ORIGIN_PATTERN]});
}

export async function removeYouTubeAccess(chromeAPI) {
  return chromeAPI.permissions.remove({origins: [YOUTUBE_ORIGIN_PATTERN]});
}

function installPopup(document, chromeAPI) {
  const status = document.querySelector("#permission-status");
  const grant = document.querySelector("#grant-access");
  const remove = document.querySelector("#remove-access");

  async function render() {
    try {
      const granted = await hasYouTubeAccess(chromeAPI);
      status.textContent = granted
        ? "YouTube access is granted."
        : "YouTube access is not granted.";
      grant.hidden = granted;
      remove.hidden = !granted;
    } catch {
      status.textContent = "Chrome could not check access. Reload the extension and try again.";
      grant.hidden = false;
      remove.hidden = true;
    }
  }

  async function run(button, operation) {
    button.disabled = true;
    try {
      await operation(chromeAPI);
      await render();
    } catch {
      status.textContent = "Chrome could not change access. Reopen the extension and try again.";
    } finally {
      button.disabled = false;
    }
  }

  grant.addEventListener("click", () => run(grant, requestYouTubeAccess));
  remove.addEventListener("click", () => run(remove, removeYouTubeAccess));
  chromeAPI.permissions.onAdded.addListener(render);
  chromeAPI.permissions.onRemoved.addListener(render);
  render();
}

if (typeof document !== "undefined" && typeof chrome !== "undefined") {
  installPopup(document, chrome);
}
