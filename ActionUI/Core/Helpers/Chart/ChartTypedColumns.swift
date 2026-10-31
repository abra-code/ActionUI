// Core/Helpers/Chart/ChartTypedColumns.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// Rows parsed once per (column, type) pair. A nil cell is missing or did not parse. The raw rows
// are kept for text with "$N" references.
struct ChartTypedColumns {
    let rows: [[String]]
    private let cells: [ChartColumnRef: [ChartScalar?]]

    var rowCount: Int { rows.count }

    init(rows: [[String]], refs: [ChartColumnRef]) {
        self.rows = rows
        var cells: [ChartColumnRef: [ChartScalar?]] = [:]
        for ref in refs {
            cells[ref] = rows.map { row in
                guard ref.index < row.count else { return nil }
                return Self.parse(row[ref.index], as: ref.type)
            }
        }
        self.cells = cells
    }

    static func parse(_ cell: String, as type: ChartColumnType) -> ChartScalar? {
        switch type {
        case .string:
            return .string(cell)
        case .number:
            return Double(PlainText.trimmedSpaces(cell)).map { .number($0) }
        case .integer:
            return Int(PlainText.trimmedSpaces(cell)).map { .integer($0) }
        case .date:
            return DateHelper.parseDate(from: cell).map { .date($0) }
        }
    }

    func scalar(row: Int, ref: ChartColumnRef) -> ChartScalar? {
        cells[ref]?[row] ?? nil
    }
}
