import XCTest
import UIKit

// MARK: - Shared helpers

private extension XCUIApplication {
    var codeTextView: XCUIElement {
        let tv = textViews["codeTextView"]
        return tv.exists ? tv : scrollViews["codeTextView"]
    }
    func waitForCodeTextView(timeout: TimeInterval = 10) -> Bool {
        codeTextView.waitForExistence(timeout: timeout)
    }

    /// Finds a menu item by label regardless of element type. Toggle items in mixed
    /// SwiftUI menus surface as buttons/menu-items rather than switches, so matching by
    /// label is more reliable than `buttons[identifier]`.
    func menuItem(label: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// Word wrap now lives inside the options menu, so toggling it means opening the
    /// menu and tapping the item (which dismisses the menu again).
    func toggleWordWrap() {
        let menu = buttons["fontSizeMenuButton"]
        _ = menu.waitForExistence(timeout: 5)
        menu.tap()
        let item = menuItem(label: "Word Wrap")
        _ = item.waitForExistence(timeout: 3)
        item.tap()
    }
}

// MARK: - Welcome screen

final class WelcomeScreenTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    func testAppLaunches() {
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testUnArchiverTitleIsVisible() {
        XCTAssertTrue(app.staticTexts["UnArchiver"].waitForExistence(timeout: 5))
    }

    func testOpenButtonExists() {
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
    }

    func testVersionLabelExists() {
        // The version label is a small caption — just verify something is rendered
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))
    }
}

// MARK: - Base class for TextViewer tests

class TextViewerTestBase: XCTestCase {
    var app: XCUIApplication!

    /// Subclasses override to customise launch args
    var launchArgs: [String] { ["--uitesting"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = launchArgs
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: Convenience element accessors

    var codeTextView: XCUIElement    { app.codeTextView }
    /// Word wrap is a Toggle inside the options menu; match it by label.
    var wordWrapButton: XCUIElement  { app.menuItem(label: "Word Wrap") }
    var hexToggleButton: XCUIElement { app.buttons["hexToggleButton"] }
    var fontSizeMenuButton: XCUIElement { app.buttons["fontSizeMenuButton"] }

    /// Finds a menu item by label regardless of element type (Toggle items in mixed
    /// menus render as buttons/menu-items rather than switches).
    func menuItem(label: String) -> XCUIElement {
        app.menuItem(label: label)
    }
}

// MARK: - Loading

final class TextViewerLoadingTests: TextViewerTestBase {

    func testTextViewLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testWordWrapButtonIsPresent() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
    }

    func testHexToggleButtonIsPresent() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
    }

    func testFontSizeMenuIsPresent() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
    }

    func testShareButtonIsPresent() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3))
    }
}

// MARK: - Word wrap behavioral tests
//
// Uses --uitesting-lorem: 50 lines × ~450 chars per line.
// IndentGuideTextView exposes scroll geometry via accessibilityValue:
//   "cw:NNN,ch:NNN,ox:NNN,oy:NNN"
// so these tests assert real layout state, not just that the view survives.

final class TextViewerWordWrapBehaviorTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-lorem"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var textView: XCUIElement    { app.codeTextView }

    private struct ScrollState {
        let contentWidth: Int
        let contentHeight: Int
        let offsetX: Int
        let offsetY: Int
    }

    private func scrollState(of el: XCUIElement) -> ScrollState? {
        guard let raw = el.value as? String else { return nil }
        var d = [String: Int]()
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            guard kv.count == 2, let v = Int(kv[1]) else { continue }
            d[String(kv[0])] = v
        }
        guard let cw = d["cw"], let ch = d["ch"],
              let ox = d["ox"], let oy = d["oy"] else { return nil }
        return ScrollState(contentWidth: cw, contentHeight: ch, offsetX: ox, offsetY: oy)
    }

    /// Polls until `condition` is true or `timeout` seconds have elapsed.
    private func waitUntil(timeout: TimeInterval = 3, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    // Word wrap ON (default): content width must not exceed the frame — text is wrapping.
    func testWordWrapOnConstrainsContentWidth() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5) // let layout settle
        guard let state = scrollState(of: textView) else {
            XCTFail("IndentGuideTextView must expose scroll geometry via accessibilityValue")
            return
        }
        let frameWidth = Int(textView.frame.width)
        XCTAssertLessThanOrEqual(
            state.contentWidth, frameWidth + 50,
            "Word wrap ON: content width \(state.contentWidth) must fit within frame width \(frameWidth)"
        )
    }

    // Word wrap OFF: ~450-char lines must expand content far beyond the frame width.
    func testWordWrapOffExpandsContentWidth() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        let frameWidth = Int(textView.frame.width)
        var state: ScrollState?
        waitUntil { state = self.scrollState(of: self.textView); return (state?.contentWidth ?? 0) > frameWidth * 3 }
        guard let s = state else { XCTFail("accessibilityValue unavailable"); return }
        XCTAssertGreaterThan(
            s.contentWidth, frameWidth * 3,
            "Word wrap OFF: content width \(s.contentWidth) must far exceed frame width \(frameWidth)"
        )
    }

    // Swiping left with word wrap OFF must actually advance contentOffset.x.
    func testHorizontalSwipeScrollsWhenWrapOff() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)

        guard let before = scrollState(of: textView) else { XCTFail("Before state missing"); return }
        XCTAssertEqual(before.offsetX, 0, "View should start at horizontal offset 0")

        textView.swipeLeft()

        var after: ScrollState?
        waitUntil { after = self.scrollState(of: self.textView); return (after?.offsetX ?? 0) > 0 }

        XCTAssertGreaterThan(
            after?.offsetX ?? 0, 0,
            "Swiping left with word wrap OFF must increase contentOffset.x"
        )
    }

    // Swiping left with word wrap ON must NOT move content horizontally.
    func testHorizontalSwipeDoesNotScrollWhenWrapOn() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)

        textView.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        guard let state = scrollState(of: textView) else { XCTFail("State missing"); return }
        XCTAssertEqual(
            state.offsetX, 0,
            "Swiping left with word wrap ON must not scroll content horizontally"
        )
    }

    // Toggling ON→OFF→ON must restore content width to frame-constrained dimensions.
    func testWordWrapRoundtripRestoresContentWidth() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        let frameWidth = Int(textView.frame.width)

        guard let initial = scrollState(of: textView) else { XCTFail("Initial state missing"); return }
        XCTAssertLessThanOrEqual(initial.contentWidth, frameWidth + 50, "Should start wrapped")

        app.toggleWordWrap() // OFF
        var offState: ScrollState?
        waitUntil { offState = self.scrollState(of: self.textView); return (offState?.contentWidth ?? 0) > frameWidth * 3 }
        XCTAssertGreaterThan(offState?.contentWidth ?? 0, frameWidth * 3, "Wrap OFF must expand width")

        app.toggleWordWrap() // ON again
        var onState: ScrollState?
        waitUntil { onState = self.scrollState(of: self.textView); return (onState?.contentWidth ?? 0) <= frameWidth + 50 }
        XCTAssertLessThanOrEqual(
            onState?.contentWidth ?? Int.max, frameWidth + 50,
            "Toggling back ON must re-constrain content width. Got \(onState?.contentWidth ?? -1)"
        )
    }

    // After scrolling right with wrap OFF, re-enabling wrap must reset horizontal offset to 0.
    func testEnablingWrapResetsHorizontalOffset() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        app.toggleWordWrap() // OFF
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)

        textView.swipeLeft()
        waitUntil { (self.scrollState(of: self.textView)?.offsetX ?? 0) > 0 }

        app.toggleWordWrap() // ON
        Thread.sleep(forTimeInterval: 0.5)

        guard let state = scrollState(of: textView) else { XCTFail("State missing"); return }
        XCTAssertEqual(state.offsetX, 0, "Re-enabling word wrap must reset horizontal scroll offset to 0")
    }

    // Rapid toggles must not crash.
    func testRapidWordWrapTogglesDoNotCrash() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        for _ in 0..<6 { app.toggleWordWrap() }
        XCTAssertTrue(textView.exists)
    }
}

// MARK: - Word-wrap toggle clipping tests
//
// Reproduces the reported bug: after toggling word wrap (any file type) the view
// shows only blank whitespace when scrolled right. The existing tests miss it
// because apply() force-resets contentOffset.x to 0 right after a toggle, so a
// check done immediately after toggling looks fine — but the inflated
// contentSize.width from the no-wrap layout survives, leaving horizontal scroll
// room over an empty region. The trigger is: scroll right while wrapped OFF, then
// toggle back ON, then try to scroll again. These tests do exactly that and assert
// the view still shows text (ink), not whitespace.

final class TextViewerWrapToggleClippingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The actual reported repro: a short Markdown doc (heading + two very long
        // paragraph lines). Markdown is syntax-highlighted, unlike the plain lorem
        // fixture — that highlighting is what makes the wrap toggle leave stale-wide
        // content. See mdLongContent in UnArchiverApp.
        app.launchArguments = ["--uitesting-mdlong"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var textView: XCUIElement { app.codeTextView }

    private struct ScrollState {
        let contentWidth: Int
        let offsetX: Int
    }

    private func scrollState(of el: XCUIElement) -> ScrollState? {
        guard let raw = el.value as? String else { return nil }
        var d = [String: Int]()
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            guard kv.count == 2, let v = Int(kv[1]) else { continue }
            d[String(kv[0])] = v
        }
        guard let cw = d["cw"], let ox = d["ox"] else { return nil }
        return ScrollState(contentWidth: cw, offsetX: ox)
    }

    private func waitUntil(timeout: TimeInterval = 3, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Fraction of pixels in the element's screenshot that differ noticeably from the
    /// top-left (background) pixel. ~0 means a uniform / blank region; text adds "ink".
    private func inkFraction(of element: XCUIElement) -> Double {
        guard let cg = element.screenshot().image.cgImage else { return 0 }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return 0 }
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Background = corner pixel (the 12pt text container inset guarantees the
        // very corner is empty regardless of light/dark theme).
        let bgR = Int(pixels[0]), bgG = Int(pixels[1]), bgB = Int(pixels[2])
        var ink = 0
        var i = 0
        while i < pixels.count {
            let dr = abs(Int(pixels[i])     - bgR)
            let dg = abs(Int(pixels[i + 1]) - bgG)
            let db = abs(Int(pixels[i + 2]) - bgB)
            if dr + dg + db > 60 { ink += 1 }
            i += bytesPerPixel
        }
        return Double(ink) / Double(w * h)
    }

    /// Drives the exact repro: wrap ON → wrap OFF → scroll right → wrap ON.
    /// Asserts each precondition so the test can NEVER pass vacuously: if the menu
    /// toggle or the swipe silently fails to take effect, these fire instead of the
    /// later assertions trivially succeeding.
    private func scrollRightThenReenableWrap() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        let frameWidth = Int(textView.frame.width)

        app.toggleWordWrap() // OFF — content width inflates to full line width
        var offWidth = 0
        waitUntil { offWidth = self.scrollState(of: self.textView)?.contentWidth ?? 0; return offWidth > frameWidth * 3 }
        XCTAssertGreaterThan(
            offWidth, frameWidth * 3,
            "PRECONDITION: turning word wrap OFF must widen the content (got contentWidth " +
            "\(offWidth) vs frame \(frameWidth)). If this fails the wrap toggle never took " +
            "effect and the rest of the test would pass vacuously."
        )

        textView.swipeLeft() // scroll right into the now-wide content
        textView.swipeLeft()
        var scrolledX = 0
        waitUntil { scrolledX = self.scrollState(of: self.textView)?.offsetX ?? 0; return scrolledX > 0 }
        XCTAssertGreaterThan(
            scrolledX, 0,
            "PRECONDITION: must actually scroll right (offsetX > 0) while word wrap is OFF; " +
            "got \(scrolledX). Without this the re-enable step proves nothing."
        )

        app.toggleWordWrap() // ON again
        Thread.sleep(forTimeInterval: 0.6)
    }

    // After re-enabling wrap, the content must be re-constrained to the view width
    // so there is no blank horizontal region to scroll into.
    func testReenablingWrapRemovesHorizontalScrollRoom() {
        scrollRightThenReenableWrap()
        guard let state = scrollState(of: textView) else { XCTFail("State missing"); return }
        let frameWidth = Int(textView.frame.width)
        XCTAssertLessThanOrEqual(
            state.contentWidth, frameWidth + 50,
            "After scrolling right then re-enabling word wrap, content width " +
            "\(state.contentWidth) still exceeds frame \(frameWidth): the view keeps " +
            "blank horizontal scroll room (the clipping bug)."
        )
    }

    // The user's exact symptom: after the toggle, swiping to scroll right must keep
    // text on screen, not slide it away to reveal blank whitespace.
    func testScrollRightAfterReenablingWrapShowsText() {
        scrollRightThenReenableWrap()

        XCTAssertGreaterThan(inkFraction(of: textView), 0.02, "Sanity: text visible after re-enabling wrap")

        textView.swipeLeft()
        textView.swipeLeft()
        textView.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertEqual(
            scrollState(of: textView)?.offsetX, 0,
            "Word wrap ON: must not scroll horizontally into blank space after a toggle"
        )
        let after = inkFraction(of: textView)
        XCTAssertGreaterThan(
            after, 0.02,
            "After toggling word wrap and scrolling right the view is blank (ink=\(after)) — " +
            "only whitespace shows. The word-wrap clipping bug."
        )
    }

    // Regression: enabling Layout Debug with word wrap OFF must not crash. In no-wrap
    // mode the text container width is CGFloat.greatestFiniteMagnitude, and the overlay
    // formerly did Int(greatestFiniteMagnitude), which traps (EXC_BREAKPOINT). This
    // reproduces that exact path and asserts the app stays alive.
    func testLayoutDebugWithWordWrapOffDoesNotCrash() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.3)

        app.toggleWordWrap() // OFF → container width becomes .greatestFiniteMagnitude
        Thread.sleep(forTimeInterval: 0.3)

        // Enable Layout Debug from the options menu.
        let menu = app.buttons["fontSizeMenuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let item = app.menuItem(label: "Layout Debug")
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()

        // Force layout/scroll while the overlay is live.
        textView.swipeLeft()
        textView.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertEqual(
            app.state, .runningForeground,
            "Enabling Layout Debug with word wrap OFF must not crash the app"
        )
        XCTAssertTrue(textView.exists)
    }
}

