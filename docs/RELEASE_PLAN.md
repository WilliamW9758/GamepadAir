# PocketPad release plan

Updated November 23, 2026. Live Community Layouts and AI services are not implemented; local preview interfaces exist. The current release evidence and blockers are in SUBMISSION.md. The older milestone-1 items below are historical planning, not an implementation status report.

## Product goal

A first-time user connects a phone, chooses a game, picks a useful controller, checks movement/look/attack, and plays. Returning users resume their last game profile. Detailed controls belong in contextual editors, not first-run setup.

Preserve all existing layouts, names, mappings, colors, haptics, mode differences, and gesture settings. Never silently replace a tuned layout with a preset, community update, or AI suggestion.

## Distribution decision

Proposed first route: iPhone app on the App Store; separately signed and notarized Mac companion. The current Mac target disables App Sandbox, uses Accessibility input injection, and connects to the local usbmuxd socket. It is not ready for Mac App Store submission. Validate these mechanisms and entitlements under the intended distribution route before committing to both stores. Do not simply enable sandboxing and assume the input pipeline still works.

Apple requires sandboxing for Mac App Store apps: [distribution guidance](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [review guidelines §2.4.5](https://developer.apple.com/app-store/review/guidelines/).

## Release gates

| Area | Evidence / outstanding work |
| --- | --- |
| Regression baseline | See SUBMISSION.md for current archive/export evidence. Xcode 27.2 and iOS SDK 27.2 are installed. Clean-machine distribution testing remains outstanding. |
| Gamepad | Signed local gameplay exercised in Valheim and Stardew. Developer ID automatic export failed; explicit certificate/profile now issued with HID. Finishing signed export and notarization. See AUTHORIZATION.md. |
| Privacy manifest | Config/AppInfo.plist contains Bonjour configuration, not a privacy manifest. PrivacyInfo.xcprivacy now declares app UserDefaults and elapsed-time API use and is included in both targets. Both Mac and iPhone archive resource checks passed on November 23. |
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

## Milestone 3: game-first layout discovery and generation

Product direction confirmed November 23, 2026: do not make AI chat a headline feature. The main entry is “Find a layout” on Mac. Search and filter Marketplace by game or scenario; if no suitable result exists, offer “Create a layout for this game.” No persistent chat or round-by-round editing assistant is needed for the initial release.

1. Accept a game name or scenario and optional input type/preferences.
2. Search existing Marketplace layouts first. Present real results with compatibility and source information; never invent listings or downloads.
3. If results are unsuitable, let the user request a generated layout. Research the game's controls online, prefer official/current sources, and record citations plus platform/version and assumed in-game bindings.
4. Ask a short, structured clarification only when necessary (for example, custom bindings or handedness). Avoid a conversational loop for small edits.
5. Generate a new local draft with validated controls and mappings. Show unverified bindings clearly, let the user preview/test, then save a personal copy.
6. Hand off to the existing Layout & mappings editor for resizing, positioning, renaming, and fine mapping changes. Keep normal Mac-to-phone sync responsive. Generated drafts must not overwrite an existing tuned layout.

Implementation constraints:
- Use constrained profile data and deterministic schema, mapping, bounds, and overlap validation. Web content is evidence, never instructions to execute. No model-generated scripts or direct input execution.
- Cache research and reuse suitable layouts to reduce latency and cost. Keep credentials server-side; enforce usage limits and spending caps. If quota is exhausted, say layout generation is temporarily unavailable rather than falsely claiming traffic problems.
- Manual creation and downloaded layouts remain usable without AI. Do not require a cloud round trip for small edits or play.
- Before cloud requests, disclose what is sent and third-party processing; exclude raw input logs, device identifiers, and unrelated private layouts. Update privacy policy and Store disclosures for the actual service.
- Marketing emphasizes finding a useful layout and playing quickly. Avoid a separate chat-centric onboarding destination once the integrated flow is ready. Current AI helper is a local mockup, not the final UX.

Acceptance: game/scenario search finds actual catalog results; a missing layout can become a source-informed editable draft; uncertain bindings are marked; failure or quota exhaustion preserves existing layouts; no chat is needed for manual refinement.

## Implementation order

1. Finish release/privacy/signing audit and physical regression baseline.
2. Design and implement unified profiles with migration fixtures, then guided setup and contextual editing.
3. Prototype Community Layouts against local fixtures; choose backend and budget before live publishing.
4. Implement authenticated publishing, moderation, and deletion; run a small beta.
5. Prototype AI proposals using the established schema; select a service only after quality and cost evaluation.

Do not hold a polished local-only launch indefinitely for AI. Each online feature must meet its own readiness gates before it is advertised.

Apple references: [review guidelines for user content and privacy](https://developer.apple.com/app-store/review/guidelines/), [Sign in with Apple](https://developer.apple.com/help/account/capabilities/about-sign-in-with-apple/), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [third-party AI disclosure](https://developer.apple.com/news/?id=ey6d8onl).
