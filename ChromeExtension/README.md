# Topher Chrome context extension

This unpacked Manifest V3 extension is the browser half of Topher's structured
Chrome context boundary. It provides bounded tab metadata, exact-title tab
activation, and one narrow YouTube Home feed capability through Chrome native
messaging. There is no remote service.

## Mental model

For a web developer, the service worker is a small browser adapter, the bundled
`TopherChromeBridgeHost` executable is a framed-JSON relay, and the Topher app
owns deterministic resolution, policy, short-lived references, and UI.

```text
Topher command and policy
  -> ephemeral Unix socket (0700 directory, launch token)
  -> bundled TopherChromeBridgeHost (bounded JSON relay only)
  -> Chrome native-messaging port
  -> MV3 service worker
  -> chrome.tabs / chrome.windows, or one packaged YouTube extractor
```

The primary Topher process creates its socket/token eagerly so an already-open
native host can connect without waiting for the first command. Tab and page
context is still fetched only after a resolved request and is never mirrored or
stored by the extension. Service-worker suspension can discard its in-memory
duplicate cache; the app never automatically retries a dispatched mutation, so
restart does not grant permission to replay an open.

## Permissions and privacy

`manifest.json` requires:

- `tabs`, for bounded regular-tab title/URL metadata and revalidated tab
  activation/navigation;
- `nativeMessaging`, for the registered local helper; and
- `scripting`, only to run the reviewed packaged `youtube_feed_extractor.js` in
  the isolated world after YouTube access is present.

The only optional host permission is `https://www.youtube.com/*`. Chrome cannot
scope a host permission to one route, so Topher additionally accepts extraction
only on the exact `https://www.youtube.com/` Home route. Click the Topher
extension button and choose **Grant YouTube access** to let Chrome show its
permission prompt. The same popup always shows current state and provides
**Remove YouTube access**. A spoken or manual Topher request never prompts for
host access because Chrome requires an explicit extension user gesture.

The YouTube extractor is fixed, packaged, and scans at most 60 visible or nearby
recommendation cards. At most 20 strict video-ID, bounded-title, bounded-channel
records cross the native protocol for presentation. A bounded extension-internal
video-ID/title candidate set proves whether each displayed title is unique; the
additional strings are discarded before the response crosses into Topher. A
missing channel can therefore bound presentation without disabling an otherwise
safe exact-title selection. Page-provided links never authorize navigation: the
service worker constructs `https://www.youtube.com/watch?v=ID` from the validated
ID after immediately revalidating permission, the active source tab and Home
route, expiry, selected-item identity, and fresh title uniqueness when required.
Unrelated feed reorder/lazy-load churn and tab-title/index changes do not
invalidate an unchanged target.

`incognito` is `not_allowed`. The manifest has no required host access,
`activeTab`, content scripts, `externally_connectable`, or storage permission.
Its committed public manifest key gives the unpacked development build a stable
ID; it is not a credential and no private key is stored. Topher does not use
screenshots, Screen Recording, OCR,
cookies, history, account data, comments, descriptions, likes, subscriptions,
forms, page-authored scripts, arbitrary URLs, continuous observation, or
browser-context persistence.

## Setup from Topher

1. Build and launch `Topher.app`.
2. Open **Topher Settings → General → Chrome and YouTube** and press **Set Up**.
   If a previous Topher build moved, press **Repair**. Topher refuses to replace
   a conflicting or insecure registration.
3. Press **Open Chrome Extensions**, enable **Developer mode**, and choose
   **Load unpacked**.
4. Press **Show Extension Folder** in Topher and select the revealed
   `ChromeExtension` folder. The packaged extension ID is
   `mhbppdheppcibhhcnhnfockmfpcfhndj`; reload it after updating the app.
5. Click Topher's extension button and choose **Grant YouTube access**. Chrome
   owns this separate optional permission prompt. The popup also removes access
   and shows its current state.

Topher Settings reports these layers independently: local native-host
registration, live extension connection, and the one optional YouTube-access
bit. The status request reads no tab or page content.

Topher's Set Up action writes only the per-user native-host manifest after the
explicit button press. It never enables Developer mode, loads the extension,
or grants page access on the user's behalf.

## Checked command-line setup

The registration and optional permission are local Chrome state and are never
committed. These steps do not install or replace `/Applications/Topher.app`.

1. Build the app bundle from the repository:

   ```sh
   xcodebuild -project Topher.xcodeproj -scheme TopherApp \
     -configuration Debug -derivedDataPath /tmp/topher-chrome-debug build
   ```