// MARK: - No-wrap rendering tests
//
// The decisive test for the word-wrap-off clipping bug. With word wrap OFF the view
// reports a wide contentSize and scrolls horizontally, but glyphs are only laid out in
// the first bounds-width of content: layoutSubviews forges contentSize from
// layoutManager.usedRect, which widens the SCROLLABLE range without widening the
// surface UITextView actually RENDERS into. Scrolling right past the first screenful
// then shows blank background where text should be.
//
// Numeric assertions (contentWidth / offsetX via accessibilityValue) cannot catch
// this: they read back the very values the implementation forges. Only pixels can —
// so this test scrolls fully past the first screen-width and asserts the viewport
// still contains ink.

final class TextViewerNoWrapRenderingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Lorem: 50 lines × ~450 chars (~3500pt wide unwrapped). Every visible row is
        // mid-sentence text at any horizontal offset, so ink stays high wherever
        // glyphs are actually rendered — and drops to ~0 where they are not.
        app.launchArguments = ["--uitesting-lorem"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var textView: XCUIElement { app.codeTextView }

    private func scrollState(of el: XCUIElement) -> (contentWidth: Int, offsetX: Int)? {
        guard let raw = el.value as? String else { return nil }
        var d = [String: Int]()
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            guard kv.count == 2, let v = Int(kv[1]) else { continue }
            d[String(kv[0])] = v
        }
        guard let cw = d["cw"], let ox = d["ox"] else { return nil }
        return (cw, ox)
    }

    private func waitUntil(timeout: TimeInterval = 3, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Fraction of pixels differing noticeably from the top-left (background) pixel.
    /// ~0 means a blank viewport; rendered text pushes this well above 0.03.
    private func inkFraction(of element: XCUIElement) -> Double {
        guard let cg = element.screenshot().image.cgImage else { return 0 }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return 0 }
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let bgR = Int(pixels[0]), bgG = Int(pixels[1]), bgB = Int(pixels[2])
        var ink = 0
        var i = 0
        while i < pixels.count {
            let dr = abs(Int(pixels[i])     - bgR)
            let dg = abs(Int(pixels[i + 1]) - bgG)
            let db = abs(Int(pixels[i + 2]) - bgB)
            if dr + dg + db > 60 { ink += 1 }
            i += bytesPerPixel
        }
        return Double(ink) / Double(w * h)
    }

    // Word wrap OFF: after scrolling fully past the first screen-width of content,
    // the viewport must still show text. If glyph layout is clipped to the view
    // bounds while the scroll range is forged wide (the bug), the viewport here is
    // pure background and this fails.
    func testTextIsRenderedBeyondFirstScreenWhenWrapOff() {
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        let frameWidth = Int(textView.frame.width)

        XCTAssertGreaterThan(
            inkFraction(of: textView), 0.03,
            "Sanity: text must be visible before scrolling"
        )

        app.toggleWordWrap() // OFF
        var offWidth = 0
        waitUntil { offWidth = self.scrollState(of: self.textView)?.contentWidth ?? 0; return offWidth > frameWidth * 3 }
        XCTAssertGreaterThan(
            offWidth, frameWidth * 3,
            "PRECONDITION: wrap OFF must report content much wider than the frame " +
            "(got \(offWidth) vs frame \(frameWidth)); otherwise this test proves nothing"
        )

        // Scroll right until well past TWICE the viewport width. Empirically the broken
        // render surface extends to about 2× the viewport (bounds + overdraw): at
        // offsetX ≈ 1.7× frame the viewport still showed partial ink (0.0299), a
        // hair under threshold. Past 2× frame the bug state is decisively blank
        // (~0.002) while a correct implementation still shows full text (~0.1),
        // giving this assertion wide margins on both sides.
        let targetOffset = frameWidth * 2 + 50
        var offsetX = 0
        for _ in 0..<10 {
            textView.swipeLeft()
            waitUntil(timeout: 1.5) {
                offsetX = self.scrollState(of: self.textView)?.offsetX ?? 0
                return offsetX > targetOffset
            }
            if offsetX > targetOffset { break }
        }
        XCTAssertGreaterThan(
            offsetX, targetOffset,
            "PRECONDITION: must scroll past 2× the viewport width " +
            "(offsetX \(offsetX) vs target \(targetOffset)); otherwise this test proves nothing"
        )

        Thread.sleep(forTimeInterval: 0.6) // let deceleration settle
        let shot = textView.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "no-wrap-viewport-at-offset-\(offsetX)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let ink = inkFraction(of: textView)
        XCTAssertGreaterThan(
            ink, 0.03,
            "Word wrap OFF: viewport at offsetX \(offsetX) (content \(offWidth), frame " +
            "\(frameWidth)) is blank (ink=\(ink)). Glyphs are only rendered near the first " +
            "screen-width — the scroll range is forged wide while the render surface " +
            "stays bounds-wide. This is the word-wrap clipping bug."
        )
    }
}

