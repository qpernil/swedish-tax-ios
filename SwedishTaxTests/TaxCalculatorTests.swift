import Foundation
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

        XCTAssertEqual(calculation.workIncome, 1_378_883)
        XCTAssertEqual(calculation.pensionIncome, 137_500)
        XCTAssertEqual(calculation.ordinaryIncome, 1_516_383)
        XCTAssertEqual(calculation.annualTax.total, 600_613)
        XCTAssertEqual(calculation.ordinaryFinalTax, 576_436)
        XCTAssertEqual(calculation.withheldTax, 496_281)
        XCTAssertEqual(calculation.taxBalance, 80_155)
        XCTAssertEqual(calculation.regularPensionPremiums, 139_954)
        XCTAssertEqual(calculation.vacationPensionPremiums, 34_765)
        XCTAssertEqual(calculation.employerPensionContributions, 174_719)
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

    func testVacationAndSalaryExchangeEditorCalculationsRemainStable() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].setVacationAnnualEntitlementDays(30)
        XCTAssertEqual(plan.entries[0].annualAmount, 891_000)
        XCTAssertEqual(plan.entries[0].vacationCompensation?.payoutDays, 24)
        XCTAssertEqual(plan.entries[0].vacationCompensationAmount, 115_883)

        let lumpID = plan.addEntry(kind: .oneTimeSalary)
        let lumpIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == lumpID })
        plan.entries[lumpIndex].amount = 372_000
        plan.entries[lumpIndex].salaryExchange = SalaryExchange()

        let allowance = try XCTUnwrap(plan.salaryExchangeAllowance(for: lumpID))
        XCTAssertEqual(allowance.pensionSalaryBasisBefore, 1_006_883)
        XCTAssertEqual(allowance.ceiling, 352_409)
        XCTAssertEqual(allowance.availableContribution, 177_690)
        XCTAssertEqual(allowance.maximumSacrifice, 168_012)
    }

    func testPersistedAppStateRoundTripsTheCompletePlan() throws {
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

        let expected = PersistedAppState(
            table: 34,
            ageGroup: .atLeast66,
            plan: plan
        )
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
    }

    func testPersistedPlanWithoutNewFieldsStillDecodes() throws {
        let encoded = try JSONEncoder().encode(IncomePlan(monthlySalary: 55_033))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "dividendAllowance")
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "ownCompanySourced")
        entries[0].removeValue(forKey: "actualWithholding")
        object["entries"] = entries

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(IncomePlan.self, from: legacy)

        XCTAssertFalse(restored.entries[0].ownCompanySourced)
        XCTAssertNil(restored.entries[0].actualWithholding)
        XCTAssertEqual(restored.dividendAllowance, DividendAllowanceInputs2027())
    }

    func testBasisPointPercentagesUseExactTextConversion() {
        XCTAssertEqual(formatBasisPointsPercentage(0), "0")
        XCTAssertEqual(formatBasisPointsPercentage(570), "5.7")
        XCTAssertEqual(formatBasisPointsPercentage(576), "5.76")
        XCTAssertEqual(parseBasisPointsPercentage(".5"), 50)
        XCTAssertEqual(parseBasisPointsPercentage("5."), 500)
        XCTAssertNil(parseBasisPointsPercentage("5.123"))
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
