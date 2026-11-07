import HomePadCore

/// How many grid cells something covers.
struct GridSpan: Equatable, Sendable {
    var columns: Int
    var rows: Int

    static let one = GridSpan(columns: 1, rows: 1)

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// Widget sizes: small 1x1, medium 2x1, large 2x2, tall 2x3. A page
    /// with fewer rows than a widget clamps it (`GridPacker`).
    init(_ size: WidgetSize) {
        self.init(columns: size.columns, rows: size.rows)
    }
}