// MARK: - Scrolling behavioral tests

final class TextViewerScrollingTests: TextViewerTestBase {

    private struct ScrollState { let offsetX: Int; let offsetY: Int }

    private func scrollState(of el: XCUIElement) -> ScrollState {
        var ox = 0, oy = 0
        if let raw = el.value as? String {
            for pair in raw.split(separator: ",") {
                let kv = pair.split(separator: ":")
                guard kv.count == 2, let v = Int(kv[1]) else { continue }
                if kv[0] == "ox" { ox = v }
                if kv[0] == "oy" { oy = v }
            }
        }
        return ScrollState(offsetX: ox, offsetY: oy)
    }

    private func waitUntil(timeout: TimeInterval = 3, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    // Swiping up with word wrap ON must increase contentOffset.y.
    func testVerticalSwipeScrollsWrapOn() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        let before = scrollState(of: codeTextView).offsetY
        codeTextView.swipeUp()
        var after = before
        waitUntil { after = self.scrollState(of: self.codeTextView).offsetY; return after > before }
        XCTAssertGreaterThan(after, before, "Swiping up must increase vertical scroll offset (wrap ON)")
    }

    // Swiping up with word wrap OFF must increase contentOffset.y.
    func testVerticalSwipeScrollsWrapOff() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        let before = scrollState(of: codeTextView).offsetY
        codeTextView.swipeUp()
        var after = before
        waitUntil { after = self.scrollState(of: self.codeTextView).offsetY; return after > before }
        XCTAssertGreaterThan(after, before, "Swiping up must increase vertical scroll offset (wrap OFF)")
    }

    // Swiping left with word wrap OFF must increase contentOffset.x.
    func testHorizontalSwipeScrollsWrapOff() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(scrollState(of: codeTextView).offsetX, 0, "Should start at offset 0")
        codeTextView.swipeLeft()
        var after = 0
        waitUntil { after = self.scrollState(of: self.codeTextView).offsetX; return after > 0 }
        XCTAssertGreaterThan(after, 0, "Swiping left must increase horizontal scroll offset when wrap is OFF")
    }

    // Swiping right after scrolling must decrease contentOffset.x back toward 0.
    func testSwipeRightAfterLeftReducesOffset() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)

        codeTextView.swipeLeft()
        var scrolledX = 0
        waitUntil { scrolledX = self.scrollState(of: self.codeTextView).offsetX; return scrolledX > 0 }
        guard scrolledX > 0 else { XCTFail("Could not scroll right first"); return }

        codeTextView.swipeRight()
        var after = scrolledX
        waitUntil { after = self.scrollState(of: self.codeTextView).offsetX; return after < scrolledX }
        XCTAssertLessThan(after, scrolledX, "Swiping right must decrease horizontal offset")
    }

    func testScrollingAfterFontSizeChange() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Larger Text"].waitForExistence(timeout: 3) {
            app.buttons["Larger Text"].tap()
        }
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        let before = scrollState(of: codeTextView).offsetY
        codeTextView.swipeUp()
        var after = before
        waitUntil { after = self.scrollState(of: self.codeTextView).offsetY; return after > before }
        XCTAssertGreaterThan(after, before, "Swiping up after font size change must scroll vertically")
    }

    func testWordWrapOffScrollsHorizontallyForReal() {
        // Lines are ~200 chars wide — with word wrap off, the content must extend
        // beyond the screen width and be reachable by horizontal swiping.
        // If text is clipped to screen width (bug), swiping left produces no visual
        // change and the two screenshots will be identical → test fails.
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))

        let before = XCUIScreen.main.screenshot()
        codeTextView.swipeLeft()
        codeTextView.swipeLeft()
        codeTextView.swipeLeft()
        let after = XCUIScreen.main.screenshot()

        XCTAssertNotEqual(
            before.pngRepresentation, after.pngRepresentation,
            "With word wrap off, swiping left must scroll content horizontally. " +
            "Identical screenshots indicate text is clipped to screen width instead of scrolling."
        )
    }
}

