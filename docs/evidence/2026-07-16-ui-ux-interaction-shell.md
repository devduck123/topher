# UI/UX interaction-shell checkpoint

Status: automated and isolated render verification passed; installed status-item acceptance remains pending, 2026-07-16

## Scope

This checkpoint replaces the expanding all-in-one menu-bar panel with two
purpose-specific surfaces while preserving Topher's existing request, policy,
permission, and execution boundaries:

- a compact menu-bar control for phase feedback, assistant and dictation
  shortcuts, readiness, permission recovery, pending dictation, undo, settings,
  diagnostics state, and quit;
- a separate native settings window with General, Personalization, and
  Developer sections;
- an empty-by-default manual command field that trims input and refuses blank
  execution;
- the existing non-activating cross-app HUD without lifecycle or authority
  changes.

No new entitlement, TCC permission, network boundary, persistence sink,
capability, Dock presence, or external effect was added. `LSUIElement` and the
accessory activation policy remain unchanged.

## Automated verification

The following checks passed from the `codex/ui-ux-improvements` worktree:

```text
ruby scripts/check_dependency_parity.rb
  passed; KeyboardShortcuts 3.0.1 remains aligned

ruby scripts/check_dogfood_corpus.rb
  passed; 20 sanitized cases

ruby scripts/test_observed_query_export.rb
  passed

xcrun swift-format lint --strict -r Package.swift Sources Tests
  passed

swift test
  passed; 232 tests, 0 failures

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-ui-ux-rebased-debug build
  passed

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-ui-ux-rebased-release build
  passed; universal arm64/x86_64 bundle

codesign --verify --deep --strict <Debug and Release Topher.app>
  passed; both bundles satisfy their designated requirements

codesign -d --entitlements - <Debug Topher.app>
  passed; audio input and get-task-allow only

codesign -d --entitlements - <Release Topher.app>
  passed; audio input only

plutil -p <Debug and Release Info.plist>
  passed; LSUIElement remains true and bundle metadata remains aligned

git diff --check
  passed
```

The new regression test verifies that manual input starts empty, whitespace-only
input cannot enter command processing, and a nonempty command enables manual
execution. Existing exactly-once, command, dictation, permission, diagnostics,
and lifecycle tests remain green.

## Isolated render verification

An ephemeral Debug copy of the merged source hosted the production
`MenuContentView` and `TopherSettingsView` without installing or replacing
`/Applications/Topher.app`. The harness changed only its temporary activation
policy and window host; those changes are not part of this branch.

Computer Use verified:

- the compact control at the production 380-point width in dark and light
  appearances;
- the General, Personalization, and Developer settings sections at the
  production 760-point minimum window width;
- visible, labeled assistant and dictation shortcuts, microphone and
  Accessibility recovery actions, diagnostics state, settings, and quit;
- no horizontal clipping after constraining settings content to the viewport
  and moving stale-Accessibility recovery guidance below its action row;
- vertical scrolling for content that exceeds the available height;
- Accessibility-tree names and values for the phase, shortcuts, controls, and
  settings navigation; and
- keyboard focus moving in order through the personalization text fields.

The harness did not mutate microphone or Accessibility decisions, execute a
command, insert or copy dictation, or retain render screenshots in the
repository.

Still required as installed-app dogfood rather than a source-merge claim:

1. Verify the real menu-bar popover anchor and native Settings window from an
   installed, identity-stable bundle.
2. Exercise VoiceOver, larger text, increased contrast, reduced transparency,
   and reduced motion without changing the user's current system configuration
   during this checkpoint.
3. Verify permission grant, denial, stale-row recovery, and relaunch from both
   surfaces.
4. Verify pending-dictation review and undo without focus theft.
5. Verify multiple displays and every Dock position; the HUD itself was not
   changed in this checkpoint.
