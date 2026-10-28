# clipboard-app 1.7.3 platform parity

This document describes the 1.7.3 implementation. Package availability is shown
by the [latest release](https://github.com/DrabornEagle/DraBornStudio/releases).
The table describes source behavior; the native acceptance gates below must
pass for the exact source revision before a package can be published.

macOS and Windows share one product version and one behavior contract. Command
maps to Control, and Option maps to Alt, on Windows. Every future feature is a
two-platform change unless a native exception is recorded in the contract.

| Area | Shared behavior and corrections |
| --- | --- |
| Shelves | Opening selects the first available image only; empty/hidden rows are skipped. Up/Down cross rows, Left/Right move items, Command/Control-arrows reach endpoints and Option/Alt-arrows change pages. |
| Text identity | Both stores match NFC Unicode and CRLF/CR line endings, ignoring only outer paragraph breaks. Newest literal clipboard bytes replace the body while names, pins, folders, tags and notes survive. Spaces, indentation, case, invisible characters and internal blank lines remain significant. The shared `contracts/text-identity.json` fixture exercises both actual stores. |
| Shortcuts | Remapping, disabling and restoring defaults affect actual dispatch and displayed hints. Custom bindings take precedence over new defaults. Quick slots, selection extension, image tools and context-dependent editing commands are configurable. |
| Actions | Search, navigation, Library views, folders/tags, settings destinations, crop and markup use real controllers. Batch actions retain captured order; preview follows the focused batch member. |
| Library | Notes and inspector edits save automatically before navigation. Saved status survives unpinning or removing folders/tags. Recent excludes saved records; Unorganized includes only saved records without folders/tags. F filters pins inside the current folder/tag scope. Multiple tags filter with AND; title descending, last-copied and relevance sorting are available. Folder drops add membership without changing existing pins; global tag rename/removal updates every record. |
| Layout | Compact 52-pixel list rows with Title/Type/Tags/Added columns; sortable headers, resizable columns, persistent side panels and widths. Grid and list share selection/actions. |
| Preview | Frameless, aspect-fitted images use full-resolution rendered content. Click text to edit; a 300 ms autosave preserves the native editor, caret, selection and undo. Editing finishes before arrows change items. Deleting the last shelf result retains an empty preview with Undo. Library preview arrows advance items; shelf preview Up/Down crosses rows without closing the preview. |
| Recordings | Windows native MP4/MOV import/watch, playback, M/Actions Trim and video-file copy/drag/export; original preserved and trim output MP4. Native codec, controls and original-preserving storage details are below. |
| Image editing | One top toolbar, zoom/pan, eight crop handles, apply/cancel, independent crop reset and annotation clearing, undo/redo after editing. |
| Links | Explicit refresh respects metadata preferences; verified YouTube black letterboxing is removed while real 4:3 content remains intact. Open-in-browser commands preserve their context. |
| Search | Names, text, notes, tags, link metadata and OCR are searchable. Windows now bundles the original MobileCLIP-S2 model through verified ONNX/WASM export; visual search runs offline in a worker with private derived caches. Text/visual/all modes respect the current Library scope. |
| Paste | Mac requests a cold Chromium/Electron accessibility tree once and uses a bounded wait for its real editable field; secure/read-only controls remain rejected. Capture the external editor before opening; preserve it across own-window transitions; refresh it when returning to an already open Library. Revalidate the exact process, window and editable field before clipboard writes and dispatch. Changed, secure or read-only fields are rejected. Successful paste dismisses browsing UI and returns keyboard focus. |
| Language | Windows translations are generated from all nine shared localization catalogs; CI rejects drift. Existing explicit source/privacy preferences are preserved. |
| Updates | Both signed feeds and both current packages must appear together in Latest. Build66 upgrades the actual published build65 and preserves existing content/settings. Large offline-model downloads use a bounded five-minute socket timeout without relaxing signatures, size or hash validation. |

## Verification requirements

The shared contract executes through the real Mac key router/model and Windows
renderer. It also covers remapping, disabling, restoring defaults and preserving
typing inside search. The release verifier authenticates both native-host CI
artifacts at the exact public source revision.

Windows acceptance runs on Windows x64 against source, packaged and per-user
installed applications. It covers Library auto-save and real geometry, keyboard
remapping, full-resolution preview, crop/undo, real WASM image search, native
target tracking and text/PNG paste into WinForms, Microsoft Edge and Google
Chrome. Native focus, inserted destination content and post-paste typing must
agree; an IPC success flag alone is insufficient. NSIS upgrade/reopen is tested
separately against the actual previous installer.

Mac acceptance uses XCTest, isolated native Library/preview fixtures and actual
external editors. Computer Use cannot automate its own host ChatGPT/Codex
application; website or synthetic tests must never be reported as native ChatGPT
desktop acceptance. No security permission is granted automatically.

## Screen recordings

Windows implements `.mp4`/`.mov` file import and collection from
explicitly configured watched folders. Recordings remain in Images, with a
poster and duration, and can use the same Library pin/name/folder/tag workflows.
The preview plays the video. **M** or **Actions → Trim video** opens start/end
range controls; Enter saves and Esc cancels. Copy, drag and export transfer the
recording file, not its poster. The native acceptance suite verifies these operations on each distributed
application form.

A separate, bounded native worker uses the installed Windows WinRT media stack
(`MediaClip`, `MediaComposition`, `BitmapDecoder` and `MediaTranscoder`). There is
no additional FFmpeg/GPL executable download. At most two decoder jobs run, with
64 queued jobs; explicit Trim takes priority over queued background inspection.
Cancellation and the ten-minute job bound stop work and clean owned temporary
files. Video import uses streamed hashing and a 2 GiB file limit.

The original managed video remains immutable. A successful trim atomically
switches the record to a new MP4 and regenerates its poster while preserving
names, pins, folders, tags and notes. MP4 export can re-encode; identical codecs
or lossless passthrough are not promised. Codec support depends on the installed
Windows media stack. H.264/AAC MP4 **and** MOV fixtures must pass actual native
acceptance; HEVC, ProRes and every possible MOV codec are not guaranteed.

Mac recognizes `.mov`/`.mp4`; its screenshot watcher accepts recordings in the
application Inbox. Quick Look and AVKit provide native playback/trimming windows.
Mac Trim now snapshots the active recording into private managed storage and
exports the kept range to another managed file. Its Library transaction switches
the existing item to the validated derivative while preserving the first original,
item ID, organization and temporary-history status. Canceling, changing the source,
trashing the item or failing the transaction cannot replace the source file. Native
AVKit controls and container/passthrough behavior differ from the Windows WinRT
encoder; both platforms preserve original recording bytes.

The release gate must verify real decoding, poster pixels, seeking, the selected
trim duration, retained decoded audio, cancellation, source hashes, Library
organization, and actual video-file transfer in source, packaged and installed
Windows runs. A command returning success alone cannot satisfy these checks. Native reports
bind the actual source, packaged and installed runs to the release revision.

## Cold Mac browser/editor accessibility

Electron can activate its web accessibility tree on demand. Mac capture now
reads the application role and requests `AXManualAccessibility` once only when
focus is absent or an eligible container is still loading. This follows
[Electron’s documented assistive-client API](https://www.electronjs.org/docs/latest/tutorial/accessibility).
Electron 44.9.0 debounces this request for two seconds; repeated setters during
polling would keep restarting it. A cold capture therefore has a 3.2-second
monotonic deadline with bounded AX calls; ordinary resolved fields retain the
fast path. Only an actual stable editable field can receive paste, and its
identity is checked before and after clipboard preparation. No security
permission, field value or undocumented enhanced-UI flag is requested. Chromium web text controls without an explicit editability hint also use a supported setter-capability denial to reject readonly controls. This check is limited to web text roles with provider DOM metadata; native/custom editors and generic rich roots do not require an assignable value. No DOM identifier is logged.

Full-tree test clients may warm the target before a clipboard test; this is an
inference from the provider sources, not proof of the cause in a particular
ChatGPT installation. Controlled cold fixtures must avoid any external AX read
before the first paste. Native ChatGPT desktop acceptance remains separate.

## Native platform details

AppKit materials and Windows window chrome use their respective platform
renderers. Text/file dragging has an explicit native exception: Windows keeps
ordinary shelf text insertion and offers Alt-drag for per-item file copies; Library cards use ordinary drag to add to folders and Alt-drag to export files;
Mac can advertise text and files in the same drag. See
[native transfer](windows-native-transfer.md). Neither distinction changes
Library organization, copy or paste commands.

Offline model provenance, licenses and reproducible export instructions are in
[Windows search models](windows-search-models.md). Models are build assets in
the existing public project repository; no client credential or runtime model
download is required.
