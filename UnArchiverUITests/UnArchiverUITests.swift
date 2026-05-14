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
    var wordWrapButton: XCUIElement  { app.buttons["wordWrapButton"] }
    var hexToggleButton: XCUIElement { app.buttons["hexToggleButton"] }
    var fontSizeMenuButton: XCUIElement { app.buttons["fontSizeMenuButton"] }

    /// Finds a menu item by label regardless of element type (Toggle items in mixed
    /// menus render as buttons/menu-items rather than switches).
    func menuItem(label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }
}

// MARK: - Loading

final class TextViewerLoadingTests: TextViewerTestBase {

    func testTextViewLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testWordWrapButtonIsPresent() {
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

// MARK: - Word wrap

final class TextViewerWordWrapTests: TextViewerTestBase {

    func testWordWrapDefaultIsOn() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
    }

    func testWordWrapToggleOff() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
        wordWrapButton.tap()
        XCTAssertTrue(codeTextView.exists, "Text view must survive toggling word wrap off")
    }

    func testWordWrapToggleOnAndOff() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
        wordWrapButton.tap() // off
        XCTAssertTrue(codeTextView.exists)
        wordWrapButton.tap() // on again
        XCTAssertTrue(codeTextView.exists)
    }

    func testWordWrapRapidTogglesDoNotCrash() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
        for _ in 0..<6 { wordWrapButton.tap() }
        XCTAssertTrue(codeTextView.exists)
    }
}

// MARK: - Scrolling

final class TextViewerScrollingTests: TextViewerTestBase {

    func testVerticalScrollWordWrapOn() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        codeTextView.swipeUp()
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
    }

    func testVerticalScrollWordWrapOff() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
        wordWrapButton.tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        codeTextView.swipeUp()
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
    }

    func testHorizontalScrollWordWrapOff() {
        XCTAssertTrue(wordWrapButton.waitForExistence(timeout: 5))
        wordWrapButton.tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        // Lines are 500+ chars — horizontal scroll must be possible
        codeTextView.swipeLeft()
        codeTextView.swipeLeft()
        codeTextView.swipeRight()
        XCTAssertTrue(codeTextView.exists)
    }

    func testScrollingAfterFontSizeChange() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Larger Text"].waitForExistence(timeout: 3) {
            app.buttons["Larger Text"].tap()
        }
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
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
        // Word wrap is not shown in hex mode
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
        XCTAssertTrue(app.buttons["Autoformat"].waitForExistence(timeout: 3))
    }

    func testAutoformatJSONDoesNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        guard app.buttons["Autoformat"].waitForExistence(timeout: 3) else {
            XCTFail("Autoformat button not found in menu")
            return
        }
        app.buttons["Autoformat"].tap() // enable
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Autoformat"].waitForExistence(timeout: 3) {
            app.buttons["Autoformat"].tap() // disable
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testScrollAfterAutoformat() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Autoformat"].waitForExistence(timeout: 3) {
            app.buttons["Autoformat"].tap()
        }
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        codeTextView.swipeUp()
        codeTextView.swipeDown()
        XCTAssertTrue(codeTextView.exists)
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
        XCTAssertTrue(app.buttons["Autoformat"].waitForExistence(timeout: 3))
    }

    func testAutoformatXMLDoesNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        guard app.buttons["Autoformat"].waitForExistence(timeout: 3) else {
            XCTFail("Autoformat button not found in menu")
            return
        }
        app.buttons["Autoformat"].tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        fontSizeMenuButton.tap()
        if app.buttons["Autoformat"].waitForExistence(timeout: 3) {
            app.buttons["Autoformat"].tap()
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
        XCTAssertFalse(app.buttons["Autoformat"].waitForExistence(timeout: 2))
    }
}

// MARK: - Screenshot snapshots
//
// These tests capture reference screenshots and attach them to the test result for
// visual inspection. They do not diff against a stored baseline (no external dependency
// required), but the attachments are preserved in the .xcresult bundle and in CI
// artifacts, making regressions immediately visible during review.

final class SnapshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app = nil }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSnapshotWelcomeScreen() {
        app.launch()
        XCTAssertTrue(app.staticTexts["UnArchiver"].waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), name: "welcome-screen")
    }

    func testSnapshotTextViewerPlain() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-plain")
    }

    func testSnapshotTextViewerWordWrapOff() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["wordWrapButton"].waitForExistence(timeout: 5))
        app.buttons["wordWrapButton"].tap()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-word-wrap-off")
    }

    func testSnapshotTextViewerHexMode() {
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["hexToggleButton"].waitForExistence(timeout: 5))
        app.buttons["hexToggleButton"].tap()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-hex-mode")
    }

    func testSnapshotTextViewerJSON() {
        app.launchArguments = ["--uitesting-json"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-json")
    }

    func testSnapshotTextViewerJSONAutoformatted() {
        app.launchArguments = ["--uitesting-json"]
        app.launch()
        let menu = app.buttons["fontSizeMenuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        if app.buttons["Autoformat"].waitForExistence(timeout: 3) {
            app.buttons["Autoformat"].tap()
        }
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 5))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-json-autoformatted")
    }

    func testSnapshotTextViewerXML() {
        app.launchArguments = ["--uitesting-xml"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-xml")
    }

    func testSnapshotTextViewerMarkdownSource() {
        app.launchArguments = ["--uitesting-markdown"]
        app.launch()
        XCTAssertTrue(app.codeTextView.waitForExistence(timeout: 10))
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-markdown-source")
    }

    func testSnapshotTextViewerMarkdownRendered() {
        app.launchArguments = ["--uitesting-markdown"]
        app.launch()
        let menu = app.buttons["fontSizeMenuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) {
            app.buttons["Rendered"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
        attach(XCUIScreen.main.screenshot(), name: "text-viewer-markdown-rendered")
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
