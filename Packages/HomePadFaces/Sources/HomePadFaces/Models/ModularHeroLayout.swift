import CoreGraphics

/// Where the top of the Modular face goes in a rect: the date and the clock.
/// `ModularLayout` lays it out twice, across the whole face from across the
/// room and in the info panel's top half up close. Each part is drawn at its
/// far size and shrunk into its near frame (`distanceFrame`), so walking up
/// moves both parts in one glide.
struct ModularHeroLayout: Equatable {
    /// Analog: the weekday and month over the day number. Digital: the date line.
    let date: CGRect
    /// Analog: the dial. Digital: the time's line.
    let clock: CGRect
    /// The date line's font size.
    let line: CGFloat
    /// Analog: the day number's font size. Digital: the time's.
    let numeral: CGFloat

    /// The analog top: the date beside the dial, like HomeView's info face,
    /// or above it when `stacked` (a tall or square panel seen from across
    /// the room, where side by side the dial could be no wider than half).
    static func analog(in rect: CGRect, gap: CGFloat, stacked: Bool = false) -> ModularHeroLayout {
        if stacked {
            let dial = max(min(rect.width, (rect.height - gap) * 0.58), 0)
            let block = max(min(rect.height - dial - gap, dial * 0.75), 0)
            let line = min(block * 0.18, rect.width * 0.09)
            let numeral = max(min((block - line * 1.2) / 1.2, rect.width / 1.3), 0)
            let top = rect.minY + max((rect.height - block - gap - dial) / 2, 0)
            let width = dateWidth(line: line, numeral: numeral, room: rect.width)
            return ModularHeroLayout(
                date: CGRect(x: rect.midX - width / 2, y: top + (block - (line + numeral) * 1.2) / 2,
                             width: width, height: (line + numeral) * 1.2),
                clock: CGRect(x: rect.midX - dial / 2, y: top + block + gap, width: dial, height: dial),
                line: line, numeral: numeral
            )
        }
        let cell = CGSize(width: max((rect.width - gap) / 2, 0), height: rect.height)
        let dial = min(cell.width, cell.height)
        let line = min(cell.height * 0.15, cell.width * 0.17)
        let numeral = max(min((cell.height - line * 1.2) / 1.2, cell.width / 1.3, dial * 0.8), 0)
        let height = (line + numeral) * 1.2
        return ModularHeroLayout(
            date: CGRect(x: rect.minX, y: rect.midY - height / 2,
                         width: dateWidth(line: line, numeral: numeral, room: cell.width), height: height),
            clock: CGRect(x: rect.minX + cell.width + gap + (cell.width - dial) / 2, y: rect.midY - dial / 2,
                          width: dial, height: dial),
            line: line, numeral: numeral
        )
    }

    /// The digital top: a date line over a big time, like the Lock Screen,
    /// from the leading edge and centered top to bottom.
    static func digital(in rect: CGRect) -> ModularHeroLayout {
        let line = max(min(rect.height * 0.12, rect.width * 0.06), 0)
        let time = max(min((rect.height - line * 1.3) / 1.2, rect.width / 2.9), 0)
        let top = rect.minY + max((rect.height - line * 1.3 - time * 1.2) / 2, 0)
        return ModularHeroLayout(
            date: CGRect(x: rect.minX, y: top, width: rect.width, height: line * 1.3),
            clock: CGRect(x: rect.minX, y: top + line * 1.3, width: rect.width, height: time * 1.2),
            line: line, numeral: time
        )
    }

    /// The analog date's width: its day number or its "Tue Oct" line,
    /// whichever is wider, within the room there is. A box as wide as the
    /// room would shrink the date too far when it moves into a narrow one.
    private static func dateWidth(line: CGFloat, numeral: CGFloat, room: CGFloat) -> CGFloat {
        max(min(room, max(numeral * 1.3, line * 4.2)), 0)
    }
}
