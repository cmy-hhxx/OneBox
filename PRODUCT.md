# Product

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS 15+ on Apple Silicon; SwiftUI with AppKit and Metal for platform capabilities.

## Users

OneBox serves its local owner, who switches among small creative, market-information and audio tasks and uses in-app diagnostics to iterate on failures.

## Product Purpose

Keep ASCII image creation, a personal stock watchlist and an audio library in one consistent desktop application. The current redesign must visibly improve the complete interface and preserve working features. After earlier iterations, the user explicitly selected BoardUI and confirmed a faithful native SwiftUI adaptation of its complete visual and motion language.

## Capabilities and Constraints

Three statically registered Swift tool packages share a host and design system. Tool implementations do not import one another. Native inspectors push content; sheets are reserved for tasks with a commit/cancel boundary. The stock tool only works while mounted. PodPin may continue user-started playback and downloads. Diagnostics retain up to 500 events in memory and preserve original errors after sensitive-field redaction.

## Brand Commitments

Keep the OneBox name and existing box mark. Use the installed BoardUI free component sources, semantic tokens, Inter 4.1 typography and motion as the current visual authority. Preserve Chinese interface copy with system glyph fallback, SF Symbols, native editing, menus, sheets and macOS interaction conventions. The reference React project stays in the ignored build directory; product UI remains SwiftUI.

## Evidence on Hand

README.md, docs/architecture.md, docs/module-contract.md and current source define supported behavior. The user supplied a screenshot of the existing stock interface as a problem example. It is not a target mockup. The official BoardUI MCP initialized .build/BoardUIReference and installed the actual free component sources. docs/boardui-native.md records their native mapping and the retained operating-system presentation boundaries. Earlier Uiverse iterations are provenance, not an active design contract.

## Product Principles

- Make the current task, primary action and data state readable at a glance.
- Give all three tools the same BoardUI navigation, controls, typography and motion vocabulary.
- Preserve original diagnostic evidence and make copying it immediate.
- Judge improvements from real rendered windows and supported window sizes.

## Accessibility & Inclusion

Keep readable text, keyboard actions, native focus feedback, Reduce Motion support and explicit labels on icon controls. Dark mode remains a development preview; the delivered interface is light.
