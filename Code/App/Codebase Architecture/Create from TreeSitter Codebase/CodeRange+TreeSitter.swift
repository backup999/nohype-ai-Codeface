import SwiftTreeSitter

extension CodeRange {
    /// Map Tree-sitter point range (0-based row/column; end typically exclusive).
    init(_ points: Range<Point>) {
        self.init(
            start: CodePosition(
                line: Int(points.lowerBound.row),
                character: Int(points.lowerBound.column)
            ),
            end: CodePosition(
                line: Int(points.upperBound.row),
                character: Int(points.upperBound.column)
            )
        )
    }
}
