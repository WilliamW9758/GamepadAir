# Portable layout format proposal

Status: draft contract, November 23, 2026. Not yet a replacement for `PortableProfile` or the on-device catalog. The companion JSON Schema and example are design artifacts for implementing the marketplace importer/generator. Do not upload or import these examples through the existing v1 profile decoder yet.

## Separate three kinds of data

1. **Layout document:** human-readable JSON describing input type, actions, controls, and defaults. No account identity, local UUIDs, selected layout/mode, pairing information, device name/address, or diagnostic history.
2. **Marketplace listing:** server-owned publication ID, author ID/public nickname, game ID, scenario tags, revision, moderation state, license, created/updated dates, compatibility claims and verification evidence. Source links from generated research belong here or in a private generation job, not executable layout fields.
3. **Local saved instance:** device UUID, selected mode, edit history, imported publication/revision, personal modifications, and sync revision. Multiple personal copies may refer to the same publication.

Use `format: pocketpad-layout` and integer `schemaVersion: 1` for this new format family. It is distinct from legacy `pocketpad-profile` version 1 and the local catalog version 2. Reject unknown major versions; introduce explicit migrations rather than silently ignoring semantics.

## Why JSON

Readable field names and short, meaningful action IDs are easy for people and models to write. Use `jump` instead of UUIDs or bitmasks. A control references an action so a name/binding is defined once. The model returns only the document, never source code or shell commands. Validate before converting to runtime controls.

Keep default values implicit and positions normalized. Encode one base arrangement; a later optional mode-override extension should store only differences. Do not duplicate an inactive input backend or the whole Aim/Cursor layout. The initial draft schema covers single-mode layouts; alternate-mode overrides and advanced gesture/timing settings need a lossless design before migration. Existing two-mode layouts must remain in their original storage until that is available.

Compress immutable documents with gzip/Brotli for transport/storage. Keep JSON as the canonical source rather than adopting an opaque binary format. Hash deterministic UTF-8 JSON (defined key ordering/number normalization) for deduplication, not arbitrary encoder output. Budget: 256 KiB uncompressed per document, 128 controls/actions maximum at schema level; the runtime adapter must enforce the actual current hardware/custom-slot limits too. Do not silently drop unsupported controls.

## Geometry and mappings

`x` and `y` are control centers in [0,1], relative to the actual phone canvas width and height. Y increases downwards. `size` is diameter/extent as a fraction of the shorter canvas edge. Placement validation must account for the full control bounds and safe areas, not just center points. Preserve the phone aspect ratio on Mac.

Actions define ordered chords and Hold/Tap behavior. Control `bindings` maps press/directional/axis roles to action IDs. Empty directions are omitted, not mapped to a hidden default. Radials choose the nearest mapped direction by angular distance; opposite mappings divide the circle in half. Control labels are optional explicit overrides; otherwise use the action label or controller-style label. This preserves custom names when changing Xbox/PlayStation style.

Beyond JSON Schema, the adapter must validate: unique control IDs; all action references exist; output family matches inputType; legal binding roles for each control kind; valid chord cardinality/type; complete control bounds; no unsupported slot count; and red/unusable indication for unresolved bindings. Duplicate into another backend with explicit conversion results rather than automatic guessed gameplay bindings.

## Migration and implementation sequence

1. Freeze the draft after accounting for every current control and advanced preference; add fixtures for current exports, custom names, both modes, radials, linked positions, controller identities and haptics.
2. Implement a pure importer/exporter between the versioned document and `SavedLayout`, with semantic validation and stable IDs local to the document.
3. Prove full round-trip behavior before changing existing file export or catalog persistence. Back up the original catalog; never rewrite it on decode failure.
4. Add the same schema and semantic checks to upload and AI generation on the server. Treat all generated/downloaded data as untrusted.
5. Measure actual sizes and parse time on representative layouts. Optimize based on measurements; small JSON payloads are unlikely to dominate server costs compared with previews and model calls.

The existing local representation remains authoritative for this build. Deletion/reset changes do not migrate or compact users' layouts.
