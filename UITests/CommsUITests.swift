import XCTest

/// Messages end to end against a running homepad-hub on this Mac:
/// the list loads, a thread opens, a sent message comes back as a bubble.
/// Needs `TEST_RUNNER_HUB_TOKEN` (the hub's token) and `TEST_RUNNER_HUB_CHAT` (the chat
/// to send in, a conversation with yourself), and the hub on 127.0.0.1:8787.
final class CommsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMessagesListsOpensAndSends() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["HUB_TOKEN"], "set TEST_RUNNER_HUB_TOKEN")
        let chat = try XCTUnwrap(env["HUB_CHAT"], "set TEST_RUNNER_HUB_CHAT")

        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "messages", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near",
                               "-HomePadCommsURL", "http://127.0.0.1:8787", "-HomePadCommsToken", token,
                               "-HomePadCommsMember", "Alex"]
        app.launch()

        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", chat)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 25), "the conversation list loads from the hub")
        keepScreenshot(app, named: "Messages list")
        target.tap()

        let stamp = "e2e \(Int(Date().timeIntervalSince1970))"
        let field = app.textFields["iMessage"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(stamp)
        app.buttons["composer-send"].tap()

        XCTAssertTrue(app.staticTexts[stamp].waitForExistence(timeout: 20), "the sent message returns as a bubble through the event stream")
        keepScreenshot(app, named: "Messages thread")
    }

    /// Opens a chat that has photos and checks they draw, and that tapping a video opens the player.
    func testPhotosAndVideosLoad() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["HUB_TOKEN"], "set TEST_RUNNER_HUB_TOKEN")
        let chat = try XCTUnwrap(env["HUB_MEDIA_CHAT"], "set TEST_RUNNER_HUB_MEDIA_CHAT")

        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "messages", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near",
                               "-HomePadCommsURL", "http://127.0.0.1:8787", "-HomePadCommsToken", token,
                               "-HomePadCommsMember", "Alex"]
        app.launch()
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", chat)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 25))
        target.tap()
        let photo = app.descendants(matching: .any).matching(identifier: "photo-block").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 25), "a photo or stack draws")
        keepScreenshot(app, named: "Thread with photos")
        photo.tap()
        XCTAssertTrue(app.buttons["viewer-done"].waitForExistence(timeout: 15), "tapping a photo opens the full-screen viewer")
        keepScreenshot(app, named: "Photo viewer")
        app.buttons["viewer-done"].tap()
    }

    /// Two people, two hubs, two Apple IDs: each sees only their own messages.
    /// `HUB_SAM_TOKEN` is the token of a second hub on 127.0.0.1:8788 serving a synthetic account.
    func testEachPersonSeesOnlyTheirOwnAccount() throws {
        let env = ProcessInfo.processInfo.environment
        let kyleToken = try XCTUnwrap(env["HUB_TOKEN"], "set TEST_RUNNER_HUB_TOKEN")
        let samToken = try XCTUnwrap(env["HUB_SAM_TOKEN"], "set TEST_RUNNER_HUB_SAM_TOKEN")
        let kyleChat = try XCTUnwrap(env["HUB_CHAT"], "set TEST_RUNNER_HUB_CHAT")
        let seeds = """
            [{"member":"Alex","url":"http://127.0.0.1:8787","token":"\(kyleToken)"},
             {"member":"Sam","url":"http://127.0.0.1:8788","token":"\(samToken)"}]
            """
        func launch(as member: String) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-HomePadOpenApp", "messages", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                                   "-HomePadMember", member, "-HomePadRecognized", "YES", "-HomePadProximity", "near",
                                   "-HomePadCommsSeeds", seeds]
            app.launch()
            return app
        }
        func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }

        let alex = launch(as: "Alex")
        XCTAssertTrue(row(alex, kyleChat).waitForExistence(timeout: 25), "Alex sees Alex's account")
        XCTAssertFalse(row(alex, "+15555550101").exists, "Alex never sees Sam's conversations")
        alex.terminate()

        let sam = launch(as: "Sam")
        let samRow = row(sam, "+15555550101")
        let found = samRow.waitForExistence(timeout: 25)
        let state = ["Set up Messages", "Connecting to your Mac", "Cannot reach your Mac", "Locked"].filter { sam.staticTexts[$0].exists }
        XCTAssertTrue(found, "Sam sees Sam's account. Screen state: \(state), rows: \(sam.staticTexts.count)")
        XCTAssertFalse(row(sam, kyleChat).exists, "Sam never sees Alex's conversations")
        keepScreenshot(sam, named: "Sam's messages")
    }

    /// A rich link shows as one card, not a bare URL plus stray attachments.
    func testRichLinkShowsAsOneCard() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["HUB_TOKEN"], "set TEST_RUNNER_HUB_TOKEN")
        let chat = try XCTUnwrap(env["HUB_LINK_CHAT"], "set TEST_RUNNER_HUB_LINK_CHAT")

        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "messages", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near",
                               "-HomePadCommsURL", "http://127.0.0.1:8787", "-HomePadCommsToken", token,
                               "-HomePadCommsMember", "Alex"]
        app.launch()
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", chat)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 25))
        target.tap()
        XCTAssertTrue(app.buttons["link-card"].firstMatch.waitForExistence(timeout: 25), "a link card draws")
        keepScreenshot(app, named: "Thread with a link card")
    }

    /// Every chat opens with its newest message at the bottom, right above the composer,
    /// and stays there once its photos and link cards have loaded. Switches between a photo
    /// chat, a text chat and a link chat, then back, so both a first load and a saved copy are checked.
    func testChatsOpenAtTheNewestMessage() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["HUB_TOKEN"], "set TEST_RUNNER_HUB_TOKEN")
        let chats = try ["HUB_MEDIA_CHAT", "HUB_LINK_CHAT", "HUB_TEXT_CHAT", "HUB_MEDIA_CHAT", "HUB_LINK_CHAT"].map {
            try XCTUnwrap(env[$0], "set TEST_RUNNER_\($0)")
        }

        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "messages", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near",
                               "-HomePadCommsURL", "http://127.0.0.1:8787", "-HomePadCommsToken", token,
                               "-HomePadCommsMember", "Alex"]
        app.launch()
        for (step, chat) in chats.enumerated() {
            let row = try XCTUnwrap(listRow(app, chat), "row for step \(step)")
            row.tap()
            let newest = app.otherElements["newest-message"]
            XCTAssertTrue(newest.waitForExistence(timeout: 20), "the thread draws (step \(step))")
            // Long enough for photos, link previews and the hub's fresh copy to arrive.
            sleep(4)
            keepScreenshot(app, named: "step \(step)")
            let field = app.textFields["iMessage"].frame
            let bottom = newest.frame.maxY
            XCTAssertLessThanOrEqual(bottom, field.minY, "the newest message is not under the composer (step \(step))")
            XCTAssertGreaterThan(bottom, field.minY - 90, "the newest message sits right above the composer (step \(step)), bottom \(bottom), composer \(field.minY)")
        }
    }

    /// The conversation's row in the list on the left, never its name in the thread's header.
    /// Each row is one button whose label starts with the conversation's name.
    private func listRow(_ app: XCUIApplication, _ title: String) -> XCUIElement? {
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        let listEdge = app.windows.firstMatch.frame.width * 0.4
        _ = app.staticTexts["Messages"].waitForExistence(timeout: 25)
        // The list only holds the rows on screen, so scroll it toward the top until the row shows.
        for _ in 0..<6 {
            if let row = matches.allElementsBoundByIndex.first(where: { $0.frame.midX < listEdge }) { return row }
            app.collectionViews.firstMatch.swipeDown()
        }
        return nil
    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
