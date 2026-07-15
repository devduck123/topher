# Decision 0001: Native Swift on stable macOS 26

Status: accepted, 2026-07-14

Use one Swift/SwiftUI macOS process targeting macOS 26. Use `MenuBarExtra` now
and AppKit only for native boundaries or a future focused overlay. Package
dependencies through Swift Package Manager.

This Mac is already on 26 and stable Apple speech/Foundation Models APIs exist
there. A lower target buys unsupported-machine compatibility at the cost of a
bundled speech runtime. macOS 27 beta adds conveniences and generic protocols
but no required MVP capability.

Rejected now: Electron/JavaScript, Python helper, Rust/C++ service, lower target,
and macOS 27-only baseline.
