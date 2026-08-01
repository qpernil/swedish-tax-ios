import Foundation

struct PersistedAppState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var table: UInt8
    var ageGroup: TaxAgeGroup
    var plan: IncomePlan

    init(
        version: Int = currentVersion,
        table: UInt8 = 32,
        ageGroup: TaxAgeGroup = .under66,
        plan: IncomePlan = IncomePlan(monthlySalary: 55_033)
    ) {
        self.version = version
        self.table = table
        self.ageGroup = ageGroup
        self.plan = plan
    }
}

enum AppStateStoreError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidTaxTable(UInt8)
}

struct AppStateStore: Sendable {
    let fileURL: URL

    static let live = AppStateStore(fileURL: defaultFileURL())

    func load() throws -> PersistedAppState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let state = try JSONDecoder().decode(
            PersistedAppState.self,
            from: Data(contentsOf: fileURL)
        )
        guard state.version == PersistedAppState.currentVersion else {
            throw AppStateStoreError.unsupportedVersion(state.version)
        }
        guard (TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable).contains(state.table) else {
            throw AppStateStoreError.invalidTaxTable(state.table)
        }
        return state
    }

    func save(_ state: PersistedAppState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directoryName = Bundle.main.bundleIdentifier ?? "SwedishTax"
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("income-plan.json", isDirectory: false)
    }
}
