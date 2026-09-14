# OneBox Repository Instructions

Before changing code, establish the requested outcome, supported scope, and observable success criteria. Read `README.md`, `docs/engineering.md`, the relevant architecture or module contract, and affected ADRs.

## Invariants

- The host composition root is the only place that registers concrete tool modules.
- Product code is Swift; use SwiftUI by default and AppKit only for macOS capabilities SwiftUI does not cover.
- Tool modules do not import one another or the host implementation.
- Host and platform capabilities are injected through narrow interfaces.
- Do not introduce dynamic plugins, remote code loading, process isolation, or a new shared module without a current requirement and an accepted ADR when the architecture changes.

## Execution

- For explanation, review, diagnosis, or planning, inspect and report only. For implementation, fix, or build requests, make scoped local changes and run non-destructive checks.
- Inspect existing code and dependencies before adding a package or writing a replacement. Prefer maintained, proven libraries.
- Report realistic reachable problems; do not add defenses for states outside the supported scope.
- Confirm before external writes, destructive operations, paid actions, or material scope expansion.
- Match verification to the changed behavior. Shared interfaces require checks for every current consumer; unaffected checks need not be repeated.
- Lead the final response with the result, followed by necessary evidence, impact, unverified items, and the next step.
- Deliver runnable local builds with `scripts/build-release.sh` and `dist/OneBox.app`, which includes verified PodPin media tools. Raw DerivedData builds are development/profiling artifacts and must not replace the complete app handed to the user.

## UI authority

- BoardUI is the visual and motion reference for the native SwiftUI application. Read [the native mapping](docs/boardui-native.md) before changing interface styling.
- Use OneBoxDesignSystem semantic tokens, typography and shared controls. Compare source recipes and rendered states instead of inventing a parallel visual system.
- BoardUI React initialization and downloaded reference components belong in the isolated `.build/BoardUIReference` directory. The production application remains Swift; do not add a web runtime or run the React initializer at the repository root.
- Actual current BoardUI component source takes precedence when its skill prose is stale. Preserve keyboard input, accessibility, Reduce Motion and the existing tool lifecycles during native adaptation.
