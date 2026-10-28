# BAMA research and clipboard-app 1.7.7

Inspected [daveebbelaar/bama](https://github.com/daveebbelaar/bama) at
`9b986714f248036cdf3bdf458b93cd4b67fe120f` (MIT, Dave Ebbelaar).
BAMA is a development toolkit, not another clipboard application. Its 21 skills
were installed through the native Codex plugin route as `bama@bama` 1.0.0,
pinned to that source. The installed skills and license match the inspected
checkout. Its relative references remain intact; no template, shell installer,
MCP server, typing monitor or production agent socket was run or added to the app.

## What already works here

The [clipboard reference](https://github.com/daveebbelaar/bama/blob/9b986714f248036cdf3bdf458b93cd4b67fe120f/specs/clipboard-history.md)
is a useful checklist, not a replacement specification. clipboard-app already
has three shelves, editable previews, saved content, names, folders/tags,
local OCR/visual search, configurable shortcuts, recoverable Trash and signed
in-app updates. The reference's fixed item cap, own-copy reordering and reversed
Return/Command-Return behavior conflict with this product's existing choices.
The stable certificate, frozen credential helper, anonymous public updates,
shared product version and native platform acceptance are already stronger than
starting over from its template. All are preserved.

The [performance workflow](https://github.com/daveebbelaar/bama/blob/9b986714f248036cdf3bdf458b93cd4b67fe120f/skills/code/performance/SKILL.md),
[OS integration recipes](https://github.com/daveebbelaar/bama/blob/9b986714f248036cdf3bdf458b93cd4b67fe120f/skills/code/os-integrations/recipes.md)
and [test workflow](https://github.com/daveebbelaar/bama/blob/9b986714f248036cdf3bdf458b93cd4b67fe120f/skills/ship/test-mac-app/SKILL.md)
provided review prompts. Implementations remain native to the existing Mac and
Windows architecture. There is no new runtime dependency on BAMA.

## Adapted improvements

| Area | Before | 1.7.7 behavior on both platforms |
| --- | --- | --- |
| Large-image editing | Markup/crop gestures repeatedly rasterized the base image. | Retain the decoded base independently and redraw only the editing overlay. Windows coalesces paints at animation-frame boundaries while retaining every stroke point. Full-resolution flattening remains on save/copy/export. |
| History cleanup | Mac offered only image clearing; Windows had no matching bulk action. | Settings → History offers All types, Images, Texts and Links, an eligible count and a confirmation. Actions can also start cleanup. Only confirmed, still-unsaved capture versions enter recoverable Library Trash. |
| Clipboard admission | Mac omitted the legacy 1Password marker; Windows omitted transient/generated markers and could read text from a replacement clipboard. | Check all item formats before payloads. Windows binds its snapshot to native clipboard generations before/after reading; unverified or superseded copies are discarded. Whitespace-only copies are skipped without trimming accepted content. |
| Shortcut recording | An existing global combination could fire instead of reaching the recorder. | Temporarily release only this process's owned global registrations for any recorder. Restore on save, cancellation, close, focus loss, replacement and error. Stale callbacks cannot fire a newer registration. A key taken by another app produces a warning rather than being stolen. |
| Settings accessibility | Windows visible labels could be Turkish while accessibility names stayed English. | Toggle names follow the visible localized label; the new History selector/count/confirmation is localized. Both platforms share the registration-restoration warning text. |

Cleanup preserves pinned items, previously saved but now unpinned items, folder
and tag membership, managed media and external originals. It is scoped to the
confirmation's IDs and capture versions. New copies are outside that boundary,
including deduplicated recopies and app-copy actions that reuse an existing ID.
An optional capture revision in record metadata provides that distinction even
with an unchanged clock; existing records need no schema or storage migration.
Mac rechecks versions and eligibility and writes under one SQLite writer
transaction. Windows commits once and rolls back the full mutation on failure.

Admission excludes recognized private markers; it cannot identify every secret
copied as unmarked ordinary text. It does not guess whether a deliberately saved
API key should be removed, inspect typing, or send contents to a service.
Accepted nonblank UTF-8 remains exact, including Unicode/BOM distinctions. Existing
saved content and intentionally blank manually created notes are preserved.
Windows sequence queries reuse the existing native monitor's request/reply pipe;
a bounded native getter is available when the monitor is absent. No new OS
permission is requested. A zero/invalid generation is rejected before payloads;
[Microsoft documents zero when clipboard access is unavailable](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboardsequencenumber).

## Measurements and validation scope

Mac's optimized raster microbenchmark alternated six batches of 32 draws. For a
4K source decoded at 3840×2160, median raster CPU was 0.626 → 0.432 ms/draw.
An 8K source went through the actual preview decoder to 4000×2250 and measured
0.624 → 0.432 ms/draw. This is approximately 31% less raster CPU work. It excludes
GPU composition and is not a measurement of display FPS or physical gesture
latency. Real composed pixels were tested at 1×/2× backing with crop, orientation,
alpha and source replacement; unchanged gestures retain the same base image.

In isolated real Chromium, the previous Windows renderer performed 98 base-image
canvas copies/overlay paints during a 97-sample synthetic gesture. The candidate
performed zero base-image canvas copies and one coalesced overlay paint in that
single JavaScript frame, retaining all 97 points. Exported and decoded stored
PNGs, including cropped pixels after zoom/pan, matched exactly at 4K and 8K.
This demonstrates coalescing and output correctness, not a 98× physical FPS gain.

The shared contracts are `contracts/clipboard-admission.json`,
`contracts/history-cleanup.json` and `contracts/shortcut-recording.json`.
Tests exercise actual watcher/store/registration interfaces, with literal
external marker expectations rather than production constants as the oracle.
Additional regressions cover a concurrent SQLite writer, failed cleanup commits,
same-clock recopies, more than 10,000 confirmed IDs, late recorder replies and
queued image paints after editor dismissal. Existing shelf selection, retained
three-row motion, preview, copy/paste and upgrade checks remain required.

The Windows native gate also exposed two existing edge cases. Native/remote key
input without a physical code now normalizes ASCII shortcut letters while
preserving legacy bindings. A controlled real-renderer test reproduced a crop
undo race when an unrelated surface packet arrived before the save reply and
its full content broadcast arrived later. Undo history now binds to the
acknowledged saved image generation; a later external edit still invalidates it.
Mac's equivalent markup save returns its native record synchronously and keeps
undo documents on the canvas, so it has no corresponding IPC fingerprint path.

The isolated Mac Cua fixture confirmed per-type counts, cancellation, moving nine
unsaved texts to Library Trash, keeping 15 saved records, and restoring the batch.
It also exercised marker drawing, zoom/pan, crop, undo/redo and navigation back
to the saved edited image. This never modified the user's real history.
Native Windows source, packaged and installed suites include real clipboard
admission, 4K/8K editor output, localized History controls and OS shortcut recording.
Successful native execution is still a publication requirement; portable browser
runs do not substitute for it. Private raw evidence remains under `local/validation`.

## Worthwhile follow-ups

1. Source-application attribution and search, placed in the inspector/filter
   rather than repeating a label below every card. Accurate capture ownership
   and an additive migration are necessary, especially on Windows.
2. An explicit opaque masking tool for screenshots. Shared exports must flatten
   the mask, invalidate stale OCR and preserve reliable undo locally.
3. Windows Library projection caching/viewport virtualization for very large
   collections. Mac already has a native virtualized collection and paged reads.
4. Serialized background TIFF import and Windows durable persistence, preserving
   successful-save semantics, error recovery and shutdown flushing. Replacing
   synchronous writes with a loose timer would weaken durability.
5. Reusable text templates with explicit insertion and date/clipboard
   placeholders. Automatic system-wide typing expansion is a separate feature
   with additional permissions and input-routing work, not an implicit addition.

The existing 1.7.6 downward/upward shelf animation, keyboard meanings, history
retention and stable update/signing identities stay intact.
