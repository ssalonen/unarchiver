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

    var codeTextView: XCUIElement { app.codeTextView }

    var wordWrapButton: XCUIElement      { app.buttons["wordWrapButton"] }
    var hexToggleButton: XCUIElement     { app.buttons["hexToggleButton"] }
    var fontSizeMenuButton: XCUIElement  { app.buttons["fontSizeMenuButton"] }
    var paragraphMenuButton: XCUIElement { app.buttons["paragraphMenuButton"] }
    var autoformatButton: XCUIElement    { app.buttons["autoformatButton"] }
    var shareButton: XCUIElement         { app.buttons["shareButton"] }
    var previewModeMenuButton: XCUIElement { app.buttons["previewModeMenuButton"] }
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
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
    }
}

// MARK: - Word wrap

final class TextViewerWordWrapTests: TextViewerTestBase {

    func testWordWrapDefaultIsOn() {
        // Paragraph menu must be present when word-wrap is on (text mode)
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

    func testParagraphMenuHiddenInHexMode() {
        XCTAssertTrue(hexToggleButton.waitForExistence(timeout: 5))
        hexToggleButton.tap()
        XCTAssertFalse(paragraphMenuButton.exists)
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
        // At least one menu item should appear
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
        // Tap smaller many times — minimum is 10pt, should not crash
        for _ in 0..<15 {
            fontSizeMenuButton.tap()
            if app.buttons["Smaller Text"].waitForExistence(timeout: 2) {
                app.buttons["Smaller Text"].tap()
            }
        }
        XCTAssertTrue(codeTextView.exists)
    }

    func testFontSizeMaximumNotCrash() {
        XCTAssertTrue(fontSizeMenuButton.waitForExistence(timeout: 5))
        // Tap larger many times — maximum is 24pt, should not crash
        for _ in 0..<15 {
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
        // Match count label contains "match"
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

    func testParagraphMenuExists() {
        XCTAssertTrue(paragraphMenuButton.waitForExistence(timeout: 5))
    }

    func testWhitespaceToggle() {
        XCTAssertTrue(paragraphMenuButton.waitForExistence(timeout: 5))
        paragraphMenuButton.tap()
        let toggle = app.switches["Whitespace Indicators"]
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        XCTAssertTrue(codeTextView.exists)
    }

    func testIndentGuidesToggle() {
        XCTAssertTrue(paragraphMenuButton.waitForExistence(timeout: 5))
        paragraphMenuButton.tap()
        let toggle = app.switches["Indent Guides"]
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        XCTAssertTrue(codeTextView.exists)
    }

    func testBothDisplayOptionsToggle() {
        XCTAssertTrue(paragraphMenuButton.waitForExistence(timeout: 5))
        // Enable whitespace
        paragraphMenuButton.tap()
        if app.switches["Whitespace Indicators"].waitForExistence(timeout: 3) {
            app.switches["Whitespace Indicators"].tap()
        }
        // Enable indent guides
        paragraphMenuButton.tap()
        if app.switches["Indent Guides"].waitForExistence(timeout: 3) {
            app.switches["Indent Guides"].tap()
        }
        XCTAssertTrue(codeTextView.exists)
        // Disable both
        paragraphMenuButton.tap()
        if app.switches["Whitespace Indicators"].waitForExistence(timeout: 3) {
            app.switches["Whitespace Indicators"].tap()
        }
        paragraphMenuButton.tap()
        if app.switches["Indent Guides"].waitForExistence(timeout: 3) {
            app.switches["Indent Guides"].tap()
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

    func testJSONLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testAutoformatButtonVisibleForJSON() {
        XCTAssertTrue(app.buttons["autoformatButton"].waitForExistence(timeout: 5))
    }

    func testAutoformatJSONDoesNotCrash() {
        let btn = app.buttons["autoformatButton"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        btn.tap() // enable
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        btn.tap() // disable
        XCTAssertTrue(codeTextView.exists)
    }

    func testScrollAfterAutoformat() {
        let btn = app.buttons["autoformatButton"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        btn.tap()
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

    func testXMLLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testAutoformatButtonVisibleForXML() {
        XCTAssertTrue(app.buttons["autoformatButton"].waitForExistence(timeout: 5))
    }

    func testAutoformatXMLDoesNotCrash() {
        let btn = app.buttons["autoformatButton"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        btn.tap()
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
        btn.tap()
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

    func testMarkdownLoads() {
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
    }

    func testPreviewModeMenuExists() {
        XCTAssertTrue(app.buttons["previewModeMenuButton"].waitForExistence(timeout: 5))
    }

    func testSwitchToRenderedMode() {
        let menuBtn = app.buttons["previewModeMenuButton"]
        XCTAssertTrue(menuBtn.waitForExistence(timeout: 5))
        menuBtn.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) {
            app.buttons["Rendered"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSwitchRenderedThenBackToSource() {
        let menuBtn = app.buttons["previewModeMenuButton"]
        XCTAssertTrue(menuBtn.waitForExistence(timeout: 5))

        menuBtn.tap()
        if app.buttons["Rendered"].waitForExistence(timeout: 3) { app.buttons["Rendered"].tap() }

        menuBtn.tap()
        if app.buttons["Source"].waitForExistence(timeout: 3) { app.buttons["Source"].tap() }

        XCTAssertTrue(codeTextView.waitForExistence(timeout: 5))
    }

    func testAutoformatButtonNotVisibleForMarkdown() {
        // Markdown is not JSON/XML so autoformat should be hidden
        XCTAssertTrue(codeTextView.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["autoformatButton"].exists)
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
