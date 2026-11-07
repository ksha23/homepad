import XCTest

/// Paging the Home Screen back and forth. On a device the scroll signposts give
/// the hitch time ratio. The simulator has no hitch metrics, so there the test
/// measures the CPU the app spends per swipe instead.
final class HomeScreenScrollPerfTests: XCTestCase {
    /// Demo content in the simulator.
    func testPagingCPU() {
        let app = launch(["-HomePadDemoContent", "YES", "-HomePadMember", "Alex", "-HomePadRecognized", "YES"])
        measure(metrics: [XCTCPUMetric(application: app), XCTClockMetric()], options: Self.options) {
            swipeBackAndForth(app)
        }
    }

    /// The device's own household and layout, so no demo arguments.
    func testPagingHitchesOnDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Hitch metrics need a device")
        #else
        let app = launch([])
        let metrics: [XCTMetric] = [
            XCTOSSignpostMetric.scrollDraggingMetric, XCTOSSignpostMetric.scrollDecelerationMetric,
            XCTCPUMetric(application: app),
        ]
        measure(metrics: metrics, options: Self.options) {
            swipeBackAndForth(app)
        }
        #endif
    }

    private static var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadHomePage", "0", "-HomePadCondition", "active"] + arguments
        app.launch()
        // The header's People button is on every page.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People'")).firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        return app
    }

    private func swipeBackAndForth(_ app: XCUIApplication) {
        for _ in 0..<3 {
            app.swipeLeft(velocity: .fast)
            app.swipeRight(velocity: .fast)
        }
    }
}
