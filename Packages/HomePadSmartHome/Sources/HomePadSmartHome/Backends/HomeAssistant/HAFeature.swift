import Foundation
import HomePadCore

/// Home Assistant `supported_features` bits that change which controls appear.
enum HAFeature {
    static let fanSetSpeed = 1
    static let coverSetPosition = 4
    static let coverSetTiltPosition = 128
    static let cameraStream = 2
    static let mediaVolumeSet = 4
    static let lockOpen = 1
}