// MARK: - Hex view

final class TextViewerHexTests: TextViewerTestBase {

    func testHexButtonExistsInTextMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
    }

    func testSwitchToHexMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
    }

    func testWordWrapButtonHiddenInHexMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap()
        // Word wrap toggle only appears in the options menu in text mode
        fontSizeMenuButton.tap()
        XCTAssertFalse(wordWrapButton.exists)
    }

    func testDisplayOptionsHiddenInHexMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap()
        // Whitespace/indent options only appear in text mode
        fontSizeMenuButton.tap()
        XCTAssertFalse(menuItem(label: "Whitespace Indicators").waitForExistence(timeout: 2))
    }

    func testReturnFromHexToText() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap() // → hex
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        hexToggleButton.tap() // → text
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
    }

    func testScrollInHexMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
    }
}

// MARK: - Font size

final class TextViewerFontSizeTests: TextViewerTestBase {

    func testFontSizeMenuOpens() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        let larger = app.buttons["Larger Text"]
        let smaller = app.buttons["Smaller Text"]
        XCTAssertTrue(
            larger.waitForExistence(timeout: 3) || smaller.waitForExistence(timeout: 3),
            "Font size menu should show Larger/Smaller Text items"
        )
    }

    func testIncreaseFontSize() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Larger Text"].waitForExistence(timeout: 3) {
            app.buttons["Larger Text"].tap()
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testDecreaseFontSize() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Smaller Text"].waitForExistence(timeout: 3) {
            app.buttons["Smaller Text"].tap()
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testFontSizeMinimumNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        // Tap smaller several times — minimum is 10pt, should not crash
        for _ in 0..<4 {
            fontSizeMenuButton.tap()
            if app.buttons["Smaller Text"].waitForExistence(timeout: 2) {
                app.buttons["Smaller Text"].tap()
            }
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testFontSizeMaximumNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        // Tap larger several times — maximum is 24pt, should not crash
        for _ in 0..<4 {
            fontSizeMenuButton.tap()
            if app.buttons["Larger Text"].waitForExistence(timeout: 2) {
                app.buttons["Larger Text"].tap()
            }
        }
        XCTAssertTrue(codeTextView.exists)
    }
}

// MARK: - Search

final class TextViewerSearchTests: TextViewerTestBase {

