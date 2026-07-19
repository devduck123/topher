# Topher Chrome context extension

This unpacked Manifest V3 extension is the browser half of Topher's first
structured Chrome context slice. It exposes only on-demand tab metadata and one
tab-activation operation to the local Topher app through Chrome native
messaging. It has no popup, content script, host access, page-body reader, or
remote service.

## Mental model

For a web developer, the extension service worker is a small browser adapter,
the bundled `TopherChromeBridgeHost` executable is a framed-JSON relay, and the
Topher app is the policy-owning local service. Chrome starts the native host;
the host never starts or installs Topher.

```text
Topher command and policy
  -> ephemeral Unix socket (0700 directory, launch token)
  -> bundled TopherChromeBridgeHost (bounded JSON relay only)
  -> Chrome native-messaging port
  -> MV3 service worker
  -> chrome.tabs / chrome.windows for the requested operation
```

The native port can remain idle, but the primary Topher process creates its
socket/token only for the first resolved Chrome request and tab data is acquired
only for an active request. Neither side mirrors tabs continuously or persists a
browser snapshot.

## Permissions

`manifest.json` requests exactly:

- `tabs`, to read the sensitive `title` and `url` properties returned by
  `chrome.tabs.query()` and to activate one revalidated tab; and
- `nativeMessaging`, to connect the service worker to the registered local
  helper.

`incognito` is `not_allowed`. The manifest intentionally contains no
`host_permissions`, `activeTab`, `scripting`, content scripts,
`externally_connectable`, extension key, or storage permission. Topher does not
use DOM/page-body extraction, `executeScript`, screenshots, cookies, history,
forms, file URLs, or browsing-history persistence in this slice.

## Development setup

The registration is local machine state and is never committed. These steps do
not install or replace `/Applications/Topher.app`.

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
   transcript field for the checklist below. Re-register after changing the app
   bundle path or extension ID.

The helper writes only
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.topher.chrome_bridge.json`
with mode `0600`. Its `allowed_origins` array contains exactly the supplied
`chrome-extension://ID/` origin and its `path` is the checked absolute path to
`Topher.app/Contents/Helpers/TopherChromeBridgeHost`. The app revalidates both
values before accepting the host's launch-scoped socket handshake.

Remove only the matching registration with:

```sh
scripts/chrome_native_host.rb uninstall \
  --extension-id YOUR_32_CHARACTER_ID \
  --app /tmp/topher-chrome-debug/Build/Products/Debug/Topher.app
```

Then remove the unpacked extension from `chrome://extensions` if desired.

## Focused manual checklist

1. Open a few ordinary `https` tabs, including one unique exact title and two
   tabs with the same title. Keep an incognito window open separately.
2. Ask “What is this Chrome tab?” and confirm Topher shows the active regular
   tab's bounded title and origin.
3. Ask “What tabs do I have open?” and confirm the result is bounded, excludes
   incognito and unsupported schemes, and does not contain page-body text.
4. Ask “Switch to the Chrome tab titled *unique exact title*” and confirm that
   tab and its window become active once without navigation or reload.
5. Use the duplicate title and confirm Topher refuses ambiguity without
   switching either tab.
6. If practical, open more than 50 supported regular tabs and confirm activation
   refuses because the bounded observation cannot prove global uniqueness.
7. Close or navigate the target during a request if practical and confirm the
   request refuses a missing/stale target rather than guessing or retrying.
8. Disable/remove the extension, stop Chrome, or unregister the host in turn;
   confirm Topher reports a recoverable fixed failure and never falls back to
   Accessibility, screenshots, or broader browser control.
9. Stream Unified Logging and confirm no tab title or URL appears. If developer
   transcript diagnostics are enabled, confirm they retain only the
   user-authored command; browser-returned titles and URLs are not appended.

Automated tests exercise the manifest, URL/title bounds, malformed messages,
the composed 64-KiB message cap, tab-list bounds, incognito and scheme
exclusion, version mismatch, cancellation, staleness, duplicate request IDs,
observation completeness, authenticated socket framing, primary-only lazy relay
construction, one-shot mutation, and unknown post-dispatch outcomes. They do not
prove live Chrome/native-host acceptance on a user's
profile.
