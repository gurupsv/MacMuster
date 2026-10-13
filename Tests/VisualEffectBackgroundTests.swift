import XCTest
import AppKit
import SwiftUI
@testable import MacMuster

/// Covers `VisualEffectBackground`'s update behaviour. Regression: `updateNSView` used to tear down
/// and rebuild the whole material view tree on every SwiftUI update — destroying and recreating an
/// `NSVisualEffectView`/`NSGlassEffectView` (a GPU-backed blur) on each tick of the opacity or tint
/// slider. It should rebuild only when the *kind* of view needed changes, and update colours in place.
@MainActor
final class VisualEffectBackgroundTests: XCTestCase {

    private var appModel: AppModel!
    private var host: NSHostingView<VisualEffectBackground>!
    private var window: NSWindow!

    override func setUp() async throws {
        appModel = AppModel()
        appModel.settings.glassStyle = .classic
        appModel.settings.simpleGlass = false
        appModel.settings.presentationMode = .glass
        appModel.settings.tintStrength = 0
        host = NSHostingView(rootView: VisualEffectBackground(appModel: appModel))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        settle()
    }

    override func tearDown() async throws {
        window.contentView = nil
        window = nil; host = nil; appModel = nil
    }

    /// Forces SwiftUI to run `updateNSView` with the model's current settings.
    private func settle() {
        host.rootView = VisualEffectBackground(appModel: appModel)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private var effectViews: [NSVisualEffectView] { descendants(of: host).compactMap { $0 as? NSVisualEffectView } }

    private func tintView() -> NSView? {
        descendants(of: host).first { $0.identifier?.rawValue == "MacMuster.tint" }
    }

    private func tintLayer() -> CALayer? { tintView()?.layer }

    private func sheetColor() -> CGColor? {
        descendants(of: host).compactMap { $0.layer?.backgroundColor }.first
    }

    // MARK: - No rebuild when nothing structural changed

    func testRepeatedUpdatesKeepTheSameEffectView() throws {
        let original = try XCTUnwrap(effectViews.first)
        for _ in 0..<5 { settle() }
        XCTAssertEqual(effectViews.count, 1, "Updates must not accumulate material views")
        XCTAssertTrue(effectViews.first === original, "An update with no structural change must reuse the live blur view")
    }

    func testChangingTintKeepsTheEffectViewAndRecolorsInPlace() throws {
        appModel.settings.tintStrength = 0.4
        settle()
        let original = try XCTUnwrap(effectViews.first)
        let firstColor = try XCTUnwrap(tintLayer()?.backgroundColor)

        appModel.settings.tintColor = .red
        appModel.settings.tintStrength = 0.8
        settle()

        XCTAssertTrue(effectViews.first === original, "Dragging the tint slider must not recreate the blur")
        XCTAssertNotEqual(tintLayer()?.backgroundColor, firstColor, "The tint colour must still update")
    }

    // MARK: - Tint placement

    /// Regression: the tint was a bare sublayer that ended up behind the blur, so even full-strength
    /// tint changed nothing on screen. It is now a view, and a view's place in `subviews` is its
    /// stacking order.
    func testTintViewIsStackedAboveTheMaterial() throws {
        appModel.settings.tintStrength = 0.5
        settle()
        let tint = try XCTUnwrap(tintView())
        let material = try XCTUnwrap(effectViews.first)
        let container = try XCTUnwrap(tint.superview)

        XCTAssertTrue(material.superview === container)
        let tintIndex = try XCTUnwrap(container.subviews.firstIndex(of: tint))
        let materialIndex = try XCTUnwrap(container.subviews.firstIndex(of: material))
        XCTAssertGreaterThan(tintIndex, materialIndex, "The tint must be above the material to be visible")
    }

    func testTintCoversTheWholeBackground() throws {
        appModel.settings.tintStrength = 0.5
        settle()
        let tint = try XCTUnwrap(tintView())
        XCTAssertEqual(tint.frame, tint.superview?.bounds, "The tint must fill the container")
        XCTAssertGreaterThan(tint.frame.width, 0)
    }

    func testTintDoesNotInterceptClicks() throws {
        appModel.settings.tintStrength = 0.5
        settle()
        let tint = try XCTUnwrap(tintView())
        XCTAssertNil(tint.hitTest(NSPoint(x: 10, y: 10)), "The tint is decoration; clicks must reach the content")
    }

    func testTintHasAVisibleColour() throws {
        appModel.settings.tintColor = .red
        appModel.settings.tintStrength = 1.0
        settle()
        let color = try XCTUnwrap(tintLayer()?.backgroundColor)
        XCTAssertGreaterThan(color.alpha, 0.5)
    }

    // MARK: - Rebuild when the kind of view changes

    func testTogglingLowGpuGlassReplacesTheEffectView() throws {
        let original = try XCTUnwrap(effectViews.first)
        XCTAssertEqual(original.blendingMode, .behindWindow)

        appModel.settings.simpleGlass = true
        settle()

        let replacement = try XCTUnwrap(effectViews.first)
        XCTAssertFalse(replacement === original)
        XCTAssertEqual(replacement.blendingMode, .withinWindow)
        XCTAssertEqual(replacement.state, .inactive)
        XCTAssertEqual(effectViews.count, 1)
    }

    func testTurningTintOnAndOffAddsAndRemovesTheTintLayer() {
        XCTAssertNil(tintLayer())

        appModel.settings.tintStrength = 0.5
        settle()
        XCTAssertNotNil(tintLayer())

        appModel.settings.tintStrength = 0
        settle()
        XCTAssertNil(tintLayer(), "A zero tint must not leave a stale tint layer behind")
    }

    func testSwitchingToSheetDropsTheBlurAndBackRestoresIt() {
        appModel.settings.presentationMode = .sheet
        settle()
        XCTAssertTrue(effectViews.isEmpty, "Sheet is an opaque fill; there is no blur to keep")
        XCTAssertNotNil(sheetColor())

        appModel.settings.presentationMode = .glass
        settle()
        XCTAssertEqual(effectViews.count, 1)
    }

    func testSheetColourUpdatesInPlace() throws {
        appModel.settings.presentationMode = .sheet
        appModel.settings.tintStrength = 0.5
        settle()
        let before = try XCTUnwrap(sheetColor())
        let layerBefore = try XCTUnwrap(descendants(of: host).compactMap { $0.layer }.first { $0.backgroundColor != nil })

        appModel.settings.tintColor = .green
        settle()

        let layerAfter = try XCTUnwrap(descendants(of: host).compactMap { $0.layer }.first { $0.backgroundColor != nil })
        XCTAssertTrue(layerAfter === layerBefore, "Recolouring a sheet must not rebuild its view")
        XCTAssertNotEqual(sheetColor(), before)
    }
}
