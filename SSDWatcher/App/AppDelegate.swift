import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    private var previewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["SSD_WATCHER_SHOW_PREVIEW"] == "1" else {
            return
        }

        let content = DevelopmentPreviewRoot()
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SSD Watcher Preview"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 390, height: 640))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }
}

#if DEBUG
private struct DevelopmentPreviewRoot: View {
    @StateObject private var model = AppModel()

    var body: some View {
        MenuBarPanel(model: model)
    }
}
#endif
