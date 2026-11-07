import CoreGraphics
import Foundation
import simd

/// A camera's pinhole model: focal lengths and principal point in pixels of
/// an image `width` by `height` pixels.
struct PinholeIntrinsics: Equatable, Sendable {
    var focalX: Double
    var focalY: Double
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double

    /// From a 3 by 3 intrinsic matrix (ARKit and AVFoundation layout: the
    /// principal point is in the third column) for an image of `size`.
    init(matrix: simd_float3x3, size: CGSize) {
        focalX = Double(matrix.columns.0.x)
        focalY = Double(matrix.columns.1.y)
        centerX = Double(matrix.columns.2.x)
        centerY = Double(matrix.columns.2.y)
        width = Double(size.width)
        height = Double(size.height)
    }

    init(focalX: Double, focalY: Double, centerX: Double, centerY: Double, width: Double, height: Double) {
        self.focalX = focalX
        self.focalY = focalY
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
    }
}

/// Where a point of the camera image lies in the depth map of the same frame.
///
/// TrueDepth depth is registered to the color camera, so both see the scene
/// from the same point. They may still cover different parts of the view:
/// ARKit's face tracking image is 16:9 while its depth map can be 4:3, and
/// then the image is a band across the middle of the depth map. Reading the
/// depth map at the image's normalized coordinates put a face near the edge
/// of the image on the wrong part of the depth map.
///
/// The mapping is a scale and an offset per axis, in normalized coordinates
/// with a top-left origin, in the native (unrotated) buffers.
struct DepthRegistration: Equatable, Sendable {
    var scaleX = 1.0
    var offsetX = 0.0
    var scaleY = 1.0
    var offsetY = 0.0

    static let identity = DepthRegistration()

    init(scaleX: Double = 1, offsetX: Double = 0, scaleY: Double = 1, offsetY: Double = 0) {
        self.scaleX = scaleX
        self.offsetX = offsetX
        self.scaleY = scaleY
        self.offsetY = offsetY
    }

    /// Without calibration: the narrower of the two is taken as the centered
    /// crop of the other. A 1280x720 image over a 640x480 depth map covers its
    /// full width and the middle three quarters of its height.
    init(imageSize: CGSize, depthSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0, depthSize.width > 0, depthSize.height > 0 else {
            self = .identity
            return
        }
        let imageAspect = Double(imageSize.width / imageSize.height)
        let depthAspect = Double(depthSize.width / depthSize.height)
        if imageAspect >= depthAspect {
            scaleY = depthAspect / imageAspect
            offsetY = (1 - scaleY) / 2
        } else {
            scaleX = imageAspect / depthAspect
            offsetX = (1 - scaleX) / 2
        }
    }

    /// From both pinhole models. A pixel's ray through the image is followed
    /// to the depth map's pixel on the same ray.
    init(image: PinholeIntrinsics, depth: PinholeIntrinsics) {
        scaleX = depth.focalX * image.width / (image.focalX * depth.width)
        offsetX = (depth.centerX - depth.focalX * image.centerX / image.focalX) / depth.width
        scaleY = depth.focalY * image.height / (image.focalY * depth.height)
        offsetY = (depth.centerY - depth.focalY * image.centerY / image.focalY) / depth.height
    }

    /// A normalized image point (top-left origin) in the depth map.
    func depthPoint(fromImage point: CGPoint) -> CGPoint {
        CGPoint(x: offsetX + scaleX * point.x, y: offsetY + scaleY * point.y)
    }

    /// A normalized image rect with a bottom-left origin (Vision and Core
    /// Image) as a rect in the depth map, also with a bottom-left origin.
    func depthRect(fromImageBottomLeft rect: CGRect) -> CGRect {
        let bottomLeftOffsetY = 1 - offsetY - scaleY
        return CGRect(
            x: offsetX + scaleX * rect.minX, y: bottomLeftOffsetY + scaleY * rect.minY,
            width: scaleX * rect.width, height: scaleY * rect.height
        )
    }

    /// For the presence trace: "x 1.00+0.00 y 0.75+0.13".
    var summary: String {
        String(format: "x %.2f%+.2f y %.2f%+.2f", scaleX, offsetX, scaleY, offsetY)
    }
}