    private func activateSearchField() -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.isHittable {
            codeTextView.swipeDown()
        }
        return field
    }

    func testSearchBarIsPresent() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        let field = activateSearchField()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testSearchFindsMatches() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        let field = activateSearchField()
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Search field not found")
            return
        }
        field.tap()
        field.typeText("ABCDEFGHIJ")
        let pred = NSPredicate(format: "label CONTAINS[c] 'match'")
        let matchLabel = app.staticTexts.matching(pred).firstMatch
        XCTAssertTrue(matchLabel.waitForExistence(timeout: 5),
                      "Expected a match-count label after searching for known content")
    }

    func testSearchNoMatches() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        let field = activateSearchField()
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        field.typeText("ZZZNOMATCH999XYZ")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
    }

    func testClearSearchRestoresView() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        let field = activateSearchField()
        guard field.waitForExistence(timeout: 5) else { return }
        field.tap()
        field.typeText("Line")
        field.clearText()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
    }
}

// MARK: - Display options (whitespace / indent guides)

final class TextViewerDisplayOptionsTests: TextViewerTestBase {

    func testDisplayOptionsMenuExists() {
        // Wait for content to load before interacting with menu
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        // Display options are consolidated inside the font size menu
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(menuItem(label: "Whitespace Indicators").waitForExistence(timeout: 3))
    }

    func testWhitespaceToggle() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        let toggle = menuItem(label: "Whitespace Indicators")
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        XCTAssertTrue(codeTextView.exists)
    }

    func testIndentGuidesToggle() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        let toggle = menuItem(label: "Indent Guides")
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        XCTAssertTrue(codeTextView.exists)
    }

    func testBothDisplayOptionsToggle() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        // Enable whitespace
        fontSizeMenuButton.tap()
        let whitespace = menuItem(label: "Whitespace Indicators")
        if whitespace.waitForExistence(timeout: 3) { whitespace.tap() }
        // Enable indent guides
        fontSizeMenuButton.tap()
        let indent = menuItem(label: "Indent Guides")
        if indent.waitForExistence(timeout: 3) { indent.tap() }
        XCTAssertTrue(codeTextView.exists)
        // Disable both
        fontSizeMenuButton.tap()
        if menuItem(label: "Whitespace Indicators").waitForExistence(timeout: 3) {
            menuItem(label: "Whitespace Indicators").tap()
        }
        fontSizeMenuButton.tap()
        if menuItem(label: "Indent Guides").waitForExistence(timeout: 3) {
            menuItem(label: "Indent Guides").tap()
        }
        XCTAssertTrue(codeTextView.exists)
    }
}

// MARK: - JSON content

final class TextViewerJSONTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-json"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var codeTextView: XCUIElement { app.codeTextView }
    private var fontSizeMenuButton: XCUIElement { app.buttons["fontSizeMenuButton"] }

    func testJSONLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testAutoformatButtonVisibleForJSON() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(app.menuItem(label: "Autoformat").waitForExistence(timeout: 3))
    }

    func testAutoformatJSONDoesNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        guard app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) else {
            XCTFail("Autoformat button not found in menu")
            return
        }
        app.menuItem(label: "Autoformat").tap() // enable
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) {
            app.menuItem(label: "Autoformat").tap() // disable
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testScrollAfterAutoformat() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) {
            app.menuItem(label: "Autoformat").tap()
        }
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
    }

    func testAutoformatMenuItemShowsCheckedState() {
        // The Autoformat control must indicate whether formatting is enabled by
        // showing a checkmark (selected state) in the menu — not act as a
        // stateless one-shot button. A plain Button never reports `isSelected`,
        // so this test fails for a button and passes for a checkbox-style Toggle.
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))

        // Before enabling, the item must be present and unchecked.
        fontSizeMenuButton.tap()
        let item = app.menuItem(label: "Autoformat")
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        XCTAssertFalse(item.isSelected, "Autoformat should start unchecked")
        item.tap() // enable (tapping a menu item dismisses the menu)

        // Reopen the menu: the item must now be checked.
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        let enabledItem = app.menuItem(label: "Autoformat")
        XCTAssertTrue(enabledItem.waitForExistence(timeout: 3))
        XCTAssertTrue(
            enabledItem.isSelected,
            "Autoformat must show a checkmark once formatting is enabled"
        )
    }

    func testAutoformatVisibleWhenWordWrapOff() {
        // Autoformat must remain in the font menu after word wrap is disabled.
        // With word wrap off, the text view gains horizontal scrolling but viewMode
        // stays .text and language stays "json", so isFormattable remains true.
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()

        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(
            app.menuItem(label: "Autoformat").waitForExistence(timeout: 3),
            "Autoformat must appear in options menu when word wrap is off for JSON"
        )
    }
}

