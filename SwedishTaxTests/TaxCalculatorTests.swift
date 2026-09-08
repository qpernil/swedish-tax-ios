import SwedishTaxFFI
import Foundation
import CoreGraphics
import XCTest
@testable import SwedishTax

final class TaxCalculatorTests: XCTestCase {
    func testRustCoreReadsOfficialMonthlyTableBoundaries() throws {
        XCTAssertEqual(
            try RustTaxCore.monthlyDeduction(
                table: 32,
                column: .column1,
                grossMonthlyIncome: 80_000
            ),
            .amount(25_944)
        )
        XCTAssertEqual(
            try RustTaxCore.monthlyDeduction(
                table: 32,
                column: .column1,
                grossMonthlyIncome: 80_001
            ),
            .percent(32)
        )
        XCTAssertThrowsError(
            try RustTaxCore.monthlyDeduction(
                table: 28,
                column: .column1,
                grossMonthlyIncome: 50_000
            )
        ) { error in
            XCTAssertEqual(error as? RustTaxCoreError, .invalidInput)
        }
    }

    func testEverySupportedTableAndColumnIsAvailableThroughTheBridge() throws {
        for table in supportedTaxTables {
            for column in TaxColumn.allCases {
                XCTAssertNoThrow(
                    try RustTaxCore.monthlyDeduction(
                        table: table,
                        column: column,
                        grossMonthlyIncome: 50_000
                    ),
                    "table=\(table), column=\(column)"
                )
                XCTAssertNoThrow(
                    try RustTaxCore.annualTax(
                        table: table,
                        column: column,
                        grossYearlyIncome: 540_000
                    ),
                    "table=\(table), column=\(column)"
                )
            }
        }
    }

    func testAnnualTaxMatchesTheSKV433WorkedExample() throws {
        XCTAssertEqual(
            try RustTaxCore.annualTax(
                table: 34,
                column: .column1,
                grossYearlyIncome: 216_000
            ),
            AnnualTax(
                assessedIncome: 216_000,
                basicAllowance: 42_400,
                taxableIncome: 173_600,
                stateIncomeTax: 0,
                municipalIncomeTax: 57_010,
                burialAndReligiousFee: 2_013,
                pensionFee: 15_100,
                pensionFeeCredit: 15_100,
                workIncomeCredit: 23_316,
                sicknessCompensationCredit: 0,
                earnedIncomeCredit: 1_002,
                publicServiceFee: 1_184,
                total: 35_889
            )
        )
    }

    func testSimplePlanHasStableEndToEndRustResult() throws {
        let calculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: IncomePlan(monthlySalary: 55_033)
        )

