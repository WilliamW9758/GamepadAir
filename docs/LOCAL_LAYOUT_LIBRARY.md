# Local layout library

Layout & mappings lists the Mac's saved layouts and works without a phone. Create, duplicate,
edit, save, and delete are local operations. When connected, saved edits can be sent to the phone.
The editor retains the last known phone canvas size when disconnected. Unsaved draft changes
require confirmation before selecting another layout.

The canonical publication document is unchanged. Local wrappers now include an optional
`modifiedAt` timestamp. Older wrappers load with an unknown edit time. Undo creates a new edit
time and revision; it never rewinds conflict counters.

Layout sync protocol 3 adds read-only fetches and identity-preserving creation. Both Mac and
phone must run the new build. Mac fetches catalog entries one at a time without switching the
phone's active layout or interrupting its input. Fetched documents are saved locally for later
editing. Fetch payloads are not retained in the mutation idempotency ledger.

Different content under the same ID is a conflict. Matching names with different IDs also
prompt, except identical built-in presets. No choice is inferred solely from revision counters:
independent offline edits may have equal counters. The comparison shows Mac/iPhone edit times
and identifies the later timestamp; missing or nearly equal timestamps are explicitly unordered.
Device clock accuracy affects timestamp ordering. Selecting an older copy requires a second
confirmation. Keep both preserves the Mac copy under a fresh ID when necessary. Stale resolutions
are rejected if either compared version has changed, and phone writes still require its expected
revision. Conflicts are never automatically overwritten.

Deleting a Mac copy does not delete the phone copy. Its ID is hidden from automatic reimport on
that Mac so it cannot immediately reappear. Pairing credentials and account credentials are
unrelated to library synchronization and are never included in its messages.

Marketplace opens to community browsing/filtering. Account actions, uploads, revision submissions,
and publication status live on the separate My submissions page with a Back to Marketplace link.

Validation: automated tests cover read-only fetches, stable IDs, duplicate/create rejection,
offline save/reopen, confirmed device replacement, undo revisions and old wrappers. Mac UI checks
verified offline create/edit/save/delete and storefront/submissions navigation. Physical-device
reconnection/conflict UI still needs testing with both protocol-3 builds; no release was promoted.
