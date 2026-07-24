import AppKit
import SwiftUI
import XCTest
@testable import SSDWatcher

@MainActor
final class MenuBarPanelTests: XCTestCase {
    func testPanelKeepsUsablePopoverSizeAfterOnboarding() {
        let suiteName = "MenuBarPanelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(0.0, forKey: "scanInterval")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(defaults: defaults)
        let controller = NSHostingController(
            rootView: MenuBarPanel(model: model)
        )
        let fittingSize = controller.sizeThatFits(
            in: MenuBarPanel.preferredSize
        )

        XCTAssertEqual(
            fittingSize.width,
            MenuBarPanel.preferredSize.width,
            accuracy: 1
        )
        XCTAssertEqual(
            fittingSize.height,
            MenuBarPanel.preferredSize.height,
            accuracy: 1
        )
        XCTAssertGreaterThan(fittingSize.height, 500)
    }
}
