# Runtime fixture expectations

All examples use schemaVersion 2 and pocketpad-fixed-v1. Swift canonical-model adoption is implemented; physical-device acceptance is pending.

| File | Expected native result |
| --- | --- |
| `keyboard-simple.layout.json` | One visible mode named Explore, switching disabled; left-stick cardinal WASD Hold; south button Space Hold, caption Jump. Right-stick mouse disabled. Only listed controls visible; all other bindings explicitly empty. |
| `two-mode.layout.json` | Modes Combat and Building, cycling in that order. Both share WASD/Space mappings. Building uses cursor pointer behavior and moves Jump to (.75,.6), labels it Hop, with light/blue feedback. Movement position edits link between modes. Switch remains visible in each mode. |
| `gamepad-remapped.layout.json` | Xbox geometry, PlayStation output identity; south source maps to west output and caption Use. Two sticks enabled, swapped, destination right Y inverted. All other button outputs explicitly unmapped. |
| `radial-custom.layout.json` | WASD/Space plus slot 0 → key.one Tap, slot 1 → key.two Tap. Slot 0 visible; slot 1 hidden. Radial up reuses slot 0, down reuses slot 1; nearest mapped direction covers intermediate angles. Releasing the radial pulses the selected slot. Exactly two custom slots consumed. |

`../example.layout.json` is identical to the simple keyboard fixture and supplies new demo seeds.

These fixtures describe current-runtime semantics, not a working Minecraft integration. In
particular, the two-mode fixture does not claim independent combat/building key mappings: that
requires future per-mode mapping or a local collection of independent layouts.

Adoption tests must cover decode/validate/encode equivalence; named modes and settings;
caption survival after controller identity changes; no invented fallback bindings; actual-canvas
fitting; fresh local wrapper UUIDs with preserved document-local IDs; and no catalog writes on
validation failure. Shared-action rebind tests must verify that only the edited reference changes,
while movement/caption edits preserve action metadata. Both language validators must run the
same positive and negative fixtures. Legacy documents and coordinates are rejected, not migrated.
These examples are canonical documents, not inputs for a SavedLayout conversion pipeline.

`rejected.json` is a shared mutation corpus consumed by Swift and Python validation tests.

`trackpad-motion.layout.json` exercises a rectangular trackpad, scrolling enabled,
and opt-in calibrated gyro aim. The matching rejection cases cover unsupported
rectangle roles, incomplete dimensions, trackpad bindings, keyboard steering,
and out-of-range motion sensitivity.

`point-sizing.layout.json` adds a custom rectangular button with width 0.1 and
height 0.15. It resolves to 80 × 48 points on both 667- and 932-point-wide canvases;
the trackpad retains its 30%-of-canvas width. Swift tests also cover consistent
46-point face buttons, 124-point sticks, minimum 44-point extents at small scale
settings, fitting at edges, and smaller relative appearance on wider previews.
