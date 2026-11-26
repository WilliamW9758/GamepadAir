# Adopting the shared layout document in the app

Decision and implementation: November 24, 2026.

The canonical model is now wired through both app targets. `SavedLayout`, the legacy catalog,
profile exchange, coordinate migration and standalone mapping-editor paths have been removed.
`LayoutDocumentStore` owns atomic persistence/history; editors mutate the document; runtime
profiles and `ResolvedLayoutMode` are disposable projections. Sync envelopes use protocol 6,
local edit revisions and bounded idempotency acknowledgments. Downloads and file imports share
the same strict decoder and allocate fresh local wrappers.

Verification: both signed targets build; Swift and Python suites pass; a real PostgreSQL/API
response matches the file fixture in Swift. Physical-phone acceptance is pending an unlocked
Air. No new TestFlight release has been uploaded for this refactor.

The sections below retain the design requirements and code touchpoints for maintenance.

## Target architecture

    API/file JSON → bounded decode + validation → LayoutDocument
                                                    │
                                 LocalLayout wrapper / catalog
                                                    │
                          document editor + undo/redo + sync
                                                    │
                                resolved runtime view (derived)
                                  /                         \
                         canvas renderer                 input mapper

The schema in layout.schema.json is the contract. Swift Codable types represent it, while Python
validates the same fields and rules. One schema does not mean one language implementation. Share
positive/negative fixtures to keep semantic validation aligned. Swift decoding must reject unknown
fields, invalid references and unsupported features; plain synthesized Codable alone is not enough.
Preserve omitted versus explicit-null overrides so base inheritance and resetting defaults differ.
Apply defaults in a resolver, without rewriting the document on every load. Specify RFC 8785
canonical serialization separately from ordinary JSONEncoder formatting before computing digests.

## Refactor sequence and code touchpoints

### 1. Shared document and edit commands

Add LayoutDocument and its action/control/mode/settings types in GamepadCore. Use document-local
IDs throughout. Keep the current one/two-mode capability limit, but make iteration and selection
ID-based, not `1 - index`. Capability limits can expand later without redesigning persistence.
Implement strict structural and semantic validation with the four existing fixtures plus common
negative cases. Add action-aware edit commands before connecting UI bindings to the new types.

Policy: caption/geometry edits leave actions intact. A single-reference rebind updates its action;
a shared-reference rebind clones and repoints only that reference. Preserve descriptive labels,
including on clones; assign a unique stored ID. Count auto-run references too. If a visible custom
button and radial direction intentionally share that same control slot, they remain one source:
editing its binding affects both entry points. Independent radial bindings would require separate
custom slots and an explicit UI operation, not a hidden allocation.

Remove the proposed metadata sidecar. The document itself owns action metadata. Runtime caches
must be invalidated after edits and may not write mappings back into the canonical document.

### 2. Persistence, presets and history

Replace the persisted SavedLayout/LayoutLibrary representation in GamepadState.swift with a
LocalLayout wrapper containing the document and local-only state. Replace LayoutCatalog storage
and LayoutHistory snapshots accordingly. Presets become actual validated documents instead of
implicit starter-profile fallbacks. Hidden/unmapped defaults are explicit in runtime resolution.

LayoutStore in Apps/iPhone/GamepadApp.swift must load a new storage key, save canonical wrappers,
and update create/duplicate/delete/select/undo paths. Old development layouts are not migrated.
A duplicate has a new local UUID but preserves IDs scoped inside its document. Source provenance
remains attached as origin information, not a claim that the edited copy still matches the source.
Use a local edit revision for conflict detection; keep the downloaded digest unchanged as origin.
Save atomically and validate before replacing catalog state. Bad new-format data must not trigger
a destructive reset. Selection and active mode belong to local/session state, not publication JSON.

### 3. Rendering and editors

TouchPadView currently reconstructs preset controls from fixed IDs and per-style LayoutLibrary.
Make it consume a resolved control list with document IDs, roles, effective mode overrides and
shared geometry. Extract the current full-canvas geometry math into GamepadCore so the phone
renderer and Apps/Mac/LayoutEditor.swift use the same placement/radius calculations.

Both editors must edit LayoutDocument through commands rather than mutating KeyboardProfile,
GamepadProfile or style-indexed placement dictionaries. Replace index-based mode assumptions with
mode-ID lookup; preserve optional overrides and null resets. One mode remains one stored mode.
Remove legacyCanvas conversion/UI guards as these paths are replaced. Do not require historical
canvas dimensions, preserve inactive style dictionaries or migrate old 78-point-header positions.

### 4. Input runtime

KeyboardMapping.swift and GamepadMapping.swift currently read separately saved profiles. They
may initially accept compiled in-memory profiles produced from the document; these are execution
structures only, never a parallel persistence format or the editor's source of truth.
Compile all mappings explicitly, including empty bindings, and honor settings from the document.
Resolve control roles/custom slots consistently for phone touch input and Mac output. Preserve
radial slot aliasing and gamepad remapping restrictions. Release held keys/buttons and clear gesture
state before changing layout, active mode, backend, or compiled bindings to prevent stuck input.

