# hw_diagnostics

A small macOS app that collects a redacted support report for any of the
[hw](../../odin_libraries) applications, including one that will not start.

It scans `/Applications` and `~/Applications` for bundles whose identifier
starts with `com.halwayland.`, shows each app's name, version and whether it has
ever written a log, and on **Collect report** writes
`~/Desktop/<app>-diagnostics.txt` and reveals it in Finder. The report holds an
environment header, the app's journal around its last failure, and the newest
macOS crash report for that app; `$HOME` is redacted and nothing is uploaded.

The report format, the crash counter and the discovery live in
`hw_odin_diagnostics`; this repository is the UI over it.
