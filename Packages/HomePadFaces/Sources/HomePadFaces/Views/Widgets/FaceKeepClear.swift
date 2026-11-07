import CoreGraphics
import SwiftUI

extension CGSize {
    /// The part of a face of this size its own content has, clear of its
    /// widgets and the Now Playing pill (`\.faceKeepClear`). It starts
    /// `room.top` down and `room.leading` in. The whole face when nothing is there.
    func leaving(_ room: EdgeInsets) -> CGSize {
        CGSize(width: max(width - room.leading - room.trailing, 0), height: max(height - room.top - room.bottom, 0))
    }
}

extension EdgeInsets {
    /// These insets moved clear of `zone`, a top corner of the face (the
    /// profile button's, `\.faceProfileZone`), when the content inside them reaches it: the
    /// top comes down below it, or the side it is on moves in beside it,
    /// whichever leaves the content more room. Unchanged when the content
    /// stays clear.
    func clearing(_ zone: CGRect, in size: CGSize) -> EdgeInsets {
        let content = CGRect(x: leading, y: top, width: max(size.width - leading - trailing, 0),
                             height: max(size.height - top - bottom, 0))
        guard !zone.isNull, content.intersects(zone) else { return self }
        var below = self
        below.top = max(top, zone.maxY)
        var beside = self
        if zone.midX < size.width / 2 {
            beside.leading = max(leading, zone.maxX)
        } else {
            beside.trailing = max(trailing, size.width - zone.minX)
        }
        func area(_ insets: EdgeInsets) -> CGFloat {
            size.leaving(insets).width * size.leaving(insets).height
        }
        return area(below) >= area(beside) ? below : beside
    }

    /// The larger of the top and bottom room at both, so content centered in
    /// what is left stays centered on the face. A dial then shrinks a little
    /// for the Now Playing pill instead of moving down, and never reaches
    /// cells it did not cover before.
    var balancedVertically: EdgeInsets {
        let room = max(top, bottom)
        return EdgeInsets(top: room, leading: leading, bottom: room, trailing: trailing)
    }
}

extension View {
    /// Centers the view in the part of a face of `size` clear of `room`
    /// (`\.faceKeepClear`), such as a dial that otherwise centers on the whole face.
    func centered(in size: CGSize, clearOf room: EdgeInsets) -> some View {
        let area = size.leaving(room)
        return position(x: room.leading + area.width / 2, y: room.top + area.height / 2)
    }
}
