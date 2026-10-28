# Three-shelf opening and closing

The remaining 1.7.4 hitch occurred during visibility changes. macOS moved the
entire SwiftUI stack, including every visible material card and global hit-rect
preference, over a 420 ms spring. It now keeps the layout and native window frame
fixed and composites a short native opacity transition (120 ms opening, 100 ms
closing). Reduce Motion remains immediate. A generation guard prevents an old
close completion from hiding a rapidly reopened window. Key focus and the exact
external paste target retain their existing handoff.

Opening clears selection once, does not publish unchanged inactive-row state,
and finds only the first eligible item rather than mapping full ID arrays.
Closing a non-searching shelf no longer runs empty search teardown. Actual
search closure, fresh image selection and filtered/empty fallbacks remain covered
by the executable shared contract.

On Windows, visibility uses small surface-state events while library content and
visible DOM remain cached. A committed edit forces a full current snapshot before
subsequent small packets. Unchanged native bounds and window style setters are
skipped. Native focus capture/restore and its security checks are unchanged.

Native Mac tests cover fixed frame/hit coordinates, rapid reversal, Reduce Motion
and focus ownership. The isolated Mac harness compares the old and new real
window/view paths over matching small and 3,036-item fixtures. It records
synchronous action duration, 16 ms main-loop timer lateness and whole-process CPU
through identical dwell intervals; none is a display FPS claim. The isolated
harness pauses background image indexing during this measurement and resumes
it afterward; production indexing is unchanged.

Windows source, packaged and installed native suites additionally check four
real hide/show cycles with 3,000 items, retained cards/media, one first-image
selection and native keyboard focus. After the real image-search worker has
drained, these steady-state cycles require zero full-library projections
and zero unchanged bounds calls for those cycles; a hidden committed edit must
still arrive in the following full snapshot.
