import Foundation

struct CalculationDocument: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var table: UInt8
    var ageGroup: TaxAgeGroup
    var plan: IncomePlan

    init(
        id: UUID = UUID(),
        name: String = "My calculation",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        table: UInt8 = 32,
        ageGroup: TaxAgeGroup = .under66,
        plan: IncomePlan = IncomePlan(monthlySalary: 55_033)
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.table = table
        self.ageGroup = ageGroup
        self.plan = plan
    }
}

struct PersistedWorkspace: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    var selectedDocumentID: UUID
    var documents: [CalculationDocument]

    init(
        version: Int = currentVersion,
        selectedDocumentID: UUID? = nil,
        documents: [CalculationDocument]? = nil
    ) {
        let initialDocuments: [CalculationDocument]
        if let documents, !documents.isEmpty {
            initialDocuments = documents
        } else {
            initialDocuments = [CalculationDocument()]
        }
        self.version = version
        self.documents = initialDocuments
        self.selectedDocumentID = selectedDocumentID ?? initialDocuments[0].id
    }

    var selectedDocument: CalculationDocument {
        documents.first { $0.id == selectedDocumentID } ?? documents[0]
    }

    @discardableResult
    mutating func selectDocument(id: UUID) -> Bool {
        guard documents.contains(where: { $0.id == id }) else { return false }
        selectedDocumentID = id
        return true
    }

    @discardableResult
    mutating func createDocument(date: Date = Date()) -> UUID {
        let document = CalculationDocument(
            name: uniqueName(startingWith: "Calculation \(documents.count + 1)"),
            createdAt: date
        )
        documents.append(document)
        selectedDocumentID = document.id
        return document.id
    }

    @discardableResult
    mutating func duplicateSelectedDocument(date: Date = Date()) -> UUID {
        let selected = selectedDocument
        let copy = CalculationDocument(
            name: uniqueName(startingWith: "\(selected.name) copy"),
            createdAt: date,
            table: selected.table,
            ageGroup: selected.ageGroup,
            plan: selected.plan
        )
        documents.append(copy)
        selectedDocumentID = copy.id
        return copy.id
    }

    @discardableResult
    mutating func renameSelectedDocument(to proposedName: String, date: Date = Date()) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !name.isEmpty,
            let index = documents.firstIndex(where: { $0.id == selectedDocumentID })
        else { return false }
        documents[index].name = name
        documents[index].modifiedAt = date
        return true
    }

    @discardableResult
    mutating func deleteDocument(id: UUID) -> Bool {
        guard
            documents.count > 1,
            let index = documents.firstIndex(where: { $0.id == id })
        else { return false }

        let deletedSelection = id == selectedDocumentID
        documents.remove(at: index)
        if deletedSelection {
            selectedDocumentID = documents[min(index, documents.count - 1)].id
        }
        return true
    }

    private func uniqueName(startingWith base: String) -> String {
        let names = Set(documents.map(\.name))
        guard names.contains(base) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }
}

enum AppStateStoreError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidTaxTable(UInt8)
    case invalidWorkspace
}

struct AppStateStore: Sendable {
    let fileURL: URL

    static let live = AppStateStore(fileURL: defaultFileURL())

    func load() throws -> PersistedWorkspace? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let version = try JSONDecoder().decode(VersionEnvelope.self, from: data).version

        switch version {
        case PersistedWorkspace.currentVersion:
            let workspace = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
            try validate(workspace)
            return workspace
        case LegacyAppState.currentVersion:
            let legacy = try JSONDecoder().decode(LegacyAppState.self, from: data)
            guard supportedTaxTables.contains(legacy.table) else {
                throw AppStateStoreError.invalidTaxTable(legacy.table)
            }
            return PersistedWorkspace(documents: [
                CalculationDocument(
                    table: legacy.table,
                    ageGroup: legacy.ageGroup,
                    plan: legacy.plan
                )
            ])
        default:
            throw AppStateStoreError.unsupportedVersion(version)
        }
    }

    func save(_ workspace: PersistedWorkspace) throws {
        try validate(workspace)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func validate(_ workspace: PersistedWorkspace) throws {
        guard workspace.version == PersistedWorkspace.currentVersion else {
            throw AppStateStoreError.unsupportedVersion(workspace.version)
        }
        let documentIDs = Set(workspace.documents.map(\.id))
        guard
            !workspace.documents.isEmpty,
            documentIDs.count == workspace.documents.count,
            workspace.documents.contains(where: { $0.id == workspace.selectedDocumentID })
        else { throw AppStateStoreError.invalidWorkspace }
        if let invalid = workspace.documents.first(where: {
            !supportedTaxTables.contains($0.table)
        }) {
            throw AppStateStoreError.invalidTaxTable(invalid.table)
        }
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

private struct VersionEnvelope: Decodable {
    var version: Int
}

private struct LegacyAppState: Decodable {
    static let currentVersion = 1

    var version: Int
    var table: UInt8
    var ageGroup: TaxAgeGroup
    var plan: IncomePlan
}
