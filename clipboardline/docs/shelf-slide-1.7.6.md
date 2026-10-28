# Restore the slide while keeping three-shelf optimization

The 1.7.5 native-opacity reveal made toggles cheaper but removed the original
falling-in motion. 1.7.6 restores downward opening/upward dismissal without
animating every SwiftUI card or resizing the native Windows window.

macOS retains its NSHostingView inside a clipped, flipped compositor wrapper.
Only that wrapper's sublayer transform animates; the window and host bounds
remain fixed even with displays stacked vertically. Windows moves its retained
shelf document with the Web Animations compositor. Both use 420ms opening and
220ms closing, with the same easing curves. Reversals sample the current
presentation position; stale completion callbacks cannot hide a reopened shelf.

Keyboard navigation is immediately available. Pointer input waits until moving
content reaches its fixed hit geometry. Reduce Motion sets immediate endpoints.
No screenshots/raster caches of user clipboard contents are generated for motion.

The shared shelf contract adds a hidden-middle-row close/reopen scenario.
Native XCTest covers hidden first-frame preparation, row-height changes,
fixed host/window coordinates, rapid reversal, queued pointer suppression,
continued keyboard actions, and reduced-motion focus ownership.

The isolated UI harness compares the unchanged 1.7.5 implementation against the
candidate with identical fixture/harness/dwell: 40 cycles across 36/3036 records.
It samples actual CALayer presentation translations and actual host-layout/
hit-geometry callbacks, with 6 rapid reversal checks afterward. CPU and 16ms
run-loop timer lateness are reported; these measurements are not display FPS.
Raw traces and build hashes stay in ignored local/validation/slide-toggle-2026-10-21.
Native platform release acceptance remains mandatory before publication.


Local Mac result: 583 XCTest cases passed. The isolated candidate passed all
40 opens/closes,80 actual movement traces,6 reversal pairs and injected Reduce
Motion. In the 3,036-record fixture, process CPU including identical dwell was
2.047s (1.7.5 opacity baseline 1.625s), with 16ms timer lateness p95 at 0.917ms
(baseline 1.741ms). Animation adds a small compositor cost while retaining bounded
layout work; this does not claim zero GPU cost or a measured display frame rate.
