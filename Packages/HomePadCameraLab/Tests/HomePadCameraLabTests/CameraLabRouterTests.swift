import HomePadCore
import Testing
@testable import HomePadCameraLab

/// Camera Lab reopens on its last tool, but never straight into the camera.
@MainActor
@Suite struct CameraLabRouterTests {
    @Test func closingOnACameraToolGoesBackToTheHub() {
        let router = CameraLabRouter()
        for tool in CameraLabTool.allCases where tool.showsCameraOnOpen {
            router.open(tool)
            router.leave()
            #expect(router.path.isEmpty, "\(tool) should not reopen with the camera on")
        }
    }

    @Test func toolsWithoutTheCameraReopen() {
        let router = CameraLabRouter()
        router.open(.floorPlan)
        router.leave()
        #expect(router.path == [.floorPlan])
    }

    @Test func aRelaunchRestoresOnlyToolsWithoutTheCamera() {
        let restored = CameraLabRouter()
        restored.restore(.documents)
        #expect(restored.path == [.documents])
        let hub = CameraLabRouter()
        hub.restore(.ask)
        #expect(hub.path.isEmpty)
    }

    /// The assistant asked for the grocery scanner while the app was closed.
    @Test func aRequestedToolWinsOverTheSavedOne() {
        let router = CameraLabRouter()
        router.open(.groceries)
        router.restore(.floorPlan)
        #expect(router.path == [.groceries])
    }

    @Test func onlyTheDocumentScannerAndFloorPlanStayCameraFree() {
        #expect(CameraLabTool.allCases.filter { !$0.showsCameraOnOpen } == [.documents, .floorPlan])
        #expect(CameraLabAppState.tool.scope == .household)
    }
}