        XCTAssertEqual(calculation.monthlyIncome, 55_033)
        XCTAssertEqual(calculation.annualIncome, 660_396)
        XCTAssertEqual(calculation.workIncome, 660_396)
        XCTAssertEqual(calculation.pensionIncome, 0)
        XCTAssertEqual(calculation.dividendIncome, 0)
        XCTAssertEqual(calculation.tableDeduction, .amount(13_048))
        XCTAssertEqual(calculation.annualTax.total, 155_513)
        XCTAssertEqual(calculation.totalTax, 155_513)
        XCTAssertEqual(calculation.withheldTax, 156_576)
        XCTAssertEqual(calculation.withholding.entries.count, 1)
        XCTAssertEqual(calculation.withholding.entries[0].gross, 660_396)
        XCTAssertEqual(calculation.withholding.entries[0].rule, .table(.column1))
        XCTAssertEqual(calculation.pensionSalaryBasis, 660_396)
        XCTAssertEqual(calculation.sgiProgress, .estimated(
            IncomeBasisProgress(estimatedBasis: 592_000, maximumBasis: 592_000)
        ))
    }

    func testComplexPlanHasStableEndToEndRustResult() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        plan.adjustmentPercent = 33
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].setVacationAnnualEntitlementDays(30)
        plan.entries[0].adjustmentApplies = true
        plan.entries[0].useFullYearProjectionAsAdjustmentBasis = true

        let oneTimeID = plan.addEntry(kind: .oneTimeSalary)
        let oneTimeIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == oneTimeID })
        plan.entries[oneTimeIndex].amount = 372_000
        plan.entries[oneTimeIndex].adjustmentApplies = true

        let pensionID = plan.addEntry(kind: .monthlyOccupationalPension)
        let pensionIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == pensionID })
        plan.entries[pensionIndex].amount = 27_500
        plan.entries[pensionIndex].start = Date2026(month: 8, day: 1)
        plan.entries[pensionIndex].setPayerRole(.secondary, adjustmentAvailable: true)

        let calculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        let calibration = try XCTUnwrap(calculation.adjustmentCalibration)

        XCTAssertEqual(calculation.workIncome, 1_383_528)
        XCTAssertEqual(calculation.pensionIncome, 137_500)
        XCTAssertEqual(calculation.ordinaryIncome, 1_521_028)
        XCTAssertEqual(calculation.annualTax.total, 603_057)
        XCTAssertEqual(calculation.ordinaryFinalTax, 578_880)
        XCTAssertEqual(calculation.withheldTax, 497_814)
        XCTAssertEqual(calculation.taxBalance, 81_066)
        XCTAssertEqual(calculation.regularPensionPremiums, 139_954)
        XCTAssertEqual(calculation.vacationPensionPremiums, 36_159)
        XCTAssertEqual(calculation.employerPensionContributions, 176_113)
        XCTAssertEqual(calibration.basisIncome, 1_116_000)
        XCTAssertEqual(calibration.impliedTaxAdjustment, 24_177)
        XCTAssertEqual(calculation.withholding.entries.map(\.rule), [
            .adjustmentPercent(33),
            .adjustmentPercent(33),
            .secondary30,
        ])
    }

    func testWithholdingRulesAndAdditionalAmountComposeInRust() throws {
        var plan = IncomePlan(annualSalary: 700_000)
        let pensionID = plan.addEntry(kind: .annualOccupationalPension)
        let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == pensionID })
        plan.entries[index].amount = 100_000
        plan.entries[index].payerRole = .secondary

        var row = try withholdingRow(for: pensionID, in: plan)
        XCTAssertEqual(row.withheld, 30_000)
        XCTAssertEqual(row.rule, .secondary30)

        plan.adjustmentPercent = 38
        plan.entries[index].adjustmentApplies = true
        row = try withholdingRow(for: pensionID, in: plan)
        XCTAssertEqual(row.withheld, 38_000)
        XCTAssertEqual(row.rule, .adjustmentPercent(38))

        plan.entries[index].additionalWithholdingPerPayment = 500
        row = try withholdingRow(for: pensionID, in: plan)
        XCTAssertEqual(row.withheld, 44_000)
        XCTAssertEqual(row.additionalWithheld, 6_000)
        XCTAssertEqual(row.rule, .adjustmentPercent(38))
    }

    func testActualWithholdingOverridesEveryIncomeKindInRust() throws {
        var plan = IncomePlan(annualSalary: 700_000)
        for (index, kind) in IncomeKind.allCases.enumerated() {
            let entryIndex: Int
            if index == 0 {
                plan.entries[0].kind = kind
                entryIndex = 0
            } else {
                let id = plan.addEntry(kind: kind)
                entryIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == id })
            }
            plan.entries[entryIndex].amount = UInt32(100_000 + index)
            plan.entries[entryIndex].actualWithholding = UInt32(10_000 + index)
            plan.entries[entryIndex].additionalWithholdingPerPayment = 99
            plan.entries[entryIndex].adjustmentApplies = true
            plan.entries[entryIndex].payerRole = .secondary
        }
        plan.adjustmentPercent = 88

        let withholding = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        ).withholding

        XCTAssertEqual(withholding.entries.count, IncomeKind.allCases.count)
        for (index, row) in withholding.entries.enumerated() {
            XCTAssertEqual(row.withheld, UInt32(10_000 + index))
            XCTAssertEqual(row.regularWithheld, row.withheld)
            XCTAssertEqual(row.supplementalWithheld, 0)
            XCTAssertEqual(row.additionalWithheld, 0)
            XCTAssertEqual(row.rule, .actualAmount)
        }
    }

    func testAddingAndRemovingEveryIncomeKindRestoresTheRustResult() throws {
        for kind in IncomeKind.allCases {
            var plan = IncomePlan(monthlySalary: 45_000)
            let baseline = try RustTaxCore.planCalculation(
                table: 32,
                ageGroup: .under66,
                plan: plan
            )
            let id = plan.addEntry(kind: kind)
            let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == id })
            plan.entries[index].amount = 60_000

            let withEntry = try RustTaxCore.planCalculation(
                table: 32,
                ageGroup: .under66,
                plan: plan
            )
            XCTAssertNotEqual(withEntry, baseline, "kind=\(kind)")

            plan.removeEntry(id: id)
            let afterRemoval = try RustTaxCore.planCalculation(
                table: 32,
                ageGroup: .under66,
                plan: plan
            )
            XCTAssertEqual(afterRemoval, baseline, "kind=\(kind)")
        }
    }

    func testDividendAddsFinalTaxWithoutPreliminaryWithholding() throws {
        var plan = IncomePlan(annualSalary: 420_000)
        let dividendID = plan.addEntry(kind: .ownCompanyDividend)
        let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == dividendID })
        plan.entries[index].amount = 78_000

        let calculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        let dividendRow = try XCTUnwrap(
            calculation.withholding.entries.first { $0.entryID == dividendID }
        )

        XCTAssertEqual(calculation.dividendIncome, 78_000)
        XCTAssertEqual(calculation.dividendTax, 15_600)
        XCTAssertEqual(calculation.totalTax, calculation.ordinaryFinalTax + 15_600)
        XCTAssertEqual(dividendRow.withheld, 0)
        XCTAssertEqual(dividendRow.rule, .none)
    }

    func testDividendAllowanceComesFromRustWithCompleteBreakdown() throws {
        var plan = IncomePlan(annualSalary: 900_000)
        plan.entries[0].ownCompanySourced = true
        plan.dividendAllowance.acquisitionCost = 200_000
        plan.dividendAllowance.acquisitionCostInterestBasisPoints = 1_155
        plan.dividendAllowance.savedAllowance = 50_000

        let allowance = try RustTaxCore.dividendAllowance(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )

        XCTAssertEqual(allowance.ownerCashSalary, 900_000)
        XCTAssertEqual(allowance.companyCashPayroll, 900_000)
        XCTAssertEqual(allowance.jointWageBasis, 900_000)
        XCTAssertEqual(allowance.jointWageBasisAfterDeduction, 232_800)
        XCTAssertEqual(allowance.wageAllowanceBeforeCap, 116_400)
        XCTAssertEqual(allowance.wageCapSalary, 900_000)
        XCTAssertEqual(allowance.wageCap, 45_000_000)
        XCTAssertEqual(allowance.wageAllowance, 116_400)
        XCTAssertEqual(allowance.acquisitionCostInterestBasis, 100_000)
        XCTAssertEqual(allowance.acquisitionCostInterest, 11_550)
        XCTAssertEqual(allowance.savedAllowance, 50_000)
        XCTAssertEqual(allowance.total, 511_550)
        XCTAssertEqual(allowance.taxAtTwentyPercent, 102_310)
        XCTAssertEqual(allowance.netAfterTwentyPercentTax, 409_240)
    }

    func testVacationAndSalaryExchangeEditorCalculationsRemainStable() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].setVacationAnnualEntitlementDays(30)
        XCTAssertEqual(plan.entries[0].annualAmount, 891_000)
        XCTAssertEqual(plan.entries[0].vacationCompensation?.payoutDays, 24)
        XCTAssertEqual(plan.entries[0].vacationCompensationAmount, 120_528)

        let lumpID = plan.addEntry(kind: .oneTimeSalary)
        let lumpIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == lumpID })
        plan.entries[lumpIndex].amount = 372_000
        plan.entries[lumpIndex].salaryExchange = SalaryExchange()

        let allowance = try XCTUnwrap(plan.salaryExchangeAllowance(for: lumpID))
        XCTAssertEqual(allowance.pensionSalaryBasisBefore, 1_011_528)
        XCTAssertEqual(allowance.ceiling, 354_034)
        XCTAssertEqual(allowance.pensionContributionsBefore, 176_113)
        XCTAssertEqual(allowance.availableContribution, 177_921)
        XCTAssertEqual(allowance.maximumSacrifice, 168_231)

        plan.entries[lumpIndex].salaryExchange?.upliftBasisPoints = 580
        plan.entries[lumpIndex].salaryExchange?.previousYearPensionSalaryBasis = 1_092_000
        plan.entries[lumpIndex].salaryExchange?.pensionAndInsuranceCostsBeforeExchange = 158_170
        plan.entries[lumpIndex].salaryExchange?.sacrificedSalary = 211_000
        let yubicoAllowance = try XCTUnwrap(plan.salaryExchangeAllowance(for: lumpID))
        XCTAssertEqual(yubicoAllowance.ceiling, 382_200)
        XCTAssertEqual(yubicoAllowance.pensionContributionsBefore, 158_170)
        XCTAssertEqual(yubicoAllowance.availableContribution, 224_030)
        XCTAssertEqual(yubicoAllowance.maximumSacrifice, 211_749)
        XCTAssertEqual(plan.entries[lumpIndex].salaryExchangePensionContribution, 223_238)

        plan.entries[0].useAnnualDailyRateForPartialMonths = true
        XCTAssertEqual(plan.entries[0].annualAmount, 892_036)
        plan.entries[0].vacationCompensation?.rateBasisPoints = 500

        let rustCalculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        XCTAssertEqual(rustCalculation.workIncome, 1_164_636)
        XCTAssertEqual(rustCalculation.salaryExchangeSacrifice, 211_000)
        XCTAssertEqual(rustCalculation.salaryExchangePensionContributions, 223_238)
    }

    func testPersistedWorkspaceRoundTripsMultipleCompleteCalculations() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStateStore(
            fileURL: directory.appendingPathComponent("income-plan.json")
        )

        var plan = IncomePlan(monthlySalary: 93_000)
        plan.adjustmentPercent = 33
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].adjustmentApplies = true
        plan.entries[0].additionalWithholdingPerPayment = 1_250
        plan.entries[0].setVacationAnnualEntitlementDays(30)
        let pensionID = plan.addEntry(kind: .monthlyOccupationalPension)
        let pensionIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == pensionID })
        plan.entries[pensionIndex].amount = 27_500
        plan.entries[pensionIndex].start = Date2026(month: 8, day: 1)

        let firstDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let secondDate = Date(timeIntervalSinceReferenceDate: 2_000)
        let first = CalculationDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Current employment",
            createdAt: firstDate,
            table: 34,
            ageGroup: .atLeast66,
            plan: plan
        )
        let second = CalculationDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Pension scenario",
            createdAt: secondDate,
            table: 32,
            ageGroup: .under66,
            plan: IncomePlan(annualSalary: 720_000)
        )
        let expected = PersistedWorkspace(
            selectedDocumentID: second.id,
            documents: [first, second]
        )
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
    }

    func testStorePreservesUnreadableWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("income-plan.json")
        let store = AppStateStore(fileURL: fileURL)
        let incomplete = Data("{\"documents\":[]}".utf8)
        try incomplete.write(to: fileURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(PersistedWorkspace()))
        XCTAssertEqual(try Data(contentsOf: fileURL), incomplete)
    }

    func testStoreRejectsDuplicateDocumentIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStateStore(fileURL: directory.appendingPathComponent("income-plan.json"))

        let document = CalculationDocument()
        let duplicateIDs = PersistedWorkspace(documents: [document, document])
        XCTAssertThrowsError(try store.save(duplicateIDs)) { error in
            XCTAssertEqual(error as? AppStateStoreError, .invalidWorkspace)
        }
    }

    func testWorkspaceCanSwitchBetweenIndependentCalculations() throws {
        let first = CalculationDocument(
            name: "Salary",
            table: 34,
            ageGroup: .under66,
            plan: IncomePlan(monthlySalary: 70_000)
        )
        let second = CalculationDocument(
            name: "Pension",
            table: 31,
            ageGroup: .atLeast66,
            plan: IncomePlan(annualSalary: 480_000)
        )
        var workspace = PersistedWorkspace(
            selectedDocumentID: first.id,
            documents: [first, second]
        )

        XCTAssertEqual(workspace.selectedDocument, first)
        XCTAssertTrue(workspace.selectDocument(id: second.id))
        XCTAssertEqual(workspace.selectedDocument, second)
        XCTAssertFalse(workspace.selectDocument(id: UUID()))
        XCTAssertEqual(workspace.selectedDocument, second)
    }

    func testWorkspaceCreatesDuplicatesRenamesAndDeletesCalculations() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        var workspace = PersistedWorkspace(documents: [
            CalculationDocument(
                name: "Baseline",
                createdAt: date,
                table: 35,
                plan: IncomePlan(monthlySalary: 88_000)
            )
        ])
        let baseline = workspace.selectedDocument

        let duplicateID = workspace.duplicateSelectedDocument(date: date.addingTimeInterval(1))
        let duplicate = workspace.selectedDocument
        XCTAssertNotEqual(duplicateID, baseline.id)
        XCTAssertEqual(duplicate.name, "Baseline copy")
        XCTAssertEqual(duplicate.table, baseline.table)
        XCTAssertEqual(duplicate.ageGroup, baseline.ageGroup)
        XCTAssertEqual(duplicate.plan, baseline.plan)

        XCTAssertTrue(workspace.renameSelectedDocument(
            to: "  Higher salary  ",
            date: date.addingTimeInterval(2)
        ))
        XCTAssertEqual(workspace.selectedDocument.name, "Higher salary")
        XCTAssertFalse(workspace.renameSelectedDocument(to: "   "))

        let newID = workspace.createDocument(date: date.addingTimeInterval(3))
        XCTAssertEqual(workspace.selectedDocumentID, newID)
        XCTAssertEqual(workspace.selectedDocument.name, "Calculation 3")
        XCTAssertTrue(workspace.deleteDocument(id: newID))
        XCTAssertEqual(workspace.selectedDocumentID, duplicateID)
        XCTAssertTrue(workspace.deleteDocument(id: duplicateID))
        XCTAssertEqual(workspace.selectedDocumentID, baseline.id)
        XCTAssertFalse(workspace.deleteDocument(id: baseline.id))
        XCTAssertEqual(workspace.documents.count, 1)
    }

    func testPersistedPlanRequiresCurrentFields() throws {
        let encoded = try JSONEncoder().encode(IncomePlan(monthlySalary: 55_033))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for field in ["dividendAllowance", "nextID"] {
            var object = original
            object.removeValue(forKey: field)
            let incomplete = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(IncomePlan.self, from: incomplete))
        }
        var object = original
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "ownCompanySourced")
        object["entries"] = entries
        let incomplete = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(IncomePlan.self, from: incomplete))
    }

    func testBasisPointPercentagesUseExactTextConversion() {
        XCTAssertEqual(formatBasisPointsPercentage(0), "0")
        XCTAssertEqual(formatBasisPointsPercentage(570), "5.7")
        XCTAssertEqual(formatBasisPointsPercentage(576), "5.76")
        XCTAssertEqual(parseBasisPointsPercentage(".5"), 50)
        XCTAssertEqual(parseBasisPointsPercentage("5."), 500)
        XCTAssertNil(parseBasisPointsPercentage("5.123"))
    }

    @MainActor
    func testPDFReportContainsExpandedSectionsAndEscapesUserText() throws {
        let fixture = try pdfReportFixture()
        let html = fixture.report.html

        XCTAssertTrue(html.contains("Quarterly &lt;plan&gt; &amp; review"))
        XCTAssertTrue(html.contains("Employer &amp; Partners"))
        XCTAssertTrue(html.contains("All entries and options expanded"))
        XCTAssertTrue(html.contains("Annual daily rate (monthly amount × 12 ÷ 365)"))
        XCTAssertTrue(html.contains("Vacation compensation rate per paid day"))
        XCTAssertTrue(html.contains("Vacation payout included in pension salary basis"))
        XCTAssertTrue(html.contains("Actual 12 345 SEK"))
        XCTAssertTrue(html.contains("Use full-year projection as jämkning basis"))
        XCTAssertTrue(html.contains("Previous year&#39;s pensionable salary"))
        XCTAssertTrue(html.contains("Pension and insurance costs before exchange"))
        XCTAssertTrue(html.contains("Maximum salary exchange"))
        XCTAssertTrue(html.contains("Monthly table reference"))
        XCTAssertTrue(html.contains("Income-basis ceilings"))
        XCTAssertTrue(html.contains("SGI annualized recurring salary"))
        XCTAssertTrue(html.contains("Effective final tax rate"))
        XCTAssertTrue(html.contains("Annual tax projection breakdown"))
        XCTAssertTrue(html.contains("Preliminary 2027 dividend allowance"))
        XCTAssertTrue(html.contains("Joint wage basis after deduction"))
        XCTAssertTrue(html.contains("Acquisition-cost interest"))
        XCTAssertTrue(html.contains("All five steps expanded"))
        XCTAssertTrue(html.contains("Formula-tax change from projection"))
        XCTAssertTrue(html.contains("Official sources"))
        XCTAssertTrue(html.contains("SKV 433 technical specification, edition 36 (2026)"))
        XCTAssertTrue(html.contains("Skatteverket closely held company dividend rules (2026 reform)"))
        XCTAssertTrue(html.contains("Skatteverket 2026 amounts and percentages (income base amount)"))
        XCTAssertTrue(html.contains("preliminary 2027 dividend allowance"))
        XCTAssertTrue(html.contains("(https://www.skatteverket.se/download/"))
        XCTAssertTrue(html.contains("Försäkringskassan sickness-benefit qualifying income (SGI)"))
        XCTAssertFalse(html.contains("DisclosureGroup"))
    }

    @MainActor
    func testPDFReportCreatesPaginatedA4Document() throws {
        let fixture = try pdfReportFixture()
        let data = try fixture.report.pdfData()

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThanOrEqual(pdf.numberOfPages, 3)

        let firstPage = try XCTUnwrap(pdf.page(at: 1))
        let mediaBox = firstPage.getBoxRect(.mediaBox)
        XCTAssertEqual(mediaBox.width, 595.28, accuracy: 0.5)
        XCTAssertEqual(mediaBox.height, 841.89, accuracy: 0.5)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Swedish-Tax-Expanded-Report-QA.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func pdfReportFixture() throws -> (
        report: CalculationPDFReport,
        calculation: PlanCalculation
    ) {
        var plan = IncomePlan(monthlySalary: 93_000)
        plan.entries[0].description = "Employer & Partners"
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].useAnnualDailyRateForPartialMonths = true
        plan.entries[0].setVacationAnnualEntitlementDays(30)
        plan.entries[0].vacationCompensation?.rateBasisPoints = 500
        plan.entries[0].vacationCompensation?.pensionPremiumOverride = 12_345
        plan.entries[0].regularPensionPremium?.monthlyOverride = 15_000
        plan.entries[0].ownCompanySourced = true
        plan.entries[0].adjustmentApplies = true
        plan.entries[0].useFullYearProjectionAsAdjustmentBasis = true
        plan.adjustmentPercent = 33

        let oneTimeID = plan.addEntry(kind: .oneTimeSalary)
        let oneTimeIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == oneTimeID })
        plan.entries[oneTimeIndex].description = "Retention payment"
        plan.entries[oneTimeIndex].amount = 125_000
        plan.entries[oneTimeIndex].additionalWithholdingPerPayment = 2_500
        plan.entries[oneTimeIndex].salaryExchange = SalaryExchange(
            sacrificedSalary: 10_000,
            employerAddsUplift: true,
            upliftBasisPoints: 580,
            previousYearPensionSalaryBasis: 1_000_000,
            pensionAndInsuranceCostsBeforeExchange: 100_000
        )

        let pensionID = plan.addEntry(kind: .monthlyOccupationalPension)
        let pensionIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == pensionID })
        plan.entries[pensionIndex].description = "Occupational pension"
        plan.entries[pensionIndex].amount = 27_500
        plan.entries[pensionIndex].start = Date2026(month: 8, day: 1)
        plan.entries[pensionIndex].setPayerRole(.secondary, adjustmentAvailable: true)

        let dividendID = plan.addEntry(kind: .ownCompanyDividend)
        let dividendIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == dividendID })
        plan.entries[dividendIndex].description = "Dividend from Example AB"
        plan.entries[dividendIndex].amount = 78_000
        plan.dividendAllowance.acquisitionCost = 200_000
        plan.dividendAllowance.acquisitionCostInterestBasisPoints = 1_155
        plan.dividendAllowance.savedAllowance = 50_000

        let calculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        let fixedDate = Date(timeIntervalSince1970: 1_767_268_800)
        let document = CalculationDocument(
            name: "Quarterly <plan> & review",
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        return (
            CalculationPDFReport(
                document: document,
                calculation: calculation,
                generatedAt: fixedDate
            ),
            calculation
        )
    }

    private func withholdingRow(
        for entryID: UInt64,
        in plan: IncomePlan
    ) throws -> EntryWithholding {
        let calculation = try RustTaxCore.planCalculation(
            table: 32,
            ageGroup: .under66,
            plan: plan
        )
        return try XCTUnwrap(
            calculation.withholding.entries.first { $0.entryID == entryID }
        )
    }
}

