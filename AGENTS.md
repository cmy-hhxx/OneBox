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
