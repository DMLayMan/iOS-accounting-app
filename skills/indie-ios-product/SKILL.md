---
name: indie-ios-product
description: Design, refine, and deliver independent iPhone utility apps with practical features, low-friction native UX, reusable components, local-first data, and evidence-based acceptance. Use for new app or feature design, interaction review, or an end-to-end iOS delivery plan; not for isolated syntax fixes or backend-only work.
metadata:
  short-description: 独立 iOS 应用的产品设计、体验审查与高效交付
---

# Independent iOS Product

Use this skill to reduce product rework, not to add ceremony. The source experience is a personal accounting app; its exact category model, colors, tab layout, and sheet sizes are examples, not defaults for every app. Honor the current user's decisions and repository conventions.

## Start with the decision that matters

Read the current product/design documents, relevant code, and current native evidence. For a new app, establish the primary user task, frequency, interruptions, data sensitivity, and delivery target. Keep low-risk assumptions explicit and move forward; resolve decisions that would change the data model or destroy existing user work before implementing them.

Route narrowly:

- New app, ambiguous feature, “ugly”, or awkward navigation: read [product and UX](references/product-and-ux.md). Use the [feature brief](assets/feature-brief.md) only for a meaningful new capability.
- Shared components, data, or native implementation: read [architecture and delivery](references/architecture-and-delivery.md). Describe ownership and failure behavior before extracting abstractions.
- Visual review, testing, handoff, or release: read [review gates](references/review-gates.md). Choose evidence proportional to the change; a one-line copy fix does not need the entire app test suite.
- Need a reproducible page specification: use [page contract](assets/page-contract.md). Need a delivery receipt: use [delivery record](assets/delivery-record.md).

Do not read every reference or generate every template for every task. On an existing app, update its canonical documents instead of creating a parallel specification system.

## Decision rules

1. Write the user task before choosing a control. Explain what the user will see, decide, do, and get back. A beautiful default screenshot does not establish a good flow.
2. Separate domain concepts, ways to find them, and personal notes. Merge concepts only when their meanings and cardinalities overlap. Quick picks, search, and management may be entrances to one entity collection.
3. Classify a transition as filtering, editing, or navigating to an object. Filtering usually stays in context; a bounded temporary task may use a sheet; a durable object may warrant a detail page. Do not solve every complaint by adding a sheet or hard-coding 70% height.
4. Design new/edit/dirty/keyboard/error/return states together. Durable save success controls dismissal. Preserve input on failure and specify who owns each draft. Optional advanced features should not obstruct the first useful action.
5. Use familiar native structure, restrained hierarchy, semantic typography, and meaningfully distinct colors. Separate accent, data series, and status colors. For motion and gestures, define purpose, discoverability, cancellation, and accessibility alternatives.
6. Research a concrete uncertainty. Record what was actually seen and what remains inferred. If an approach is rejected twice, revisit the task and evidence before generating another cosmetic variant; this is a diagnostic default, not a user approval gate.
7. Reuse behavior and state contracts, not just shapes. Keep a single authoritative calculation for a metric, a single owner for shared context, and explicit inputs/outputs for shared components. Avoid speculative frameworks.
8. Local-first still needs failure recovery, data compatibility, and test isolation. Do not open a writable empty store when reading an existing store fails. Never let invalid test configuration silently choose the personal repository.
9. Deliver a small vertical slice through entry, save, readback, edit, interruption, and recovery before expanding features. Prototype uncertain layout cheaply; validate keyboard, drag, sheets, scrolling, and native materials in the actual iOS app.
10. Review the experience yourself. In a UI batch, inspect the relevant native states together, fix the observed problems, and confirm the fixes. Avoid indefinite subjective polishing; real functional failures still need closure. A test count cannot prove beauty or human task speed.

## Output and stopping

For design work, provide the selected flow, a concrete representation, reasons for its tradeoffs, and unresolved assumptions. For implementation, provide changed behavior, evidence, current documentation, and remaining limits. Scope the output to the user's request.

Distinguish proposed design, implemented code, simulator acceptance, physical-device acceptance, and distribution. Inspect actual remote CI and publication state before claiming those outcomes. This skill grants no additional permission to push, merge, publish, message others, or change accounts.

When other design skills are already available, use them for their specialized visual or platform review as needed; do not install dependencies or rewrite global configuration just to use this skill.
