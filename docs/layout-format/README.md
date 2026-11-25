# Portable layout format — revised runtime contract

Status: **adopted by the Swift clients, November 24, 2026; physical-device acceptance pending.**
`layout.schema.json` is the shared document for client editing, local persistence, file exchange,
API downloads and server JSONB storage. Swift types are generated from the schema and both
languages validate the shared fixtures. There is no SavedLayout conversion pipeline or mapping
metadata sidecar. See [APP_ADOPTION.md](APP_ADOPTION.md) for the implementation and remaining check.

## Versioning and development reset policy

Use `format: pocketpad-layout`, `schemaVersion: 2`, and reject unsupported formats/versions.
Only current full-canvas geometry is supported. No legacy coordinate migration, old profile
import, old catalog conversion or experimental v1 compatibility is required. Development layouts
may be discarded. The archived `layout-v1.schema.json` is historical material, not a supported
input contract. Version numbers still matter for future evolution after launch.

The clients use `PocketPad/layout-documents-v1.json` in their Application Support directory,
with fresh canonical starter documents. They do not read old layout keys. Old layout-only data can be removed during an explicit development
reset. Do not reset pairing, credentials, permissions or unrelated settings. A corrupt new-format
catalog must still report an error without silently overwriting it.

Existing development API rows may still contain schema v1 and are rejected by the new client.
A separate `pocketpad_canonical_test` database was seeded with v2 to verify actual API downloads;
the original development database and its immutable revisions were left unchanged.

## One document, separate envelopes

- **LayoutDocument:** the canonical actions, controls, named modes, settings and presentation.
  The app edits this document, exports it and stores it inside a local wrapper. The server stores
  the same document as JSONB. Swift/Python types differ; JSON field names and semantics do not.
- **Marketplace listing:** publication/revision identity, ownership, game, tags, licensing,
  moderation and research sources remain server metadata outside the document.
- **LocalLayout:** local UUID, document, optional source publication/revision/digest, preset/edit
  state and local revision for conflict detection. A local catalog holds selection; active mode
  is local/session state, distinct from the document's initialMode. Document-local action,
  control and mode IDs are preserved on download and duplication; only wrapper IDs are renewed.

Only the active input backend is stored in the document. Backend conversion creates an explicit
new copy, with unresolved mappings reported. No hidden inactive profile or template-style store
is maintained as a second source of truth. Runtime objects are derived, disposable views of the
document and never independently saved or edited.

## Modes and future layout collections

A document has an ordered `modes` list with stable human-readable IDs, `initialMode`, and a
control with role `modeSwitch` and command `cycleModes`. Names are user-defined: Combat and
Building are valid names. The mode's `pointerMode` (`aim` or `cursor`) is a behavior setting,
not its identity. List order defines the cycle; `initialMode` must name the first entry under
the current runtime profile.

`runtimeProfile: pocketpad-fixed-v1` limits this draft to one or two modes. Two require exactly
one switch, visible in both modes. One forbids a switch and remains a genuine one-element list; do not fabricate a second
saved mode to satisfy the old SavedLayout structure. Control IDs and bindings are
shared across modes under this initial capability profile. Mode overrides
change presentation only; mode settings change gestures and pointer behavior. Overrides merge
onto the base control; omitted fields inherit. Explicit null for label, placement or feedback
clears that base override and restores the runtime default for that mode. No per-mode bindings
are accepted.

**The requested future feature is broader:** users download independent layouts, put them in a
local ordered collection (Combat → Building → Travel), and cycle between them. Each member can
have different mappings. Prefer local copies and provenance over live remote dependencies, so
switching works offline and remote edits cannot unexpectedly change play. Collection membership,
current selection and local IDs belong to local storage, not public UUID references inside a
portable layout. A shareable collection/bundle format can be designed separately later.

The named-list and `cycleModes` vocabulary leaves room for expansion, but a new capability profile
and runtime work are required for >2 modes, per-mode bindings, or cross-layout switching. Do not
increase maxItems alone: replace two-mode indexing, define release of held inputs on transition,
update sync/wire validation and editing, and define copying/updates of collection members first.
Current validators deliberately reject third modes and remote layout targets.

## Controls, actions and allocation

Controls have stable document-local `id` and a `role`, not just a generic shape. Fixed roles are
native face/shoulder/system buttons, triggers, left/right sticks, D-pad, radial and mode switch.
Only one of each fixed role is allowed. `customButton` additionally declares a unique `customSlot`
from 0 to 15. These are runtime slots, not device UUIDs. At most 35 controls fit the full profile.
The adapter will map each role to the existing canvas ID; IDs themselves remain readable.

