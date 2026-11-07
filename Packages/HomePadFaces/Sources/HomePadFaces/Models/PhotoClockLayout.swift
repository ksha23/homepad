import CoreGraphics
import HomePadUI
import SwiftUI

/// Where the Photos face draws its time from across the room and up close.
///
/// From across the room the time is the one big fact: as wide and as tall
/// as the face's insets allow, centered in their height while no widgets
/// take the bottom (the depth style), or a large white clock at the top like
/// the Lock Screen's (the classic style). The insets keep it above the face's
/// widgets, so it stays clear of them at every distance. Up close it glances
/// smaller and the date fades in beside it. The time is laid out once at its
/// far size and shrunk by `nearScale` (`distanceFrame`), so walking up moves
/// it in one glide.
///
/// The depth effect measures the numerals where they are drawn at the
/// distance shown (`digits(isNear:)`), so the face on the wall, its
/// thumbnails and the editor decide alike.
struct PhotoClockLayout: Equatable {
    /// The face's size.
    let viewSize: CGSize
    /// The time's font size. The same at both distances.
    let fontSize: CGFloat
    /// The time's line of text from across the room, in points.
    let farLine: CGRect
    /// The same line up close: `farLine` shrunk by `nearScale`.
    let nearLine: CGRect
    /// The date's line up close: above the time for the depth style, under it for the classic one.
    let date: CGRect
    /// The date's font size.
    let dateSize: CGFloat
    /// Where the digits sit in a line of text at a font size of 1.
    private let metrics: ClockFontMetrics

    /// How far the depth time shrinks up close. Far it is close to twice the size.
    static let depthNearScale: CGFloat = 0.56
    /// The classic time's font size from across the room, as a share of the short side.
    static let classicFarShare: CGFloat = 0.36
    /// Where the classic clock's line starts, as a share of the height.
    static let classicTop: CGFloat = 0.06
    /// The classic clock's height up close for a font size of 1: the time's
    /// line (about 1.2) and the date's under it (about 0.25).
    static let classicHeight: CGFloat = 1.45

    /// The scale of the time up close, from 0 to 1.
    var nearScale: CGFloat {
        farLine.width > 0 ? nearLine.width / farLine.width : 1
    }

    /// The time's line at a distance, in points.
    func line(isNear: Bool) -> CGRect {
        isNear ? nearLine : farLine
    }

    /// Where the numerals are drawn at a distance, normalized to the face (0...1).
    func digits(isNear: Bool) -> CGRect {
        let line = line(isNear: isNear)
        let size = fontSize * (isNear ? nearScale : 1)
        let rect = CGRect(x: line.midX - metrics.width * size / 2, y: line.minY + metrics.digitTop * size,
                          width: metrics.width * size, height: metrics.digitHeight * size)
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGRect(x: rect.minX / viewSize.width, y: rect.minY / viewSize.height,
                      width: rect.width / viewSize.width, height: rect.height / viewSize.height)
    }

    // MARK: Depth

    /// The depth style: tall compressed numerals across the photo. Far, the
    /// numerals span the insets' width (or their height, on a wide face).
    /// Near, they shrink by `depthNearScale` under the date.
    ///
    /// Centered, as on HomeView, the numerals sit in the middle of the
    /// height the insets leave from across the room, and the date and the
    /// numerals together up close. Otherwise they start at the top inset, as
    /// they do above widgets along the bottom.
    /// - Parameters:
    ///   - insets: The face insets, which include the burn-in overscan and the
    ///     room the widgets and the Now Playing pill take (`\.faceKeepClear`).
    ///   - isCentered: Centers the time in the height the insets leave.
    static func depth(viewSize: CGSize, insets: EdgeInsets, metrics: ClockFontMetrics,
                      isCentered: Bool = false) -> PhotoClockLayout {
        let content = Self.content(viewSize, insets)
        let size = max(min(content.width / metrics.width, content.height / metrics.digitHeight), 0)
        let digitHeight = metrics.digitHeight * size
        let farDigitTop = isCentered ? content.midY - digitHeight / 2 : content.minY
        let farLine = CGRect(x: content.minX, y: farDigitTop - metrics.digitTop * size,
                             width: content.width, height: metrics.lineHeight * size)
        let dateSize = Self.dateSize(viewSize)
        let dateHeight = dateSize * 1.25
        // Up close the numerals come under the date and end above the widgets.
        let fits = (content.height - dateHeight - Theme.Spacing.s) / max(digitHeight, 1)
        let scale = max(min(depthNearScale, fits), 0.1)
        let group = dateHeight + Theme.Spacing.s + digitHeight * scale
        let date = CGRect(x: content.minX, y: isCentered ? content.midY - group / 2 : content.minY,
                          width: content.width, height: dateHeight)
        let top = date.maxY + Theme.Spacing.s
        let nearLine = CGRect(x: content.midX - content.width * scale / 2, y: top - metrics.digitTop * size * scale,
                              width: content.width * scale, height: farLine.height * scale)
        return PhotoClockLayout(viewSize: viewSize, fontSize: size, farLine: farLine, nearLine: nearLine,
                                date: date, dateSize: dateSize, metrics: metrics)
    }

    /// The date over the depth time up close: about 36 points on an 11-inch iPad.
    static func dateSize(_ viewSize: CGSize) -> CGFloat {
        min(max(min(viewSize.width, viewSize.height) * 0.042, 22), 44)
    }

    // MARK: Classic

    /// The classic style: a white clock at the top. Far, its font is
    /// `classicFarShare` of the short side, as wide and as tall as the insets
    /// allow. Near, it shrinks to `classicNearSize` with the date under it.
    static func classic(viewSize: CGSize, insets: EdgeInsets, metrics: ClockFontMetrics) -> PhotoClockLayout {
        let content = Self.content(viewSize, insets)
        let top = viewSize.height * classicTop
        let shortSide = min(viewSize.width, viewSize.height)
        let bottom = content.maxY
        let far = max(min(shortSide * classicFarShare, content.width / metrics.width,
                          (bottom - top) / metrics.lineHeight), 0)
        let near = min(classicNearSize(viewSize: viewSize, bottom: bottom), far)
        let scale = far > 0 ? near / far : 1
        let farLine = CGRect(x: content.minX, y: top, width: content.width, height: metrics.lineHeight * far)
        let nearLine = CGRect(x: content.midX - content.width * scale / 2, y: top,
                              width: content.width * scale, height: farLine.height * scale)
        let dateSize = near * 0.2
        let date = CGRect(x: content.minX, y: nearLine.maxY + Theme.Spacing.xs, width: content.width, height: dateSize * 1.25)
        return PhotoClockLayout(viewSize: viewSize, fontSize: far, farLine: farLine, nearLine: nearLine,
                                date: date, dateSize: dateSize, metrics: metrics)
    }

    /// The classic time's font size up close: 17 percent of the short side,
    /// smaller only when the time and the date under it would reach below
    /// `bottom`, in points (the face's whole height by default).
    static func classicNearSize(viewSize: CGSize, bottom: CGFloat? = nil) -> CGFloat {
        let natural = min(viewSize.width, viewSize.height) * 0.17
        let room = (bottom ?? viewSize.height) - classicTop * viewSize.height - Theme.Spacing.xs
        return max(min(natural, room / classicHeight), 0)
    }

    private static func content(_ size: CGSize, _ insets: EdgeInsets) -> CGRect {
        CGRect(x: insets.leading, y: insets.top,
               width: max(size.width - insets.leading - insets.trailing, 0),
               height: max(size.height - insets.top - insets.bottom, 0))
    }
}