// MARK: - XML content

final class TextViewerXMLTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-xml"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var codeTextView: XCUIElement { app.codeTextView }
    private var fontSizeMenuButton: XCUIElement { app.buttons["fontSizeMenuButton"] }

    func testXMLLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testAutoformatButtonVisibleForXML() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(app.menuItem(label: "Autoformat").waitForExistence(timeout: 3))
    }

    func testAutoformatXMLDoesNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        guard app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) else {
            XCTFail("Autoformat button not found in menu")
            return
        }
        app.menuItem(label: "Autoformat").tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) {
            app.menuItem(label: "Autoformat").tap()
        }
        XCTAssertTrue(codeTextView.exists)
    }
}

// MARK: - Markdown content

final class TextViewerMarkdownTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-markdown"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private var codeTextView: XCUIElement { app.codeTextView }
    private var fontSizeMenuButton: XCUIElement { app.buttons["fontSizeMenuButton"] }

    func testMarkdownLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testPreviewModeMenuExists() {
        // Preview mode options are inside the font size menu
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertTrue(app.buttons["Rendered"].waitForExistence(timeout: 3))
    }

    func testSwitchToRenderedMode() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) {
            app.buttons["Rendered"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSwitchRenderedThenBackToSource() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) { app.buttons["Rendered"].tap() }

        fontSizeMenuButton.tap()
        if app.buttons["Source"].waitForExistence(timeout: 3) { app.buttons["Source"].tap() }

        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
    }

    func testAutoformatButtonNotVisibleForMarkdown() {
        // Markdown is not JSON/XML so autoformat should be absent from the menu
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        XCTAssertFalse(app.menuItem(label: "Autoformat").waitForExistence(timeout: 2))
    }
}

// MARK: - Screenshot snapshots
//
// Captures key UI states as XCTAttachment screenshots preserved in the .xcresult
// bundle for visual inspection during review.
//
// NOTE: pixel-diff regression (assertSnapshot) requires swift-snapshot-testing linked
// to a unit test target, not a XCUITest bundle — Xcode refuses to load the Swift
// Testing module inside XCUITest bundles. A separate UnArchiverTests unit target
// with SwiftUI view snapshots is the correct home for that.

final class SnapshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app = nil }

    private func attach(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSnapshotWelcomeScreen() {
        app.launch()
        XCTAssertTrue(app.staticTexts["UnArchiver"].waitForExistence(timeout: 5))
        attach("welcome-screen")
    }

    func testSnapshotTextViewerPlain() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach("text-viewer-plain")
    }

    func testSnapshotTextViewerWordWrapOff() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        app.toggleWordWrap()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 5))
        attach("text-viewer-word-wrap-off")
    }

    func testSnapshotTextViewerHexMode() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["hexToggleButton"].waitForExistence(timeout: 5))
        app.buttons["hexToggleButton"].tap()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach("text-viewer-hex-mode")
    }

    func testSnapshotTextViewerJSON() {
        app.launchArguments = ["--uitesting-json"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach("text-viewer-json")
    }

    func testSnapshotTextViewerJSONAutoformatted() {
        app.launchArguments = ["--uitesting-json"]
        app.launch()
        let menu = app.buttons["fontSizeMenuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        if app.menuItem(label: "Autoformat").waitForExistence(timeout: 3) { app.menuItem(label: "Autoformat").tap() }
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 5))
        attach("text-viewer-json-autoformatted")
    }

    func testSnapshotTextViewerXML() {
        app.launchArguments = ["--uitesting-xml"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach("text-viewer-xml")
    }

    func testSnapshotTextViewerMarkdownSource() {
        app.launchArguments = ["--uitesting-markdown"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach("text-viewer-markdown-source")
    }

    func testSnapshotTextViewerMarkdownRendered() {
        app.launchArguments = ["--uitesting-markdown"]
        app.launch()
        let menu = app.buttons["fontSizeMenuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) { app.buttons["Rendered"].tap() }
        XCTAssertEqual(app.state, .runningForeground)
        attach("text-viewer-markdown-rendered")
    }
}

// MARK: - XCUIElement helpers

private extension XCUIElement {
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        tap()
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)
        typeText(delete)
    }
}