`bindings` maps `press` or the four cardinal directions to action IDs. Actions contain ordered
outputs, optional Hold/Tap (default Hold), and a descriptive label. Action labels are descriptive
metadata; they do not implicitly override captions. Use a control's `label` for a visible custom
caption (maximum 20 characters); otherwise preserve runtime identity/template captions. Action IDs, labels and bindings live directly in the canonical document. Moving/resizing a
control or changing its caption does not change its action. Rebinding a unique action updates
its outputs while retaining identity and descriptive label. Rebinding one of multiple references
clones the action under a new document-local ID and repoints only the edited reference; other
references remain unchanged. The editor must account for all references, including auto-run.
Deleting a control removes its reference; retain an action while any references remain. Remove
unreferenced actions only through a documented cleanup operation, not silently during decoding.
Duplication preserves document-local IDs and metadata within a fresh local wrapper.

All binding edits go through document edit commands, including Mac edits and undo/redo. There
is no metadata sidecar and no reconciliation against a separately persisted runtime profile.
New actions receive stable stored IDs and neutral descriptions unless the user supplies meaning;
never infer that Space means Jump. Explicit shared-action editing, if added later, must be a
separate operation from editing a single control binding.

Keyboard/mouse supports up to four distinct outputs per action. Gamepad accepts zero or one
button output with Hold only. Gamepad sticks use shared gamepad settings, not action bindings.
Keyboard right-stick mouse behavior uses keyboard settings plus mode pointer behavior, not
`pointer.*` pseudo-actions. Independent diagonal bindings and radial center-hold are unsupported.
Four/eight-way D-pad behavior is a mode setting; diagonal activation combines cardinal outputs.

Absent controls must be hidden/disabled, and absent bindings explicitly unmapped by the adapter.
Never let native gamepad identity mappings, custom number-key defaults, or Shift auto-run leak
into a loaded document. Empty action outputs explicitly mean unmapped. Required default
materialization must happen before applying document bindings.

A radial's `radialSlots` maps directions to **custom control IDs**, sharing their existing slot
and binding. A custom control may be hidden while remaining usable through the radial. This
preserves aliasing between an on-screen quick button and its radial direction. Missing radial
directions use the existing nearest-mapped-direction rule. Selection occurs on release with a
0.12-second custom input pulse; Hold on such a source does not mean holding the radial open.
No new center-hold or arbitrary radial activation semantics are introduced.

## Geometry and appearance

`geometry: runtimePresetV1` deliberately replaces the old shorter-edge `size` field. Placement
uses normalized `x`, `y`, and `scale` (0.65–1.8, default 1). Each mode has `sizeFactor` (default 1).
Omitted placement uses that role's existing preset placement, including template-specific offsets.
Controls use consistent UIKit point sizes, independent of screen dimensions and pixel density.
This is the development v2 point-sizing update; older proportional sizing is no longer used.
Both devices must use layout sync protocol 5.

For a canvas W × H, the requested radius is:

    roleBaseRadius × mode.sizeFactor × placement.scale

The resolved radius is at least 22 points (44-point diameter). Four-way D-pads use
22 / 0.92 so the visible cross spans at least 44 points. Oversized controls shrink
only as needed to fit the playable canvas with a four-point margin. Normal phone
canvases must be at least 52 points per axis to satisfy both fitting and minimum size.

Base radii: sticks 62; D-pad 50; radial 30; triggers/shoulders 27; mode switch 25;
face buttons 23; back/start/stick-click buttons 22; guide 20; custom buttons 19.
Guide and custom buttons therefore resolve to at least 44-point diameters by default.
Positions remain normalized; default template offsets retain relative placement.
Coordinates are fitted after sizing. Phone and Mac previews use the same resolver;
fit-to-window previews scale the complete control, including its label.

`templateStyle` chooses the Xbox/PlayStation geometry template. `controllerStyle` separately
chooses gamepad emulation identity and is required only for gamepad documents. Global haptics
default to medium. Per-control feedback carries explicit haptic/tint values; absent feedback
means the runtime's inherited behavior. Mode overrides can supply placement, caption, visibility
and feedback. `linkedControls` names controls whose future position edits propagate between
modes using the runtime's size-factor compensation; it is not an assertion that existing
positions are equal.

## Settings and defaults