// ARM64 C sizes/offsets for the frozen v1 layouts in SwedishTaxFFI.h.
// Generated from a native clang sizeof/offsetof probe; Swift must import the same layout.
extension TaxCalculatorTests {
    func testPlanningCLayoutsOnARM64() {
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.size, 64)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.work_income), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.pension_income), 4)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.dividend_income), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.sgi_annual_rate), 12)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.adjustment_basis_work_income), 16)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.pension_salary_basis), 20)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.regular_pension_premiums), 24)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.vacation_pension_premiums), 28)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.salary_exchange_sacrifice), 32)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.salary_exchange_pension_contributions), 36)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.ordinary_income), 40)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.monthly_taxable_income), 44)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.gross_income), 48)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.total_employer_pension_contributions), 52)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanTotals>.offset(of: \.employer_pension_share_of_basis), 56)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.size, 48)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.january), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.february), 4)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.march), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.april), 12)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.may), 16)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.june), 20)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.july), 24)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.august), 28)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.september), 32)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.october), 36)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.november), 40)
        XCTAssertEqual(MemoryLayout<SwedishTaxMonthlyAmounts>.offset(of: \.december), 44)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.size, 72)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.ceiling), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.pension_salary_basis_before), 4)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.pension_salary_basis_after), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.previous_year_pension_salary_basis), 12)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.pension_and_insurance_costs_before_exchange), 20)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.pension_contributions_before), 28)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.regular_pension_premiums), 32)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.vacation_pension_premiums), 36)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.other_exchange_contributions), 40)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.selected_exchange_contribution), 44)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.total_employer_pension_contributions), 48)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.available_contribution), 52)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.maximum_sacrifice), 56)
        XCTAssertEqual(MemoryLayout<SwedishTaxExchangeAllowance>.offset(of: \.contribution_share_of_basis), 64)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.size, 208)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.status), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.entry_id), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.annual_amount), 16)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.total_annual_amount), 20)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.withholding_payment_count), 24)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.requested_additional_withholding), 28)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.vacation_compensation_amount), 32)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.regular_pension_premium_amount), 36)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.vacation_pension_premium_amount), 40)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.salary_exchange_sacrifice), 44)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.salary_exchange_pension_contribution), 48)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.pension_salary_basis_amount), 52)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.full_year_adjustment_basis_amount), 56)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.is_valid), 60)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.pension_benchmark_monthly), 64)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.suggested_vacation_days), 68)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.vacation_amount_per_day), 72)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.monthly_amounts), 80)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.has_allowance), 128)
        XCTAssertEqual(MemoryLayout<SwedishTaxEntrySupport>.offset(of: \.allowance), 136)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.size, 128)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.status), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.issue_kind), 4)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.issue_entry_id), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.issue_maximum), 16)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.totals), 24)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.has_uniform_monthly_table_reference), 88)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.salary_column), 92)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.pension_column), 96)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.entries), 104)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.entries_count), 112)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanSupport>.offset(of: \.entries_capacity), 120)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.size, 20)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.offset(of: \.regular_pension_monthly_threshold), 0)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.offset(of: \.default_vacation_rate_basis_points), 4)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.offset(of: \.default_exchange_uplift_basis_points), 8)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.offset(of: \.employer_pension_allowance_maximum), 12)
        XCTAssertEqual(MemoryLayout<SwedishTaxPlanningPolicy>.offset(of: \.acquisition_cost_threshold), 16)
    }

    func testInvalidExchangeUsesClampedRustPreviewAndPreservesSavedRequest() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        let id = plan.addEntry(kind: .oneTimeSalary)
        plan.entries[1].amount = 372_000
        plan.entries[1].includedInPensionSalaryBasis = true
        plan.entries[1].salaryExchange = SalaryExchange()
        plan.entries[1].salaryExchange?.sacrificedSalary = .max
        let saved = try JSONEncoder().encode(plan)
        let allowance = try XCTUnwrap(plan.salaryExchangeAllowance(for: id))
        XCTAssertEqual(allowance.ceiling, 434890)
        XCTAssertEqual(allowance.pensionSalaryBasisBefore, 1488000)
        XCTAssertEqual(allowance.pensionSalaryBasisAfter, 1242544)
        XCTAssertEqual(allowance.maximumSacrifice, 245456)
        XCTAssertEqual(allowance.pensionContributionsBefore, 175296)
        XCTAssertEqual(allowance.availableContribution, 259594)
        XCTAssertEqual(plan.validationIssue, .salaryExchangeExceedsAllowance(entryID: id, maximum: allowance.maximumSacrifice))
        XCTAssertEqual(plan.entries[1].salaryExchangeSacrifice, 372_000)
        XCTAssertEqual(plan.totals.workIncome, 1_116_000)
        XCTAssertThrowsError(try RustTaxCore.planCalculation(table: 32, ageGroup: .under66, plan: plan))
        XCTAssertEqual(try JSONDecoder().decode(IncomePlan.self, from: saved), plan)
        XCTAssertEqual(plan.entries[1].salaryExchange?.sacrificedSalary, .max)
        plan.entries[1].salaryExchange?.sacrificedSalary = allowance.maximumSacrifice
        XCTAssertNil(plan.validationIssue)
        XCTAssertNoThrow(try RustTaxCore.planCalculation(table: 32, ageGroup: .under66, plan: plan))
    }

    func testSupportRetainsInvalidPeriodRowsAndCopiesOwnedBuffers() throws {
        var plan = IncomePlan(monthlySalary: 55_033)
        plan.entries[0] = IncomeEntry(id: .max, kind: .monthlySalary)
        plan.entries[0].amount = 55_033
        plan.entries[0].start = Date2026(month: 12, day: 1)
        plan.entries[0].end = Date2026(month: 1, day: 1)
        for _ in 0..<1000 {
            let support = try RustTaxCore.planSupport(plan)
            XCTAssertEqual(support.issue, .invalidPaymentPeriod(entryID: .max))
            XCTAssertEqual(support.entries.count, 1)
            XCTAssertEqual(support.entries[0].entry_id, .max)
            XCTAssertEqual(support.entries[0].annual_amount, 0)
            XCTAssertEqual(support.totals.workIncome, 0)
        }
    }

    func testExchangePriorYearConfirmedCostsAndSaturationMatchSharedFixtures() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        _ = plan.addEntry(kind: .oneTimeSalary)
        plan.entries[1].amount = 372_000
        plan.entries[1].includedInPensionSalaryBasis = true
        plan.entries[1].salaryExchange = SalaryExchange()
        plan.entries[1].salaryExchange?.sacrificedSalary = .max
        plan.entries[1].salaryExchange?.previousYearPensionSalaryBasis = 1_092_000
        plan.entries[1].salaryExchange?.pensionAndInsuranceCostsBeforeExchange = 158_170
        let confirmed = try XCTUnwrap(plan.salaryExchangeAllowance(for: plan.entries[1].id))
        XCTAssertEqual(confirmed.ceiling, 382200)
        XCTAssertEqual(confirmed.pensionSalaryBasisAfter, 1092000)
        XCTAssertEqual(confirmed.maximumSacrifice, 211829)
        XCTAssertEqual(confirmed.pensionContributionsBefore, 158170)
        plan.entries[0].amount = .max
        plan.entries[1].amount = .max
        plan.entries[1].salaryExchange?.previousYearPensionSalaryBasis = nil
        plan.entries[1].salaryExchange?.pensionAndInsuranceCostsBeforeExchange = nil
        let saturated = try XCTUnwrap(plan.salaryExchangeAllowance(for: plan.entries[1].id))
        XCTAssertEqual(saturated.ceiling, 592000)
        XCTAssertEqual(saturated.pensionSalaryBasisBefore, 4294967295)
        XCTAssertEqual(saturated.pensionSalaryBasisAfter, 4294967295)
        XCTAssertEqual(saturated.maximumSacrifice, 0)
        XCTAssertEqual(plan.entries[1].salaryExchange?.sacrificedSalary, .max)
    }
}
