# Risk register

| Risk | Current evidence | Mitigation / next proof |
|---|---|---|
| Speech accuracy and latency | No user recordings measured. Upstream benchmarks are not representative. | Run the fixed corpus and select only from local results. |
| Permission reliability | A fixed Topher bundle now runs from `/Applications`, but Slice 1 requests no microphone access and local signing is ad hoc. | Add a stable Apple signing identity, `NSMicrophoneUsageDescription`, and the Hardened Runtime audio-input entitlement before speech; request incrementally, implement denial recovery, and run the Xcode-versus-`/Applications` TCC matrix. |
| System model availability | Runtime reports `appleIntelligenceNotEnabled`. | Deterministic commands are complete without it; gate every model use at runtime. |
| Application-name resolution | Speech may vary names; arbitrary app lookup can open an unintended target. | Explicit aliases and bundle IDs now; measured vocabulary and validated discovery later. |
| Prompt injection | Future web, screen, and document text is untrusted. | Separate instruction/data channels; typed proposals; policy independent of model; never execute code/scripts from content. |
| Browser integration complexity | YouTube feed questions require structured DOM data and Chrome native messaging. | Defer until core loop is reliable; minimal MV3 permissions; return data, never arbitrary JavaScript. |
| Search query disclosure | Topher does not log search text, but an explicitly executed search sends it to Google or YouTube through the default browser. | Keep providers and endpoints fixed, label the capability sensitive, execute only explicit typed searches, and make the external handoff visible in the result. |
| Always-on energy | No local measurements; wake word and ambient capture are separate systems. | No ambient mode in MVP; later measure false accepts/rejects and power before enabling. |
| Toolchain reproducibility | Xcode 26.6 is selected; SwiftPM tests and Debug/Release app builds pass. | Keep package pins and shared scheme; add a clean-machine or CI build before wider distribution. |
| Local signing and distribution | Release is hardened and ad-hoc signed; strict `codesign` verification passes, but it has no Developer ID or notarization. | Treat this build as local-only. Use Developer ID signing and notarization before sharing it with other Macs. |
| Shortcut conflicts | No default chord can be assumed safe. | User-recorded standard modified shortcut and conflict UI; no Fn/modifier-only interception. |
| Menu-bar lifecycle | The installed app registers as a UI element, creates its status-item scene, remains alive, and passed the initial manual shortcut/command check. | Exercise removal, relaunch, sleep/wake, and onboarding before relying on persistent background use. |
