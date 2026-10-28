# BAMA adaptation audit

Research and implementation for Banana-edits, 2026-10-27. [Türkçe](../tr/bama-adaptation.md)

## What was installed and examined

[BAMA](https://github.com/daveebbelaar/bama) is a collection of 21 agent skills for building native Mac apps, not an image generator or an application runtime. The audit used revision [`9b986714f248036cdf3bdf458b93cd4b67fe120f`](https://github.com/daveebbelaar/bama/tree/9b986714f248036cdf3bdf458b93cd4b67fe120f), under the upstream MIT license. All 21 skills were installed in the local Codex skill directory. No upstream installer script was executed and no upstream executable dependency was added to Banana-edits.

The relevant parts are `research`, `performance`, `improve-architecture`, `os-integrations`, and `test-mac-app`. Their useful principles are to measure before optimizing, share behavior across entry points, keep UI code small, save atomically, and test against temporary data. BAMA's new-app template expects recent Swift/macOS versions; Banana keeps its current macOS 13.5 distribution minimum and existing shared React, AppKit/WKWebView, WinForms/WebView2, and Node/SQLite architecture.

Evidence labels below: **V** means verified source or repository behavior; **U** means a proposal that still needs implementation or testing. Individual issue reports are evidence of a reported problem, not a representative user survey or proof of a current bug in another product.

## Comparable apps

| App | Verified pattern | Decision for Banana |
| --- | --- | --- |
| [Draw Things](https://drawthings.ai/) | **V:** local generation, video, canvas and editing workflows; [releases](https://drawthings.ai/downloads/) distinguish generation and edit controls. | Keep Banana's explicit generation/edit intent. Attaching a reference must not silently choose area editing. |
| [DiffusionBee](https://github.com/divamgupta/diffusionbee-stable-diffusion-ui) | **V:** image generation, inpainting, variations and history in an installed Mac app. | Keep the existing masks, history and simple packaged local server; do not add another engine just to copy a feature already present. |
| [ComfyUI Desktop](https://docs.comfy.org/installation/desktop/overview) | **V:** packaged local environment; [shortcuts](https://docs.comfy.org/interface/shortcuts) are discoverable and configurable. | Improve keyboard image inspection now. A shared native menu command catalog is a follow-up. |
| [Pixelmator Pro](https://support.apple.com/guide/pixelmator-pro/keyboard-shortcuts-and-gestures-pix71a3304c4/4.4/mac/26) | **V:** keyboard zoom and fit are part of image inspection. | Add equivalent image-level controls, preserving browser zoom and text input. Banana uses unmodified +/−/0 consistently across platforms. |
| [Photomator](https://www.pixelmator.com/photomator/) | **V:** file browsing, drag/drop, ratings and batch workflows. | Optimize the existing gallery rather than building a second Mac-only library. |
| [Eagle](https://en.eagle.cool/blog/post/how-to-preview-files-in-eagle) | **V:** keyboard-oriented preview and navigation, plus handoff to other creative apps. | Preserve arrow navigation while adding zoom. A workspace-owned Reveal Original command needs a separate path-security design. |

## User reports and their implications

| App | Positive workflow or expectation | Friction reported | Evidence |
| --- | --- | --- | --- |
| Draw Things | Regional face detail is useful to an API user. | API coverage and multi-reference edit consistency. | [141](https://github.com/drawthingsai/draw-things-community/issues/141), [137](https://github.com/drawthingsai/draw-things-community/issues/137) |
| DiffusionBee | One user values Apple Silicon optimization and regular use. | Inpainting control, model import and revisiting prompts. | [570](https://github.com/divamgupta/diffusionbee-stable-diffusion-ui/issues/570), [history request](https://github.com/divamgupta/diffusionbee-stable-diffusion-ui/issues/24) |
| ComfyUI Desktop | Retaining the working context is a stated expectation. No broad praise claim was established. | Window restoration, quitting before the child process exits, and Back leaving a preview. | [window PR](https://github.com/Comfy-Org/Comfy-Desktop/pull/1629), [shutdown PR](https://github.com/Comfy-Org/Comfy-Desktop/pull/1625), [Back issue](https://github.com/Comfy-Org/ComfyUI/issues/8707) |
| Pixelmator Pro | Photos integration and reversible edits are valued in a discussion. | Users expect different browsing/flagging workflows. | [integration discussion](https://www.reddit.com/r/pixelmator/comments/1sh9h8q/pixelmator_as_photomator_alternative/), [flagging discussion](https://www.reddit.com/r/pixelmator/comments/1qegzsc/to_photomator_or_not/) |
| Photomator | RAW editing and viewing workflows receive positive comments. | Edit-history access, preset previews and backing up edit metadata. | [RAW/backup discussion](https://www.reddit.com/r/pixelmator/comments/1jm2oh0), [history discussion](https://www.reddit.com/r/pixelmator/comments/1rc95fd/photomator_speed/) |
| Eagle | Some users report fast normal collections. | Others report slow large imports and previews; accounts conflict. | [discussion](https://www.reddit.com/r/macapps/comments/157lkx9), [performance report](https://www.reddit.com/r/EagleCool/comments/1f96j8c) |

These reports informed the priorities; actual Banana source inspection and tests determined the fixes.

## Implemented adaptations

| Change | Before | Result and acceptance check |
| --- | --- | --- |
| Keyboard and accessible image zoom | Full-image viewer supported wheel/pan/double-click only. | + or = zooms in, − zooms out, 0 fits; visible buttons expose the same actions. Clamp is fit through 8×. Inputs, composition, browser shortcuts, sliders, menus and nested dialogs retain their keys. Image bytes are unchanged. |
| One folder statistics index | The standalone gallery filtered all media for each folder badge and recursively recomputed descendant costs. | Index direct media and child counts once; keep original pricing callback and accumulation order. Iterate rather than recurse; tolerate malformed cycles and 20,000 nested folders. Sorting, direct-count badges and descendant cost semantics remain intact. |
| Normal window placement | Both native shells reopened centered at a default size. | Save a small versioned geometry file atomically; restore only normal bounds and clamp to connected displays. Do not restore fullscreen/maximized state. Tests use temporary files, including corrupt and off-screen settings. |
| Bounded Mac startup | Windows had a readiness timeout; Mac could wait indefinitely. | A 30-second Mac readiness gate reports failure once, cancels on ready/shutdown, ignores late events and stops the failed child. Existing saved data is not deleted. |

The image viewer was extracted from the oversized gallery component into `src/components/GalleryDetailImage.tsx`, allowing the actual production handlers to be tested independently. The folder index is in `src/components/galleryFolderStats.ts`. These changes also apply to the hosted Banana codebase.

Window restoration uses [normal WinForms bounds](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.form.restorebounds) and connected [working areas](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.screen.workingarea). The Mac implementation follows AppKit's [window-position model](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/WinPanel/Tasks/SavingWindowPosition.html), with explicitly testable geometry and file storage.

## Measurements

Synthetic metadata only, Node 24.19.0, five warm-up runs and the median of eleven measured runs. Each before/after pair checks exact result parity. Benchmarks were run sequentially; small timings still vary with system load.

| Case | Standalone before → after | Hosted before → after |
| --- | --- | --- |
| 300 root folders, 20,000 media, 300 visible badges | 32.955 → 0.248 ms | 1.118 → 0.229 ms |
| 1,000 nested folders, 20,000 media, one visible badge | 1.056 → 0.710 ms | 1.790 → 1.090 ms |

The hosted version already indexed direct item counts, so its baseline is different. These are folder-derivation timings, not whole-page rendering or provider-generation speed claims. Run `node scripts/benchmark-gallery-folder-stats.mjs` to reproduce the standalone comparison.

## Verification and boundaries

Unit tests exercise the real zoom handlers, reference-safe keyboard behavior, counts/costs, input immutability, cycle handling, deep nesting, isolated placement files and startup deadlines. The committed `tests/ui/gallery-zoom.html` fixture uses only a synthetic image, with no account or provider call. Mac Swift tests compile the real shell. Windows CI builds the shell and runs `--test-window-placement` next to its isolated vault check. A physical Windows display/DPI session remains a separate manual check; compilation and geometry self-tests do not prove all hardware interactions.

No model routing, generation prompts, edit mask limits or outside-mask preservation behavior changed. Provider keys remain in the native vaults/server. No background clipboard reader, screen recording grant, global keyboard monitor, unauthenticated debug bridge or arbitrary file-opening endpoint was introduced. BAMA is installed as development guidance, not shipped as a runtime dependency.

## Useful follow-ups

1. **U: shared native command catalog.** Expose Search, Library and preparation actions in native menus using the shared UI handlers. Require enabled-state parity and prevent duplicate billable submissions; keep native copy/paste/undo.
2. **U: Reveal Original.** Accept only a saved media ID, resolve an owned workspace file on the server, and reveal it in Finder/Explorer. Never accept an arbitrary path from JavaScript.
3. **U: full desktop workspace restoration.** Save navigation and drafts through the local SQLite service. The ephemeral web session and random loopback port make browser-only storage unsuitable for a cross-restart guarantee.
4. **U: safe job-aware shutdown.** Extend the existing durable queue tests to quitting/reopening mid-generation, with a bounded child-exit wait and no duplicate paid calls.

These need their own acceptance tests before delivery. A rewrite into SwiftUI, a new local inference backend, and a macOS 26-only visual redesign were rejected for this phase because they would increase platform differences without solving the verified gaps above.
