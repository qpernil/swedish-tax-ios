import Foundation

enum TaxRowKind: Sendable {
    case amount
    case percent
}

struct TaxRow: Equatable, Sendable {
    let minimum: UInt32
    let maximum: UInt32
    let values: [UInt32]
    let kind: TaxRowKind
}

enum TaxTableSourceError: Error, CustomStringConvertible {
    case resourceMissing
    case invalidRecordCount(actual: Int)
    case invalidRecord(line: Int, reason: String)
    case invalidCoverage(table: UInt8, reason: String)

    var description: String {
        switch self {
        case .resourceMissing:
            "The embedded official tax-table resource is missing."
        case let .invalidRecordCount(actual):
            "Tax table source has \(actual) records; expected \(TaxTables.recordCount)."
        case let .invalidRecord(line, reason):
            "Tax table source line \(line): \(reason)."
        case let .invalidCoverage(table, reason):
            "Tax table \(table) \(reason)."
        }
    }
}

enum TaxTables {
    static let recordCount = 7_966
    private static let recordLength = 49
    private static let resourceName = "allmanna-tabeller-manad-2026"

    private static let loadResult: Result<[UInt8: [TaxRow]], Error> = Result {
        try loadAndValidate()
    }

    static func all() throws -> [UInt8: [TaxRow]] {
        try loadResult.get()
    }

    static func rows(for table: UInt8) -> [TaxRow]? {
        try? loadResult.get()[table]
    }

    static func sourceData() throws -> Data {
        guard let url = resourceURL() else {
            throw TaxTableSourceError.resourceMissing
        }
        return try Data(contentsOf: url)
    }

    private static func loadAndValidate() throws -> [UInt8: [TaxRow]] {
        let data = try sourceData()
        let source = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        var lines = source.split(separator: 0x0A, omittingEmptySubsequences: true)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.count == recordCount else {
            throw TaxTableSourceError.invalidRecordCount(actual: lines.count)
        }

        var tables = Dictionary(
            uniqueKeysWithValues: (TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable)
                .map { ($0, [TaxRow]()) }
        )

        for (zeroBasedLine, rawLine) in lines.enumerated() {
            let lineNumber = zeroBasedLine + 1
            let line = rawLine.last == 0x0D ? rawLine.dropLast() : rawLine[...]
            guard line.count == recordLength else {
                throw sourceError(lineNumber, "expected \(recordLength) characters")
            }
            let bytes = Array(line)
            guard bytes[0] == 0x33, bytes[1] == 0x30 else {
                throw sourceError(lineNumber, "unsupported record type")
            }

            let kind: TaxRowKind
            switch bytes[2] {
            case 0x42: kind = .amount
            case 0x25: kind = .percent
            default:
                throw sourceError(lineNumber, "unsupported row kind")
            }

            let table = UInt8(try parse(bytes[3..<5], line: lineNumber, name: "table"))
            guard tables[table] != nil else {
                throw sourceError(lineNumber, "table \(table) is outside the supported range")
            }

            let minimum = try parse(bytes[5..<12], line: lineNumber, name: "minimum")
            let maximumBytes = bytes[12..<19]
            let maximum = maximumBytes.allSatisfy { $0 == 0x20 }
                ? UInt32.max
                : try parse(maximumBytes, line: lineNumber, name: "maximum")
            var values = [UInt32]()
            values.reserveCapacity(6)
            for index in 0..<6 {
                let start = 19 + index * 5
                values.append(
                    try parse(bytes[start..<(start + 5)], line: lineNumber, name: "column value")
                )
            }

            tables[table, default: []].append(
                TaxRow(minimum: minimum, maximum: maximum, values: values, kind: kind)
            )
        }

        for table in TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable {
            guard let rows = tables[table], rows.first?.minimum == 1 else {
                throw TaxTableSourceError.invalidCoverage(
                    table: table,
                    reason: "does not start at income 1"
                )
            }
            guard rows.last?.maximum == UInt32.max else {
                throw TaxTableSourceError.invalidCoverage(
                    table: table,
                    reason: "has no open-ended final row"
                )
            }
            for index in 1..<rows.count where rows[index - 1].maximum + 1 != rows[index].minimum {
                throw TaxTableSourceError.invalidCoverage(
                    table: table,
                    reason: "contains a gap or overlap at row \(index + 1)"
                )
            }
        }

        return tables
    }

    private static func resourceURL() -> URL? {
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module, Bundle.main, Bundle(for: BundleToken.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks
        #else
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks
        #endif
        return bundles.lazy.compactMap {
            $0.url(forResource: resourceName, withExtension: "txt")
        }.first
    }

    private static func parse(
        _ bytes: ArraySlice<UInt8>,
        line: Int,
        name: String
    ) throws -> UInt32 {
        let trimmed = bytes.drop(while: { $0 == 0x20 }).reversed().drop(while: { $0 == 0x20 }).reversed()
        guard !trimmed.isEmpty else {
            throw sourceError(line, "invalid \(name)")
        }
        var value: UInt32 = 0
        for byte in trimmed {
            guard (0x30...0x39).contains(byte) else {
                throw sourceError(line, "invalid \(name)")
            }
            value = value * 10 + UInt32(byte - 0x30)
        }
        return value
    }

    private static func sourceError(_ line: Int, _ reason: String) -> TaxTableSourceError {
        .invalidRecord(line: line, reason: reason)
    }
}

private final class BundleToken: NSObject {}
