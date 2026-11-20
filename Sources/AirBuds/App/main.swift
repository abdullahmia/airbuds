// AirBuds: control earbuds from the menu bar. Starts the app; AppDelegate does
// the rest.

import AppKit

#if DEBUG
MainActor.assumeIsolated { DebugSnapshots.runIfRequested() }
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
