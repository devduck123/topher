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

The primary Topher process creates its socket/token only for a resolved Chrome
request. Context is fetched on demand and never mirrored or stored by the
extension. Service-worker suspension can discard its in-memory duplicate cache;
the app never automatically retries a dispatched mutation, so restart does not
grant permission to replay an open.

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

The YouTube extractor is fixed, packaged, and limited to at most 20 visible or
nearby recommendation cards. It returns only a strict 11-character video ID,
bounded title, and bounded channel. Page-provided links never authorize
navigation: the service worker constructs `https://www.youtube.com/watch?v=ID`
from the validated ID after immediately revalidating permission, active source
tab, page URL/fingerprint, expiry, and selected-item presence.

`incognito` is `not_allowed`. The manifest has no required host access,
`activeTab`, content scripts, `externally_connectable`, extension key, or
storage permission. Topher does not use screenshots, Screen Recording, OCR,
cookies, history, account data, comments, descriptions, likes, subscriptions,
forms, page-authored scripts, arbitrary URLs, continuous observation, or
browser-context persistence.

## Development setup

The registration and optional permission are local Chrome state and are never
committed. These steps do not install or replace `/Applications/Topher.app`.

1. Build the app bundle from the repository:

   ```sh
   xcodebuild -project Topher.xcodeproj -scheme TopherApp \
     -configuration Debug -derivedDataPath /tmp/topher-chrome-debug build
   ```

2. Open `chrome://extensions`, enable **Developer mode**, choose **Load
   unpacked**, and select this repository's `ChromeExtension` directory.
3. Copy the 32-character extension ID Chrome shows. The repository deliberately
   has no manifest `key`, so no developer-specific unpacked ID is committed.
4. Register the exact extension origin and the absolute helper path in that
   built app:

   ```sh
   scripts/chrome_native_host.rb install \
     --extension-id YOUR_32_CHARACTER_ID \
     --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app

   scripts/chrome_native_host.rb check \
     --extension-id YOUR_32_CHARACTER_ID \
     --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app
   ```

5. Launch that exact `Topher.app`, keep Chrome running, and use Topher's manual
   command field for the checklist below. Re-register after changing the app
   bundle path or extension ID.
6. For the YouTube slice, click the Topher extension button and choose **Grant
   YouTube access**. If denied, reopen the popup and try again. If access was
   removed in Chrome's site settings, the popup returns to the not-granted
   state; grant it again explicitly.

The helper writes only
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.topher.chrome_bridge.json`
with mode `0600`. Its `allowed_origins` contains exactly the supplied
`chrome-extension://ID/` origin and `path` is the checked absolute path to
`Topher.app/Contents/Helpers/TopherChromeBridgeHost`. The app revalidates both
before accepting the launch-scoped socket handshake.

Remove only the matching registration with:

```sh
scripts/chrome_native_host.rb uninstall \
  --extension-id YOUR_32_CHARACTER_ID \
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
5. Say “Open the third one.” Confirm the source feed is revalidated and its tab
   navigates exactly once. Ask for the feed again, then say “Open the YouTube
   video titled *exact listed title*.” Confirm normalized exact matching;
   duplicate titles refuse and request a number.
6. Read the feed, then navigate, switch tabs, remove permission, let 90 seconds
   pass, or change the feed before the follow-up. Confirm Topher asks for a
   fresh feed and performs no navigation.
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
completeness, staleness, permission revocation, DOM drift, authenticated socket
framing, primary-only relay ownership, one-shot mutation, and unknown
post-dispatch outcomes. They do not prove live Chrome/YouTube acceptance in a
user's profile.