The existing compact GamepadState input transport need not become layout JSON: it carries live
input events/state, not an alternative layout definition. Fixed roles/slots remain runtime limits.

### 5. Mac/phone synchronization

ControllerSnapshot, LayoutSummary and LayoutCommand in WireProtocol.swift currently embed
SavedLayout or compare full old snapshots. Carry the shared document inside a versioned session
envelope, with local layout ID, active mode ID and base edit revision. Validate incoming commands
before mutation and keep command IDs/acknowledgments for idempotency. Reject stale edits rather
than overwriting newer changes. Do not use the marketplace revision as the local edit revision.

Update CableSession, the phone command handler and Mac layout editor together. Bump/handshake the
layout-sync protocol so mismatched development builds produce a clear version error. Keep pairing,
transport credentials and device/session state outside downloadable documents. No backward wire
compatibility with the earlier development representation is required.

### 6. File and marketplace loading

Replace file exchange via PortableProfile and catalog-file imports with LayoutDocument JSON.
On load: enforce byte limits, validate, allocate a fresh local wrapper, then save/select only after
success. Export the document directly, excluding local wrapper and marketplace fields. Downloads
use exactly this path and attach source metadata outside the document. No SavedLayout conversion.

Apps/Mac/MacGamepadApp.swift currently also stores standalone mappings and a PortableProfile:
replace their authoritative storage with the local canonical document rather than updating two
copies. Keep settings unrelated to layouts (pairing, target app, permissions) independent.
The read-only API routes need no architectural change; align database schema-version validation
and seed content with the accepted contract. Earlier development rows may be reset/reseeded during
cutover, never rewritten under an immutable revision URL. No AWS deployment is needed for this work.

## Completion checks

- Swift and Python agree on the shared accepted/rejected fixture corpus.
- Document decode/encode and local save/load preserve actions, IDs, overrides and settings.
- Rebinding one shared action reference leaves other references unchanged; undo restores both.
- Caption/position edits and duplication preserve action identity and descriptive names.
- Rendered placements and active mappings match all four fixtures on representative canvases.
- No implicit native-button, number-key or auto-run fallback becomes active.
- Two-device edits reject stale bases and do not leave held outputs across transitions.
- File load and local API download produce the same canonical document in a fresh local wrapper.
- Unknown/legacy input and corrupt canonical storage fail without modifying saved state.
- Mac and iPhone targets build and an actual phone/Mac local end-to-end flow passes before AWS.

## Scope boundary

This refactor removes the need for a permanent layout importer/converter and metadata sidecar.
It does not itself enable arbitrary mode counts or mixing mappings across modes. Named mode IDs
and a local wrapper provide a path to future collections of independently downloaded layouts;
that feature still needs explicit switching semantics, UI and capability-profile changes.

### Motion activation (November 25, 2026)

`motion.activationControl` optionally references a document-local button/trigger ID
(including custom buttons). Omission retains right-trigger activation. The selected
control keeps its ordinary mapping. Removing that control turns motion off. Both
editors expose this setting and the phone tests the held control before mappings.
The shared schema and local Python validator/tests accept and validate the reference;
the matching backend validator is deployed at https://api.gamepadair.com (image
`beta-20261125-gyro-01`, digest
`sha256:80274e88a2346be96f2516cacd6f5dd2187c77a39eacb22bd25cbbd599bf2de4`).
The release changes only the validator and schema over `beta-20261125-01`, with no
database migration. Local format tests (47), live acceptance/rejection checks and
public readiness passed. A subsequent signed-in Mac app test submitted
“Gyro activation test 2026-11-25” with `motion: {mode: "aim", activationControl: "lefttrigger"}`.
AWS accepted revision 1 as pending; Download a copy returned an exactly equal full
document to the local library. Test listing `7f1ce47b-2ad2-4c68-8743-1a4bab1d7d33`
was then removed through the app and its public detail returns 404. It was not
approved or publicly published. Two local test copies remain for inspection.
The submissions page also displays an unrelated unavailable-feature notice because
its newer moderation/account UI calls endpoints absent from this schema-only deployment.

### Explicit control size

`placement.diameter` sets a round control's diameter in points (44–240), independent
of its role, legacy scale, and mode sizeFactor. Omission preserves existing sizes.
Both editors show numeric point sizes and use 1-point adjustments. Moving a control
preserves its diameter; linked modes share the explicit point size. Rectangular
controls continue using width/height. Canvas fitting and the four-way D-pad's
minimum touch extent still apply.

A signed-in Marketplace round-trip on 2026-11-25 submitted “Button size round-trip
test” with A at 70 pt, LT at 138 pt, and View at 58 pt. Download a copy returned an
exactly equal canonical document, including all three explicit diameters. The
pending test submission was removed through the app without public publication;
the two local test copies remain for inspection.
