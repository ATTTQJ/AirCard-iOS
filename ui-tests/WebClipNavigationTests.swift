import XCTest

final class WebClipNavigationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testChineseEntriesPreviewAndHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-aircard.language", "zh-Hans", "-aircard.dont_show_support_on_launch", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["钱包"].exists)
        XCTAssertTrue(app.tabBars.buttons["密码主题"].exists)
        XCTAssertTrue(app.tabBars.buttons["壁纸"].exists)
        let icons = app.tabBars.buttons["图标主题"]
        XCTAssertTrue(icons.exists, "WebClip must be a visible tab, not hidden in More")
        capture(app, "01-Chinese-home")
        icons.tap()
        XCTAssertTrue(app.buttons["webclip.install"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["webclip.install"].isEnabled, "Writing must be blocked without prerequisites")
        capture(app, "02-WebClip-preview")
        let bundleField = app.textFields["webclip.bundleID"]
        for _ in 0..<6 {
            if bundleField.exists && bundleField.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(bundleField.exists && bundleField.isHittable, "App identifier must be reachable by scrolling")
        capture(app, "03-WebClip-target-and-readiness")
        let verify = app.buttons["webclip.verifyDirectory"]
        for _ in 0..<6 {
            if verify.exists && verify.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(verify.exists && verify.isHittable)
        XCTAssertFalse(verify.isEnabled, "Directory writes must also require a supported paired device")
        capture(app, "04-Directory-diagnostics")
        app.buttons["webclip.history"].tap()
        XCTAssertTrue(app.staticTexts["暂无写入记录"].waitForExistence(timeout: 5))
        capture(app, "04-WebClip-history")
        app.buttons["完成"].tap()
        app.tabBars.buttons["首页"].tap()
        let entry = app.buttons["home.webclip"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["webclip.install"].exists, "Home entry must open the same WebClip screen")
    }

    func testEnglishSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-aircard.language", "en", "-aircard.dont_show_support_on_launch", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Pairing"].waitForExistence(timeout: 15))
        let icons = app.tabBars.buttons["App Icons"]
        XCTAssertTrue(icons.exists)
        icons.tap()
        XCTAssertTrue(app.buttons["webclip.install"].exists)
        capture(app, "05-English-WebClip")
    }

    func testFullReportCanBeCopiedWithoutVPN() throws {
        let app = XCUIApplication()
        // NSArgumentDomain parses unquoted multiline launch values at the first
        // newline. A whitespace-free long fixture exercises the actual full-text
        // view without silently truncating the test input before app launch.
        let report = "目录验证测试：" + String(repeating: "完整日志内容", count: 80) + "REPORT-END-MARKER"
        app.launchArguments = ["-aircard.language", "zh-Hans", "-aircard.dont_show_support_on_launch", "YES", "-webclip.directoryReport", report]
        app.launch()
        app.tabBars.buttons["图标主题"].tap()
        let open = app.buttons["webclip.openReport"]
        for _ in 0..<10 {
            if open.exists && open.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(open.exists && open.isHittable)
        open.tap()
        XCTAssertTrue(app.buttons["webclip.copyReport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["webclip.fullReport"].label.hasSuffix("REPORT-END-MARKER"), "Report must not be truncated to the preview")
        app.buttons["webclip.copyReport"].tap()
        XCTAssertTrue(app.staticTexts["完整报告已复制，可以返回聊天粘贴。"].exists)
        XCTAssertTrue(app.buttons["webclip.saveReport"].isEnabled)
        capture(app, "06-Full-report-copy-and-save")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