2. Open `chrome://extensions`, enable **Developer mode**, choose **Load
   unpacked**, and select this repository's `ChromeExtension` directory.
3. Confirm Chrome shows the packaged ID
   `mhbppdheppcibhhcnhnfockmfpcfhndj`.
4. Register the packaged extension origin and the absolute helper path in that
   built app:

   ```sh
   scripts/chrome_native_host.rb install \
     --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app

   scripts/chrome_native_host.rb check \
     --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app
   ```

5. Launch that exact `Topher.app`, keep Chrome running, and use Topher's manual
   command field for the checklist below. Re-register or use **Repair** after
   changing the app bundle path.
6. For the YouTube slice, click the Topher extension button and choose **Grant
   YouTube access**. If denied, reopen the popup and try again. If access was
   removed in Chrome's site settings, the popup returns to the not-granted
   state; grant it again explicitly.

The helper writes only
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.topher.chrome_bridge.json`
with mode `0600`. Its `allowed_origins` contains exactly the packaged
`chrome-extension://mhbppdheppcibhhcnhnfockmfpcfhndj/` origin and `path` is the
checked absolute path to `Topher.app/Contents/Helpers/TopherChromeBridgeHost`.
The app revalidates both before accepting the launch-scoped socket handshake.

Remove only the matching registration with:

```sh
scripts/chrome_native_host.rb uninstall \
  --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app
```

Then remove the unpacked extension from `chrome://extensions`, or use the
extension popup to remove only YouTube access while retaining tab metadata.

## Focused manual checklist

1. Open ordinary `https` tabs with one unique title and two duplicate titles;
   keep an incognito window open separately.
2. Ask “What is this Chrome tab?”, “What tabs do I have open?”, and “Switch to
   the Chrome tab titled *unique exact title*”. Confirm bounded reads and one
   exact activation; duplicates, incomplete observations, incognito, stale
   targets, and unsupported schemes must fail closed.
3. Remove YouTube access in the popup, ask “What's on my YouTube feed?”, and
   confirm Topher says how to grant access without inspecting the page.
4. Grant access, make YouTube Home the active regular Chrome tab, ask again,
   and confirm Topher shows at most 20 numbered title/channel rows. A bounded
   result must say so. The transient HUD should remain concise.
5. Click a listed row or say “Open the third one.” Confirm the source feed is
   revalidated and its tab navigates exactly once. Ask for the feed again, then
   say “Open the YouTube
   video titled *exact listed title*.” Confirm normalized exact matching;
   duplicate titles refuse and request a number. Also ask “What’s YouTube
   recommending?”, say “Open that video,” then answer “number three.” Repeat with
   “Open video three,” “the third one,” and one bare exact title. Pronouns without
   a feed must request a fresh list instead of searching Google. A phrase that
   could mean different ordinal and title targets must refuse and ask for an
   explicit form. Also try “the last one”; with a one-item list, “open that
   video” is unambiguous, while a multi-item list must still ask which one.
6. Read the feed, then navigate, switch tabs, remove permission, let 90 seconds
   pass, or remove/change the selected item before the follow-up. Confirm Topher
   asks for a fresh feed and performs no navigation. Separately reorder the tab
   or allow an unrelated recommendation to lazy-load/change; an unchanged
   selected item should still open once.
7. Repeat the read on a watch, search, Shorts, non-YouTube, and incognito page.
   Confirm Topher asks for YouTube Home and never falls back to Accessibility,
   screenshots, OCR, or broader page reading.
8. Disable/remove the extension, stop Chrome, or unregister the host. Confirm a
   recoverable fixed failure. Restart or reload the extension around requests
   and confirm no mutation is replayed after an unknown dispatched outcome.
9. Stream Unified Logging and confirm no tab URL, feed title, channel, video ID,
   or destination URL appears. If the explicit content-bearing developer trace
   is enabled, it may retain the user-authored command, including a title the
   user spoke, but never appends the feed snapshot or browser-returned values.

Automated tests exercise manifest scope, permission grant/removal helpers,
sanitized DOM fixtures, extractor and protocol bounds, hostile values, strict
routes/video IDs, version mismatch, cancellation, timeout, duplicate IDs,
separate presentation/title completeness, staleness, permission revocation,
target versus unrelated DOM drift, authenticated socket
framing, primary-only relay ownership, one-shot mutation, and unknown
post-dispatch outcomes. They do not prove live Chrome/YouTube acceptance in a
user's profile.