JSON Schema `default` annotations document defaults; validators do not insert them. The adapter
must materialize them explicitly, independently of starter profiles.

- Keyboard: rightStickMouse true; speed 900; smoothing .025; relativeGameAim true;
  mouseUpdateRate 1000; invertMouseY false; stickThreshold .35; comboGap .03; tapDuration .12.
- Auto-run: disabled, threshold .8. Enabling requires an explicit Hold action; no implicit Shift.
- Gamepad: swapSticks, disableLeftStick, disableRightStick, invertLeftY, invertRightY all false.
- Mode: pointerMode aim; sizeFactor 1; dpadStyle eightWay; holdAimEnabled true;
  holdAimDelay .3; trackpadHoldDelay .5; floatingLeft/Right false; leftTap/rightTap off.
- Runtime stick center-hold behavior, gesture thresholds and radial pulse timing remain fixed.
  Hold-to-aim belongs to rightTrigger and is inactive in cursor mode. No fields imply otherwise.

The draft bounds gesture delays to 0–5 seconds. Existing values outside the representable range
must produce an export diagnostic rather than truncation. Unknown properties, references,
roles, output families and unsupported combinations are errors. Size limit: 256 KiB canonical
JSON. Digests use SHA-256 over RFC 8785 canonical bytes; never hash arbitrary encoder output.

## Fixtures and validation

See `fixtures/README.md` for the four contracts and expected native mappings. They are authored
examples, not captured production exports and not verified game presets. The Python tests
exercise accepted fixtures and unsupported combinations. Swift document/runtime tests must independently
verify mappings, slot allocation, geometry and input behavior; digest equality alone is not a
round-trip test.

The Mac and iPhone targets build with document-backed editors, shared geometry, derived input
profiles, atomic catalog persistence and protocol-v2 sync. Swift tests cover action-sharing,
undo, conflicts, transport framing and file/download boundaries. Python tests include PostgreSQL
integration. A live local API download matches the file fixture in Swift. Physical iPhone/Mac
create/edit/switch/retry/conflict acceptance still requires the unlocked connected phone.

Export uses ordinary validated JSON. The Swift app does not generate publication digests;
server digests use RFC 8785 and remain immutable origin metadata on local edits and duplicates.
Run `python3 Scripts/generate_layout_types.py` after schema changes. The embedded-schema test
fails if the app contract drifts from the checked-in schema.

## Extended controls (development v2)

Optional placement `width` and `height` form a pair of normalized dimensions
(0.03–1 each), supported by `customButton` and the dedicated keyboard/mouse-only
`trackpad` role. These dimensions take precedence over radius/scale/sizeFactor;
trackpad dimensions use the actual canvas, while custom button dimensions use a fixed
800 × 320-point design reference. Both have a 44-point minimum extent and fit within
the same four-point canvas margin. An omitted trackpad size
resolves to 28% canvas width and 40% height. Ordinary buttons remain circular until
both dimensions are supplied. Position edits preserve dimensions; reset placement
clears them. Mac, phone, and marketplace previews use the shared resolver.
The fixed profile now admits 35 controls, including one trackpad; mode count remains 1–2.

Trackpad has no action bindings. One-finger drag emits cursor displacement, tap
clicks, and stationary hold right-clicks in either pointer mode. Two fingers suppress
clicks until both lift; mode `trackpadScroll` enables scrolling (default true).
The existing right-stick cursor behavior remains available. Pointer wire action 3
carries bounded two-axis scroll deltas, using the displacement fixed-point format.
Layout sync protocol is 5; both apps must be updated together.

Optional document `motion` has `mode` (`off`, `aim`, `steering`), `sensitivity`
(0.1–4, default 1), and `deadZone` (0–0.3, default .03). Omission is off. Steering
requires gamepad input. While RT/R2 is held, the phone calibrates against the first
sensor sample and emits right analog axes for aim or left X for steering. Release,
interruption, or mode/layout changes clear calibration and output. Aim is inactive
in Cursor mode. RT retains its ordinary binding; its normal hold-to-aim axes are
superseded while motion is active. Existing axis inversion, swapping and disabling
still apply. Keyboard motion aim uses the right-stick mouse output. Motion does not
create a separately persisted runtime profile. Actual sensor direction/feel still
requires physical-device acceptance.

Editor snapping and device preview selection are editor preferences, not layout
content. The floating phone settings button's size, fade delay (zero means always
visible), and inactive opacity are phone preferences, like its existing position.
