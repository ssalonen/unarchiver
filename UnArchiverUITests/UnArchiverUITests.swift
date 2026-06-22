import XCTest

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
