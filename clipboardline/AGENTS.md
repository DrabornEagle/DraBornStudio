# clipboard-app public source

This repository contains the audited source and releases for one clipboard-app
product on macOS and Windows. Keep all user-visible features and behavior aligned
by default. A feature request applies to both platforms unless an explicit,
reviewed OS-native exception documents its user impact and reason. Native API
and modifier-name differences do not justify silently omitting a feature.

Read `docs/cross-platform-parity.md`. Extend `contracts/shelf-behavior.json` and
both actual application adapters for user-visible changes. Run the Mac XCTest
and Windows renderer/runtime acceptance suites, the parity checker tests,
`python3 scripts/check-release-version.py --require-windows`, publication audit
and secret scan. Publication requires successful exact-source Mac and Windows
CI evidence; a Windows renderer test executed on macOS is not native Windows
acceptance. No source-text or implementation-mirroring checks as behavioral proof.

The maintained DrabornEagle source is `DrabornEagle/DraBornStudio/clipboardline`.
`UPSTREAM.json` identifies the original project and pinned import. Existing Mac
feed URLs and Windows signed repository/URL identities are inherited upstream
compatibility data; they are not a DrabornEagle release channel. Before distributing
any desktop package, configure and verify a distinct DrabornEagle signed update
channel, or disable updates for a development build. Do not ship an upstream
package as a DrabornEagle update. Preserve internal module and storage identities
unless an explicit migration is implemented and tested. The historical upstream
rename is documented in `docs/repository-rename-2026-10-27.md`.
Keep the shared product version aligned and platform build counters independent.
Preserve the Mac bundle/storage identity and compatibility paths. Both signed
update feeds and packages must remain available in every Latest release; do not
publish a platform-only Latest. Public/community builds contain no private
release identity, client credentials or signing keys. Never commit private
history, real clipboard content, preferences, validation artifacts or backups.
