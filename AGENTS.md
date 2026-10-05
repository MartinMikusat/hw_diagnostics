# hw_diagnostics

The standalone diagnostics helper for the hw macOS apps. It lists the apps it
finds in `/Applications` and `~/Applications` whose bundle id starts with
`com.halwayland.`, and writes the selected app's redacted report to the Desktop
and reveals it, so a user can hand the operator one file when something breaks.

- Build with `./build.sh [debug|trace|asan|release]`. Test with `./test.sh`. Run
  the watcher with `./dev.sh` (`./dev.sh rebuild` to rebuild and relaunch).
- The report format, the crash counter and the scan live in the shared
  `hw_odin_diagnostics` library; this app is only the UI over it. Do not
  reimplement report building here.
- Interface verification is the operator's: `diagnostics --offscreen <path.ppm>
  [--settings] [--font-size=N]` renders headlessly.
- Releases and updates: `python3 scripts/release_macos.py build <version>
  --notary-profile <profile>` then `publish dist.noindex/<version>`; the app
  checks the release feed hourly and swaps a staged update in on quit.
  Publish only when the operator asks.
