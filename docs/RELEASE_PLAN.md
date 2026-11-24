# PocketPad release plan

Audit date: November 6, 2026. This is a proposal and release checklist, not a claim of App Store readiness. Community Layouts and AI assistance are not implemented.

## Product goal

A first-time user connects a phone, chooses a game, picks a useful controller, checks movement/look/attack, and plays. Returning users resume their last game profile. Detailed controls belong in contextual editors, not first-run setup.

Preserve all existing layouts, names, mappings, colors, haptics, mode differences, and gesture settings. Never silently replace a tuned layout with a preset, community update, or AI suggestion.

## Distribution decision

Proposed first route: iPhone app on the App Store; separately signed and notarized Mac companion. The current Mac target disables App Sandbox, uses Accessibility input injection, and connects to the local usbmuxd socket. It is not ready for Mac App Store submission. Validate these mechanisms and entitlements under the intended distribution route before committing to both stores. Do not simply enable sandboxing and assume the input pipeline still works.

Apple requires sandboxing for Mac App Store apps: [distribution guidance](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [review guidelines §2.4.5](https://developer.apple.com/app-store/review/guidelines/).

## Release gates

| Area | Evidence / outstanding work |
| --- | --- |
| Regression baseline | 78 Swift package tests and unsigned universal Mac Release build passed locally on November 6. iPhone Xcode build blocked by missing iOS platform component. Added CI for tests and unsigned Release builds; hosted execution not yet verified. |
| Gamepad | Development capability assigned; distribution request submitted. Signed runtime and game compatibility tests outstanding. See AUTHORIZATION.md. |
| Privacy manifest | Config/AppInfo.plist contains Bonjour configuration, not a privacy manifest. PrivacyInfo.xcprivacy now declares app UserDefaults and elapsed-time API use and is included in both targets. Mac archive resource checks passed; iPhone archive inspection remains blocked by its missing platform component. |
| Privacy disclosures | Publish privacy policy and support contact; add in-app links. Verify actual data flows before completing App Store privacy labels. Revisit when accounts or AI ship. |
| Security | Review pairing-secret storage, rate limits, wireless authentication, malformed input handling, and permission/focus gates. Keep server and signing secrets out of clients and Git. |
| Physical testing | USB/Wi-Fi/BLE on multiple devices; reconnect, sleep/wake, phone lock, backgrounding, permission denial/revocation, held-input release, menu pointer behavior, and sustained play. Record observed results. |
| Upgrade safety | Test old persisted catalogs and real exported profiles against migrations; backup before migration; preserve original data on errors. |
| Distribution | Validate archives, signing/provisioning, Mac notarization/stapling and clean-machine installation. Choose final bundle identity deliberately to avoid breaking installed data. |
| Store submission | Screenshots from real builds, accurate feature claims, age rating, encryption/export-compliance answers, support/privacy URLs, and reviewer instructions including how to obtain the companion. |

## Milestone 1: polish and unified game profiles

Ship a dependable local experience before adding online dependencies.

- One game profile owns actions, bindings, layout, and modes on both devices. Introduce versioned synchronization with explicit conflict handling and local offline copies.
- Actions such as Attack or Dodge have stable IDs. Controls invoke actions; editing one binding updates all controls that reference it.
- Connect → choose game → choose preset → optional essential-controls check → play. Global input remains an explicit option.
- Curated presets state the assumed in-game key bindings. Unsupported games start from a genre template or an empty controller.
- Edit a control in place. Show action/name/size first; expose advanced gestures, colors, and haptics on demand.
- New profiles share positions across modes by default. Existing profiles retain their current independent/linked behavior.
- Separate edit and test states clearly, retain undo, and offer per-control reset.

Acceptance: a new user can use a curated preset without manually creating buttons. Existing users keep identical behavior after upgrading. A profile can be copied, restored, and used offline without signing in.

## Milestone 2: free Community Layouts

Journey: choose game → browse previews → inspect bindings/compatibility → use a personal copy → optionally customize. Publishing is a separate deliberate action.

- Browse and download without an account; Sign in with Apple for publishing and managing uploads. Use a public nickname rather than exposing the Apple account name.
- Store validated declarative profiles only. The existing PortableProfile is a starting point, not yet a complete public-service trust boundary.
- Include stable publication ID, immutable revision, schema/minimum app version, game identity, input backend, description, author, and assumed game bindings.
- Downloads get new local identities and source attribution. Updates show differences and require adoption; never overwrite a personal copy automatically.
- Strip device addresses, pairing secrets, app paths, and permission state. Do not import global output authorization. Validate bounds, strings, action types, and payload size on client and server.
- Backend responsibilities: Apple token verification, ownership checks, database/storage, search, rate limits, moderation queue, deletion, backups, and operational cost limits.
- Include content filtering, reporting, blocking authors, moderation tools, public support contact, and in-app account deletion. Decide publication licensing and deletion behavior before launch. No comments/chat in the first release.
- Choose hosting only after establishing an operating budget and data-retention policy. No paid infrastructure is provisioned by this plan.

Acceptance: unauthorized users cannot edit another author's profile; malformed uploads fail safely; removed content stops appearing; imported layouts remain usable offline; account deletion is tested end to end.

## Milestone 3: optional AI layout assistant

Treat AI as a proposal editor built on the same action/profile system, not a separate controller engine.

Journey: choose game/template → describe needs (for example, larger attack button and one-thumb hotbar) → answer only missing binding questions → preview proposed changes → try → accept or undo.

- Start from curated or user-selected bindings. Never present guessed game bindings as verified. Mark uncertain actions and ask the user to confirm them.
- Model output is a constrained profile/change document, checked by deterministic validators. No scripts, shell commands, arbitrary URLs, or direct input execution.
- Generate into a draft; show additions, removals, changed bindings, and placement changes. Preserve the prior layout and require user acceptance.
- Keep generated controls within reach and bounds, detect overlaps, and honor selected handedness/control sizes. Geometry validation is independent of model output.
- Optional and failure-tolerant: manual editing and presets work when AI is unavailable or quota is exhausted.
- Before cloud AI, choose provider, retention, spending caps, and abuse limits. Keep provider credentials server-side. Show what will be sent; obtain explicit permission before sharing personal data with third-party AI. Do not send raw input history, device identifiers, or private layout libraries by default.
- Evaluate against a fixed set of game/action requirements, invalid output cases, and user editing tasks before exposing the feature publicly.

Acceptance: a model failure cannot corrupt a saved profile or emit input. Every accepted change can be undone. Uncertain bindings remain distinguishable from confirmed bindings.

## Implementation order

1. Finish release/privacy/signing audit and physical regression baseline.
2. Design and implement unified profiles with migration fixtures, then guided setup and contextual editing.
3. Prototype Community Layouts against local fixtures; choose backend and budget before live publishing.
4. Implement authenticated publishing, moderation, and deletion; run a small beta.
5. Prototype AI proposals using the established schema; select a service only after quality and cost evaluation.

Do not hold a polished local-only launch indefinitely for AI. Each online feature must meet its own readiness gates before it is advertised.

Apple references: [review guidelines for user content and privacy](https://developer.apple.com/app-store/review/guidelines/), [Sign in with Apple](https://developer.apple.com/help/account/capabilities/about-sign-in-with-apple/), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [third-party AI disclosure](https://developer.apple.com/news/?id=ey6d8onl).
