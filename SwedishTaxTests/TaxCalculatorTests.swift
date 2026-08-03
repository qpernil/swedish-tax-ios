import CryptoKit
import Foundation
import XCTest
#if canImport(SwedishTax)
import SwiftUI
@testable import SwedishTax
#else
@testable import SwedishTaxCore
#endif

final class TaxCalculatorTests: XCTestCase {
    private let columns = TaxColumn.allCases
    private let annualFormulaGrossBreakpoints: [UInt32] = [
        25_042, 53_872, 58_608, 65_712, 103_600, 116_328, 161_024, 184_112,
        191_808, 296_000, 310_208, 466_496, 478_336, 660_672, 673_038, 760_128
    ]
    private let taxableIncomeBreakpoints: [UInt32] = [40_000, 118_400, 240_000, 643_200]

    #if canImport(SwedishTax)
    func testBasisPointPercentagesUseExactTextConversion() {
        XCTAssertEqual(formatBasisPointsPercentage(0), "0")
        XCTAssertEqual(formatBasisPointsPercentage(570), "5.7")
        XCTAssertEqual(formatBasisPointsPercentage(576), "5.76")
        XCTAssertEqual(parseBasisPointsPercentage(""), 0)
        XCTAssertEqual(parseBasisPointsPercentage("5.76"), 576)
        XCTAssertEqual(parseBasisPointsPercentage(".5"), 50)
        XCTAssertEqual(parseBasisPointsPercentage("5."), 500)
        XCTAssertNil(parseBasisPointsPercentage("5.123"))
        XCTAssertNil(parseBasisPointsPercentage("42949673"))
    }
    #endif

    private func threeEntryPlan(
        targetKind: IncomeKind,
        targetIndex: Int
    ) -> (baselinePlan: IncomePlan, plan: IncomePlan, targetID: UInt64) {
        var baselinePlan = IncomePlan(monthlySalary: 45_000)
        baselinePlan.entries[0].description = "Salary"
        let pensionID = baselinePlan.addEntry(kind: .annualOccupationalPension)
        let pensionIndex = baselinePlan.entries.index(before: baselinePlan.entries.endIndex)
        precondition(baselinePlan.entries[pensionIndex].id == pensionID)
        baselinePlan.entries[pensionIndex].description = "Pension"
        baselinePlan.entries[pensionIndex].amount = 120_000
        baselinePlan.entries[pensionIndex].payerRole = .secondary

        var plan = baselinePlan
        let targetID = plan.addEntry(kind: targetKind)
        let appendedIndex = plan.entries.index(before: plan.entries.endIndex)
        precondition(plan.entries[appendedIndex].id == targetID)
        plan.entries[appendedIndex].description = "Temporary \(targetKind)"
        plan.entries[appendedIndex].amount = 60_000
        let addedEntry = plan.entries.remove(at: appendedIndex)
        plan.entries.insert(addedEntry, at: targetIndex)
        return (baselinePlan, plan, targetID)
    }

    func testAddingAndRemovingEveryIncomeKindAtFirstMiddleAndLastRestoresCalculation() throws {
        for kind in IncomeKind.allCases {
            for targetIndex in 0..<3 {
                let scenario = threeEntryPlan(targetKind: kind, targetIndex: targetIndex)
                var plan = scenario.plan
                let position = ["first", "middle", "last"][targetIndex]
                let context = "\(kind) in \(position) position"
                let baselineCalculation = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: scenario.baselinePlan)
                )

                XCTAssertEqual(
                    plan.entries.count,
                    scenario.baselinePlan.entries.count + 1,
                    context
                )
                XCTAssertEqual(plan.entries[targetIndex].id, scenario.targetID, context)
                XCTAssertEqual(plan.entries[targetIndex].kind, kind, context)
                let calculationWithAddedEntry = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
                )
                XCTAssertNotEqual(calculationWithAddedEntry, baselineCalculation, context)

                plan.removeEntry(id: scenario.targetID)

                let calculationAfterRemoval = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
                )
                XCTAssertEqual(plan.entries, scenario.baselinePlan.entries, context)
                XCTAssertEqual(calculationAfterRemoval, baselineCalculation, context)
            }
        }
    }

#if canImport(SwedishTax)
    @MainActor
    func testIncomeEditorBindingRemainsSafeForEveryKindAndListPosition() throws {
        for kind in IncomeKind.allCases {
            for targetIndex in 0..<3 {
                let scenario = threeEntryPlan(targetKind: kind, targetIndex: targetIndex)
                var plan = scenario.plan
                let targetID = scenario.targetID
                let deletedSnapshot = try XCTUnwrap(plan.entries.first { $0.id == targetID })
                let position = ["first", "middle", "last"][targetIndex]
                let context = "\(kind) in \(position) position"
                let baselineCalculation = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: scenario.baselinePlan)
                )
                let planBinding = Binding(
                    get: { plan },
                    set: { plan = $0 }
                )
                let entryBinding = try XCTUnwrap(planBinding.incomeEntry(id: targetID))

                XCTAssertEqual(
                    plan.entries.count,
                    scenario.baselinePlan.entries.count + 1,
                    context
                )
                XCTAssertEqual(plan.entries[targetIndex].id, targetID, context)
                XCTAssertEqual(plan.entries[targetIndex].kind, kind, context)
                let calculationWithAddedEntry = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
                )
                XCTAssertNotEqual(calculationWithAddedEntry, baselineCalculation, context)

                plan.removeEntry(id: targetID)

                XCTAssertEqual(entryBinding.wrappedValue, deletedSnapshot, context)
                var outgoingEdit = entryBinding.wrappedValue
                outgoingEdit.amount = .max
                entryBinding.wrappedValue = outgoingEdit
                let calculationAfterRemoval = try XCTUnwrap(
                    PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
                )
                XCTAssertEqual(plan.entries, scenario.baselinePlan.entries, context)
                XCTAssertEqual(calculationAfterRemoval, baselineCalculation, context)
                XCTAssertNil(planBinding.incomeEntry(id: targetID), context)
            }
        }
    }
#endif

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
        plan.entries[0].vacationCompensation = VacationCompensation(
            annualEntitlementDays: 30,
            start: plan.entries[0].start,
            end: plan.entries[0].end
        )
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
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, expected)

        var restoredPlan = restored.plan
        XCTAssertEqual(restoredPlan.addEntry(), 3)
    }

    func testOfficialResourceIsPreservedByteForByte() throws {
        let data = try TaxTables.sourceData()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(
            hash,
            "8c5abe81d774ce083fec81ceed430282e39208c8b5a7a961a4760e4875e850ce"
        )
    }

    func testTablesCoverEveryPositiveIncomeWithoutGaps() throws {
        let allTables = try TaxTables.all()
        XCTAssertEqual(allTables.values.reduce(0) { $0 + $1.count }, 7_966)

        for table in TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable {
            let rows = try XCTUnwrap(allTables[table])
            XCTAssertEqual(rows.first?.minimum, 1, "Table \(table)")
            XCTAssertEqual(rows.last?.maximum, UInt32.max, "Table \(table)")

            for index in 1..<rows.count {
                XCTAssertEqual(
                    rows[index - 1].maximum + 1,
                    rows[index].minimum,
                    "Table \(table), row \(index + 1)"
                )
            }

            for row in rows {
                for (index, column) in columns.enumerated() {
                    let expected: TaxDeduction = row.kind == .amount
                        ? .amount(row.values[index])
                        : .percent(row.values[index])
                    XCTAssertEqual(
                        try TaxCalculator.monthlyDeduction(
                            table: table,
                            column: column,
                            grossMonthlyIncome: row.minimum
                        ),
                        expected
                    )
                    XCTAssertEqual(
                        try TaxCalculator.monthlyDeduction(
                            table: table,
                            column: column,
                            grossMonthlyIncome: row.maximum
                        ),
                        expected
                    )
                }
            }
        }
    }

    func testOfficialBoundaryValuesMatchTheSourceFile() {
        XCTAssertEqual(deduction(29, .column6, 2_001), .amount(2))
        XCTAssertEqual(deduction(29, .column1, UInt32.max), .percent(48))
        XCTAssertEqual(deduction(32, .column6, 2_001), .amount(2))
        XCTAssertEqual(deduction(32, .column1, 80_000), .amount(25_944))
        XCTAssertEqual(deduction(32, .column1, 80_001), .percent(32))
        XCTAssertEqual(deduction(33, .column4, 80_000), .amount(23_386))
        XCTAssertEqual(deduction(33, .column6, 80_001), .percent(39))
        XCTAssertEqual(deduction(34, .column3, 80_000), .amount(24_065))
        XCTAssertEqual(deduction(34, .column4, UInt32.max), .percent(45))
        XCTAssertEqual(deduction(42, .column6, 2_001), .amount(3))
        XCTAssertEqual(deduction(42, .column4, UInt32.max), .percent(51))
    }

    func testAnnualFormulaMatchesSKV433WorkedExamples() {
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
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

        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 34,
                column: .column1,
                grossYearlyIncome: 31_200
            ),
            AnnualTax(
                assessedIncome: 31_200,
                basicAllowance: 25_100,
                taxableIncome: 6_100,
                stateIncomeTax: 0,
                municipalIncomeTax: 2_003,
                burialAndReligiousFee: 70,
                pensionFee: 2_200,
                pensionFeeCredit: 2_003,
                workIncomeCredit: 0,
                sicknessCompensationCredit: 0,
                earnedIncomeCredit: 0,
                publicServiceFee: 61,
                total: 2_331
            )
        )

        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 34,
                column: .column1,
                grossYearlyIncome: 1_020_000
            ),
            AnnualTax(
                assessedIncome: 1_020_000,
                basicAllowance: 17_400,
                taxableIncome: 1_002_600,
                stateIncomeTax: 71_920,
                municipalIncomeTax: 329_253,
                burialAndReligiousFee: 11_630,
                pensionFee: 47_100,
                pensionFeeCredit: 47_100,
                workIncomeCredit: 53_134,
                sicknessCompensationCredit: 0,
                earnedIncomeCredit: 1_500,
                publicServiceFee: 1_184,
                total: 359_353
            )
        )
    }

    func testStateTaxUsesWideArithmeticForHighIncomes() throws {
        let annual = try XCTUnwrap(
            TaxCalculator.calculateAnnualTax(
                table: 34,
                column: .column1,
                grossYearlyIncome: 300_000_000
            )
        )

        XCTAssertEqual(annual.taxableIncome, 299_982_600)
        XCTAssertEqual(annual.stateIncomeTax, 59_867_920)
    }

    func testVacationCompensationSaturatesAtNumericLimits() {
        var vacation = VacationCompensation(
            annualEntitlementDays: UInt32.max,
            start: Date2026(month: 1, day: 1),
            end: Date2026(month: 12, day: 31)
        )
        vacation.payoutDays = UInt32.max

        XCTAssertEqual(vacation.amount(monthlySalary: UInt32.max), UInt32.max)
    }

    func testAnnualizedFormulaMatchesEveryMonthlyAmountEntry() throws {
        for table in TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable {
            for row in try XCTUnwrap(try TaxTables.rows(for: table)) where row.kind == .amount {
                let annualIncome = row.maximum * 12
                for (index, column) in columns.enumerated() {
                    let annual = try XCTUnwrap(
                        TaxCalculator.calculateAnnualTax(
                            table: table,
                            column: column,
                            grossYearlyIncome: annualIncome
                        )
                    )
                    XCTAssertEqual(
                        annual.total / 12,
                        row.values[index],
                        "Table \(table), column \(index + 1), bracket \(row.minimum)...\(row.maximum)"
                    )
                }
            }
        }
    }

    func testAnnualizedFormulaMatchesEveryMonthlyPercentageEntry() throws {
        for table in TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable {
            for row in try XCTUnwrap(try TaxTables.rows(for: table)) where row.kind == .percent {
                let firstBracketMaximum = (row.minimum + 199) / 200 * 200
                let monthlyIncomes = row.maximum == UInt32.max
                    ? [firstBracketMaximum]
                    : [firstBracketMaximum, row.maximum]

                for monthlyIncome in monthlyIncomes {
                    let annualIncome = monthlyIncome * 12
                    for (index, column) in columns.enumerated() {
                        let annual = try XCTUnwrap(
                            TaxCalculator.calculateAnnualTax(
                                table: table,
                                column: column,
                                grossYearlyIncome: annualIncome
                            )
                        )
                        let denominator = UInt64(annualIncome)
                        let calculated = UInt64(annual.total) * 100
                        let published = UInt64(row.values[index]) * denominator
                        let difference = calculated > published
                            ? calculated - published
                            : published - calculated
                        XCTAssertLessThanOrEqual(
                            difference * 1_000,
                            denominator * 501,
                            "Table \(table), column \(index + 1), income \(monthlyIncome)"
                        )
                    }
                }
            }
        }
    }

    func testUnsupportedInputsReturnNilAndZeroIncomeHasZeroTax() {
        XCTAssertNil(deduction(28, .column1, 50_000))
        XCTAssertNil(deduction(43, .column1, 50_000))
        XCTAssertEqual(deduction(32, .column1, 0), .amount(0))
        XCTAssertNil(
            TaxCalculator.calculateAnnualTax(
                table: 28,
                column: .column1,
                grossYearlyIncome: 50_000
            )
        )
        XCTAssertNil(
            TaxCalculator.calculateAnnualTax(
                table: 43,
                column: .column1,
                grossYearlyIncome: 50_000
            )
        )
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 32,
                column: .column1,
                grossYearlyIncome: 0
            )?.total,
            0
        )
    }

    func testMarginalRateUsesAnnualFormulaAtAllIncomes() {
        let expected = Double(38_894 - 35_889) * 100 / 12_000
        XCTAssertEqual(
            TaxCalculator.calculateMarginalRate(
                table: 34,
                column: .column1,
                monthlyIncome: 18_000
            ),
            expected
        )
        XCTAssertNil(
            TaxCalculator.calculateMarginalRate(
                table: 29,
                column: .column1,
                monthlyIncome: UInt32.max
            )
        )
        XCTAssertNil(
            TaxCalculator.calculateMarginalRate(
                table: 28,
                column: .column1,
                monthlyIncome: 18_000
            )
        )
    }

    func testMarginalRateCoversEveryAnnualFormulaRangeTransition() throws {
        for table in TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable {
            for column in columns {
                for breakpoint in annualFormulaGrossBreakpoints {
                    try assertFormulaTransition(table: table, column: column, breakpoint: breakpoint)
                }
                for taxableBreakpoint in taxableIncomeBreakpoints {
                    try assertFormulaTransition(
                        table: table,
                        column: column,
                        breakpoint: findGrossIncome(
                            table: table,
                            column: column,
                            taxableBreakpoint: taxableBreakpoint
                        )
                    )
                }
            }
        }
    }

    func testCalculationModelMatchesRustGUIBehavior() throws {
        let defaultCalculation = try XCTUnwrap(
            try TaxCalculation(
                table: 32,
                column: .column1,
                period: .monthly,
                income: 55_033
            )
        )
        XCTAssertEqual(defaultCalculation.annualTax.stateIncomeTax, 0)
        XCTAssertLessThanOrEqual(UInt64(55_033) * 12, 660_400)
        XCTAssertGreaterThan(UInt64(55_034) * 12, 660_400)

        let monthly = try XCTUnwrap(
            try TaxCalculation(
                table: 34,
                column: .column1,
                period: .monthly,
                income: 18_000
            )
        )
        XCTAssertEqual(monthly.monthlyIncome, 18_000)
        XCTAssertEqual(monthly.annualIncome, 216_000)
        XCTAssertEqual(monthly.formulaMonthlyTax, monthly.annualTax.total / 12)
        XCTAssertEqual(
            monthly.pensionProgress,
            IncomeBasisCalculator.publicPensionProgress(
                column: .column1,
                grossYearlyIncome: 216_000
            )
        )
        XCTAssertEqual(
            monthly.sgiProgress,
            IncomeBasisCalculator.estimatedSGIProgress(
                column: .column1,
                grossYearlyIncome: 216_000
            )
        )

        let annual = try XCTUnwrap(
            try TaxCalculation(
                table: 32,
                column: .column3,
                period: .annual,
                income: 420_011
            )
        )
        XCTAssertEqual(annual.monthlyIncome, 35_000)
        XCTAssertEqual(annual.annualIncome, 420_011)
        XCTAssertEqual(
            annual.pensionProgress,
            IncomeBasisCalculator.publicPensionProgress(
                column: .column3,
                grossYearlyIncome: 420_011
            )
        )
        XCTAssertEqual(
            annual.sgiProgress,
            IncomeBasisCalculator.estimatedSGIProgress(
                column: .column3,
                grossYearlyIncome: 420_011
            )
        )

        let zero = try XCTUnwrap(
            try TaxCalculation(
                table: 33,
                column: .column1,
                period: .monthly,
                income: 0
            )
        )
        XCTAssertEqual(zero.tableDeduction, .amount(0))
        XCTAssertEqual(zero.annualTax.total, 0)
        XCTAssertEqual(zero.formulaMonthlyNet, 0)
        XCTAssertEqual(zero.effectiveRate, 0)
    }

    func testPublicPensionProgressUsesPGIAfterTheGeneralPensionFee() {
        XCTAssertEqual(
            IncomeBasisCalculator.publicPensionProgress(
                column: .column1,
                grossYearlyIncome: 510_000
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: 474_300,
                    maximumBasis: IncomeBasisCalculator.maximumPensionableIncome
                )
            )
        )
    }

    func testPublicPensionProgressObservesTheMinimumAndMaximum() {
        XCTAssertEqual(
            IncomeBasisCalculator.publicPensionProgress(
                column: .column1,
                grossYearlyIncome: 25_000
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: 0,
                    maximumBasis: IncomeBasisCalculator.maximumPensionableIncome
                )
            )
        )
        XCTAssertEqual(
            IncomeBasisCalculator.publicPensionProgress(
                column: .column1,
                grossYearlyIncome: 672_600
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: IncomeBasisCalculator.maximumPensionableIncome,
                    maximumBasis: IncomeBasisCalculator.maximumPensionableIncome
                )
            )
        )
        XCTAssertEqual(
            IncomeBasisCalculator.publicPensionProgress(
                column: .column5,
                grossYearlyIncome: 1_000_000
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: IncomeBasisCalculator.maximumPensionableIncome,
                    maximumBasis: IncomeBasisCalculator.maximumPensionableIncome
                )
            )
        )
    }

    func testPublicPensionProgressReportsColumnsThatNeedOtherTreatment() {
        for column in [TaxColumn.column2, .column6] {
            XCTAssertEqual(
                IncomeBasisCalculator.publicPensionProgress(
                    column: column,
                    grossYearlyIncome: 500_000
                ),
                .notBasedOnSelectedIncome
            )
        }
        XCTAssertEqual(
            IncomeBasisCalculator.publicPensionProgress(
                column: .column4,
                grossYearlyIncome: 500_000
            ),
            .requiresAdditionalInformation
        )
    }

    func testEstimatedSGIUsesUnroundedSalaryAndCapsAtTheMaximum() {
        XCTAssertEqual(
            IncomeBasisCalculator.estimatedSGIProgress(
                column: .column1,
                grossYearlyIncome: 14_199
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: 0,
                    maximumBasis: IncomeBasisCalculator.maximumSGI
                )
            )
        )
        XCTAssertEqual(
            IncomeBasisCalculator.estimatedSGIProgress(
                column: .column1,
                grossYearlyIncome: 14_201
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: 14_201,
                    maximumBasis: IncomeBasisCalculator.maximumSGI
                )
            )
        )
        XCTAssertEqual(
            IncomeBasisCalculator.estimatedSGIProgress(
                column: .column3,
                grossYearlyIncome: 700_000
            ),
            .estimated(
                IncomeBasisProgress(
                    estimatedBasis: IncomeBasisCalculator.maximumSGI,
                    maximumBasis: IncomeBasisCalculator.maximumSGI
                )
            )
        )
    }

    func testEstimatedSGIIsNotDerivedFromNonSalaryColumns() {
        for column in [
            TaxColumn.column2,
            .column4,
            .column5,
            .column6
        ] {
            XCTAssertEqual(
                IncomeBasisCalculator.estimatedSGIProgress(
                    column: column,
                    grossYearlyIncome: 500_000
                ),
                .notBasedOnSelectedIncome
            )
        }
    }

    func testIncomeBasisPercentageUsesEstimatedAndMaximumBases() {
        let progress = IncomeBasisProgress(
            estimatedBasis: 296_000,
            maximumBasis: IncomeBasisCalculator.maximumSGI
        )
        XCTAssertEqual(progress.percentOfMaximum, 50)
    }

    func testMonthlyAndAnnualInputsProduceTheSameIncomeBasisProgress() throws {
        let monthly = try XCTUnwrap(
            try TaxCalculation(
                table: 32,
                column: .column1,
                period: .monthly,
                income: 35_000
            )
        )
        let annual = try XCTUnwrap(
            try TaxCalculation(
                table: 32,
                column: .column1,
                period: .annual,
                income: 420_000
            )
        )
        XCTAssertEqual(monthly.pensionProgress, annual.pensionProgress)
        XCTAssertEqual(monthly.sgiProgress, annual.sgiProgress)
    }

    func testIncomeProfilesPreservePureSalaryAndPensionCalculations() {
        let income: UInt32 = 420_000
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 32,
                ageGroup: .under66,
                profile: AnnualIncomeProfile(workIncome: income, pensionIncome: 0)
            ),
            TaxCalculator.calculateAnnualTax(
                table: 32,
                column: .column1,
                grossYearlyIncome: income
            )
        )
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 32,
                ageGroup: .under66,
                profile: AnnualIncomeProfile(workIncome: 0, pensionIncome: income)
            ),
            TaxCalculator.calculateAnnualTax(
                table: 32,
                column: .column6,
                grossYearlyIncome: income
            )
        )
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 32,
                ageGroup: .atLeast66,
                profile: AnnualIncomeProfile(workIncome: income, pensionIncome: 0)
            ),
            TaxCalculator.calculateAnnualTax(
                table: 32,
                column: .column3,
                grossYearlyIncome: income
            )
        )
        XCTAssertEqual(
            TaxCalculator.calculateAnnualTax(
                table: 32,
                ageGroup: .atLeast66,
                profile: AnnualIncomeProfile(workIncome: 0, pensionIncome: income)
            ),
            TaxCalculator.calculateAnnualTax(
                table: 32,
                column: .column2,
                grossYearlyIncome: income
            )
        )
    }

    func testExactDateIncomeAndVacationCompensationMatchRustGUI() {
        var entry = IncomeEntry(id: 1, kind: .monthlySalary)
        entry.amount = 93_000
        entry.end = Date2026(month: 10, day: 18)
        entry.vacationCompensation = VacationCompensation(
            annualEntitlementDays: 30,
            start: entry.start,
            end: entry.end
        )

        XCTAssertEqual(entry.amount(forMonth: 9), 93_000)
        XCTAssertEqual(entry.amount(forMonth: 10), 54_000)
        XCTAssertEqual(entry.amount(forMonth: 11), 0)
        XCTAssertEqual(entry.annualAmount, 891_000)
        XCTAssertEqual(entry.vacationCompensation?.payoutDays, 24)
        XCTAssertEqual(entry.vacationCompensationAmount, 115_883)
        XCTAssertEqual(entry.vacationPensionPremiumAmount, 34_765)
        XCTAssertEqual(entry.pensionSalaryBasisAmount, 1_006_883)
    }

    func testChangingVacationEntitlementRecomputesRustSuggestedDays() {
        var entry = IncomeEntry(id: 1, kind: .monthlySalary)
        entry.amount = 93_000
        entry.end = Date2026(month: 10, day: 18)

        entry.setVacationAnnualEntitlementDays(25)
        XCTAssertEqual(entry.vacationCompensation?.payoutDays, 20)

        entry.setVacationAnnualEntitlementDays(30)
        XCTAssertEqual(entry.vacationCompensation?.payoutDays, 24)
        XCTAssertEqual(entry.vacationCompensationAmount, 115_883)
        XCTAssertEqual(entry.vacationPensionPremiumAmount, 34_765)
    }

    func testTypicalJämkningVacationAndOneTimeSalaryScenarioMatchesRustGUI() throws {
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

        let totals = plan.totals
        XCTAssertEqual(plan.entries[0].annualAmount, 891_000)
        XCTAssertEqual(plan.entries[0].vacationCompensation?.payoutDays, 24)
        XCTAssertEqual(plan.entries[0].vacationCompensationAmount, 115_883)
        XCTAssertEqual(totals.workIncome, 1_378_883)
        XCTAssertEqual(totals.regularPensionPremiums, 139_954)
        XCTAssertEqual(totals.vacationPensionPremiums, 34_765)
        XCTAssertEqual(totals.totalEmployerPensionContributions, 174_719)

        let withholding = try plan.estimatedWithholding(table: 32, ageGroup: .under66)
        XCTAssertEqual(withholding.entries[0].gross, 1_006_883)
        XCTAssertEqual(withholding.entries[0].withheld, 332_271)
        XCTAssertEqual(withholding.entries[0].rule, .adjustmentPercent(33))
        XCTAssertEqual(withholding.entries[1].gross, 372_000)
        XCTAssertEqual(withholding.entries[1].withheld, 122_760)
        XCTAssertEqual(withholding.entries[1].rule, .adjustmentPercent(33))
        XCTAssertEqual(withholding.total, 455_031)

        let calculation = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
        )
        let calibration = try XCTUnwrap(calculation.adjustmentCalibration)
        XCTAssertEqual(calibration.basisIncome, 1_116_000)
        XCTAssertEqual(calibration.formulaTaxAtBasis, 392_457)
        XCTAssertEqual(calibration.assumedTaxAtBasis, 368_280)
        XCTAssertEqual(calibration.impliedTaxAdjustment, 24_177)
        XCTAssertEqual(calculation.monthlyIncome, 114_906)
        XCTAssertEqual(calculation.annualIncome, 1_378_883)
        XCTAssertEqual(calculation.tableDeduction, .percent(38))
        XCTAssertEqual(calculation.annualTax.total, 529_113)
        XCTAssertEqual(calculation.totalTax, 504_936)
        XCTAssertEqual(calculation.withheldTax, 455_031)
        XCTAssertEqual(calculation.cashAfterWithholding, 923_852)
        XCTAssertEqual(calculation.annualNet, 873_947)
        XCTAssertEqual(calculation.taxBalance, 49_905)
        XCTAssertEqual(calculation.marginalRate, 52)
    }

    func testTypicalScenarioPlusSecondaryTjänstepensionMatchesRustGUI() throws {
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

        let totals = plan.totals
        XCTAssertEqual(totals.workIncome, 1_378_883)
        XCTAssertEqual(totals.pensionIncome, 137_500)
        XCTAssertEqual(totals.ordinaryIncome, 1_516_383)
        XCTAssertEqual(totals.adjustmentBasisWorkIncome, 1_116_000)
        XCTAssertEqual(totals.totalEmployerPensionContributions, 174_719)

        let withholding = try plan.estimatedWithholding(table: 32, ageGroup: .under66)
        XCTAssertEqual(withholding.entries[0].withheld, 332_271)
        XCTAssertEqual(withholding.entries[0].rule, .adjustmentPercent(33))
        XCTAssertEqual(withholding.entries[1].withheld, 122_760)
        XCTAssertEqual(withholding.entries[1].rule, .adjustmentPercent(33))
        XCTAssertEqual(withholding.entries[2].gross, 137_500)
        XCTAssertEqual(withholding.entries[2].withheld, 41_250)
        XCTAssertEqual(withholding.entries[2].rule, .secondary30)
        XCTAssertEqual(withholding.total, 496_281)

        let calculation = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
        )
        let calibration = try XCTUnwrap(calculation.adjustmentCalibration)
        XCTAssertEqual(calibration.basisIncome, 1_116_000)
        XCTAssertEqual(calibration.formulaTaxAtBasis, 392_457)
        XCTAssertEqual(calibration.assumedTaxAtBasis, 368_280)
        XCTAssertEqual(calibration.impliedTaxAdjustment, 24_177)
        XCTAssertEqual(calculation.monthlyIncome, 126_365)
        XCTAssertEqual(calculation.annualIncome, 1_516_383)
        XCTAssertEqual(calculation.annualTax.total, 600_613)
        XCTAssertEqual(calculation.ordinaryFinalTax, 576_436)
        XCTAssertEqual(calculation.totalTax, 576_436)
        XCTAssertEqual(calculation.withheldTax, 496_281)
        XCTAssertEqual(calculation.cashAfterWithholding, 1_020_102)
        XCTAssertEqual(calculation.annualNet, 939_947)
        XCTAssertEqual(calculation.taxBalance, 80_155)
        XCTAssertEqual(calculation.marginalRate, 52)
    }

    func testPensionBenchmarkAndSalaryExchangeMatchRustGUI() throws {
        XCTAssertEqual(RegularPensionPremium.benchmarkMonthly(93_000), 14_608)

        var plan = IncomePlan(monthlySalary: 93_000)
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].vacationCompensation = VacationCompensation(
            annualEntitlementDays: 30,
            start: plan.entries[0].start,
            end: plan.entries[0].end
        )
        let lumpID = plan.addEntry(kind: .oneTimeSalary)
        let lumpIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == lumpID })
        plan.entries[lumpIndex].amount = 372_000
        plan.entries[lumpIndex].salaryExchange = SalaryExchange()

        let allowance = try XCTUnwrap(plan.salaryExchangeAllowance(for: lumpID))
        XCTAssertEqual(allowance.pensionSalaryBasisBefore, 1_006_883)
        XCTAssertEqual(allowance.ceiling, 352_409)
        XCTAssertEqual(allowance.regularPensionPremiums, 139_954)
        XCTAssertEqual(allowance.vacationPensionPremiums, 34_765)
        XCTAssertEqual(allowance.availableContribution, 177_690)
        XCTAssertEqual(allowance.maximumSacrifice, 168_012)

        plan.entries[lumpIndex].salaryExchange?.sacrificedSalary = allowance.maximumSacrifice
        let totals = plan.totals
        XCTAssertEqual(totals.workIncome, 1_210_871)
        XCTAssertEqual(totals.salaryExchangeSacrifice, 168_012)
        XCTAssertEqual(totals.salaryExchangePensionContributions, 177_689)
        XCTAssertEqual(totals.totalEmployerPensionContributions, 352_408)
    }

    func testSalaryExchangeIsInvalidatedWhenOtherPensionContributionsIncrease() throws {
        var plan = IncomePlan(annualSalary: 1_000_000)
        let lumpID = plan.addEntry(kind: .oneTimeSalary)
        let lumpIndex = try XCTUnwrap(plan.entries.firstIndex { $0.id == lumpID })
        plan.entries[lumpIndex].amount = 300_000
        plan.entries[lumpIndex].salaryExchange = SalaryExchange()

        let originalMaximum = try XCTUnwrap(
            plan.salaryExchangeAllowance(for: lumpID)?.maximumSacrifice
        )
        XCTAssertGreaterThan(originalMaximum, 0)
        plan.entries[lumpIndex].salaryExchange?.sacrificedSalary = originalMaximum
        XCTAssertNil(plan.validationIssue)

        plan.entries[0].regularPensionPremium?.monthlyOverride = 25_000
        let reducedMaximum = try XCTUnwrap(
            plan.salaryExchangeAllowance(for: lumpID)?.maximumSacrifice
        )
        XCTAssertLessThan(reducedMaximum, originalMaximum)
        XCTAssertEqual(
            plan.validationIssue,
            .salaryExchangeExceedsAllowance(entryID: lumpID, maximum: reducedMaximum)
        )
        XCTAssertNil(try PlanCalculation(table: 32, ageGroup: .under66, plan: plan))
    }

    func testWithholdingRulesAndAdditionalAmountCompose() throws {
        var plan = IncomePlan(annualSalary: 700_000)
        let pensionID = plan.addEntry(kind: .annualOccupationalPension)
        let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == pensionID })
        plan.entries[index].amount = 100_000
        plan.entries[index].payerRole = .secondary

        var row = try XCTUnwrap(
            try plan.estimatedWithholding(table: 32, ageGroup: .under66)
                .entries.first { $0.entryID == pensionID }
        )
        XCTAssertEqual(row.withheld, 30_000)
        XCTAssertEqual(row.rule, .secondary30)

        plan.adjustmentPercent = 38
        plan.entries[index].adjustmentApplies = true
        row = try XCTUnwrap(
            try plan.estimatedWithholding(table: 32, ageGroup: .under66)
                .entries.first { $0.entryID == pensionID }
        )
        XCTAssertEqual(row.withheld, 38_000)
        XCTAssertEqual(row.rule, .adjustmentPercent(38))

        plan.entries[index].additionalWithholdingPerPayment = 500
        row = try XCTUnwrap(
            try plan.estimatedWithholding(table: 32, ageGroup: .under66)
                .entries.first { $0.entryID == pensionID }
        )
        XCTAssertEqual(row.withheld, 44_000)
        XCTAssertEqual(row.additionalWithheld, 6_000)
        XCTAssertEqual(row.rule, .adjustmentPercent(38))
    }

    func testAdditionalWithholdingUsesPaymentCountAndCannotExceedGross() throws {
        var annualPlan = IncomePlan(annualSalary: 600_000)
        let annualBaseline = try XCTUnwrap(
            try annualPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        annualPlan.entries[0].additionalWithholdingPerPayment = 1_000
        let annualWithExtra = try XCTUnwrap(
            try annualPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        XCTAssertEqual(annualPlan.entries[0].withholdingPaymentCount, 12)
        XCTAssertEqual(annualWithExtra.additionalWithheld, 12_000)
        XCTAssertEqual(annualWithExtra.withheld, annualBaseline.withheld + 12_000)

        var periodPlan = IncomePlan(monthlySalary: 40_000)
        periodPlan.entries[0].start = Date2026(month: 3, day: 15)
        periodPlan.entries[0].end = Date2026(month: 5, day: 10)
        let periodBaseline = try XCTUnwrap(
            try periodPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        periodPlan.entries[0].additionalWithholdingPerPayment = 750
        let periodWithExtra = try XCTUnwrap(
            try periodPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        XCTAssertEqual(periodPlan.entries[0].withholdingPaymentCount, 3)
        XCTAssertEqual(periodWithExtra.additionalWithheld, 2_250)
        XCTAssertEqual(periodWithExtra.withheld, periodBaseline.withheld + 2_250)

        var cappedPlan = IncomePlan(annualSalary: 12_000)
        let cappedBaseline = try XCTUnwrap(
            try cappedPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        cappedPlan.entries[0].additionalWithholdingPerPayment = 10_000
        let capped = try XCTUnwrap(
            try cappedPlan.estimatedWithholding(table: 32, ageGroup: .under66).entries.first
        )
        XCTAssertEqual(capped.withheld, capped.gross)
        XCTAssertEqual(
            capped.additionalWithheld,
            capped.gross.saturatingSubtract(cappedBaseline.withheld)
        )
    }

    func testActualWithholdingOverridesEveryIncomeKind() throws {
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

        let withholding = try plan.estimatedWithholding(table: 32, ageGroup: .under66)

        XCTAssertEqual(withholding.entries.count, IncomeKind.allCases.count)
        for (index, row) in withholding.entries.enumerated() {
            XCTAssertEqual(row.withheld, UInt32(10_000 + index))
            XCTAssertEqual(row.regularWithheld, row.withheld)
            XCTAssertEqual(row.supplementalWithheld, 0)
            XCTAssertEqual(row.additionalWithheld, 0)
            XCTAssertEqual(row.rule, .actualAmount)
        }
    }

    func testPreliminary2027DividendAllowanceMatchesRust() throws {
        var plan = IncomePlan(monthlySalary: 50_000)
        plan.entries[0].ownCompanySourced = true

        let baseline = try plan.dividendAllowance2027()
        XCTAssertEqual(baseline.ownerCashSalary, 600_000)
        XCTAssertEqual(baseline.companyCashPayroll, 600_000)
        XCTAssertEqual(baseline.total, 333_600)

        plan.entries[0].kind = .annualSalary
        plan.entries[0].amount = 800_000
        let wageBased = try plan.dividendAllowance2027()
        XCTAssertEqual(wageBased.jointWageBasisAfterDeduction, 132_800)
        XCTAssertEqual(wageBased.wageAllowance, 66_400)
        XCTAssertEqual(wageBased.total, 400_000)
    }

    func testPreliminary2027OwnershipAllocationFollowsSkatteverketWorkedExamples() throws {
        // Skatteverket's Gunnar/Rita, Ismail, and Tove examples for income year 2026:
        // https://www.skatteverket.se/foretag/drivaforetag/foretagsformer/famansforetag/andradereglerfordelagareifamansforetaginforinkomstdeklarationen2027.4.4a54dc8b19aa6175a152359.html
        // The app projects income year 2027, so the same published allocation formula
        // uses the official 2026 income-base amount: 4 × 83,400 = 333,600 SEK.
        var inputs = DividendAllowanceInputs2027()
        inputs.ownershipBasisPoints = 5_000
        XCTAssertEqual(try inputs.calculate(ownerCashSalary2026: 0).basicAmount, 166_800)

        inputs.ownershipBasisPoints = 2_500
        inputs.otherQualifiedOwnershipBasisPoints = 3_300
        XCTAssertEqual(try inputs.calculate(ownerCashSalary2026: 0).basicAmount, 83_400)

        inputs.otherQualifiedOwnershipBasisPoints = 17_500
        XCTAssertEqual(try inputs.calculate(ownerCashSalary2026: 0).basicAmount, 41_700)
    }

    func testPreliminary2027WageAllowanceFollowsSkatteverketWorkedExamples() throws {
        // Mirrors Skatteverket's Agnes/Birger and Amy/Gedion examples with the
        // income-year-2027 deduction: 8 × the official 2026 IBB = 667,200 SEK.
        var agnes = DividendAllowanceInputs2027()
        agnes.onePersonCompany = false
        agnes.ownershipBasisPoints = 7_000
        agnes.companyCashPayroll2026 = 4_000_000
        let agnesResult = try agnes.calculate(ownerCashSalary2026: 400_000)
        XCTAssertEqual(agnesResult.jointWageBasis, 2_800_000)
        XCTAssertEqual(agnesResult.jointWageBasisAfterDeduction, 2_132_800)
        XCTAssertEqual(agnesResult.wageAllowance, 1_066_400)

        var birger = agnes
        birger.ownershipBasisPoints = 3_000
        let birgerResult = try birger.calculate(ownerCashSalary2026: 300_000)
        XCTAssertEqual(birgerResult.jointWageBasis, 1_200_000)
        XCTAssertEqual(birgerResult.jointWageBasisAfterDeduction, 532_800)
        XCTAssertEqual(birgerResult.wageAllowance, 266_400)

        var amy = agnes
        amy.ownershipBasisPoints = 6_000
        amy.spouseOwnershipBasisPoints = 4_000
        amy.highestRelatedCashSalary2026 = 300_000
        XCTAssertEqual(try amy.calculate(ownerCashSalary2026: 500_000).wageAllowance, 999_840)

        var gedion = amy
        gedion.ownershipBasisPoints = 4_000
        gedion.spouseOwnershipBasisPoints = 6_000
        gedion.highestRelatedCashSalary2026 = 500_000
        XCTAssertEqual(try gedion.calculate(ownerCashSalary2026: 300_000).wageAllowance, 666_560)
    }

    func testPreliminary2027AllowanceFollowsSkatteverketValterAndHelleExamples() throws {
        // Valter's published total remains 1,250,000 SEK when rolled forward:
        // the 11,200 SEK higher basic amount is offset by an 11,200 SEK lower
        // wage allowance under the eight-IBB deduction.
        var valter = DividendAllowanceInputs2027()
        valter.onePersonCompany = false
        valter.companyCashPayroll2026 = 1_000_000
        valter.acquisitionCost = 25_000
        valter.savedAllowance = 750_000
        let valterResult = try valter.calculate(ownerCashSalary2026: 600_000)
        XCTAssertEqual(valterResult.basicAmount, 333_600)
        XCTAssertEqual(valterResult.wageAllowance, 166_400)
        XCTAssertEqual(valterResult.acquisitionCostInterest, 0)
        XCTAssertEqual(valterResult.total, 1_250_000)
        XCTAssertEqual(valterResult.taxAtTwentyPercent, 250_000)
        XCTAssertEqual(valterResult.netAfterTwentyPercentTax, 1_000_000)

        // Helle's official example uses 11.55% on the acquisition-cost portion
        // above 100,000 SEK: 150,000 × 11.55% = 17,325 SEK.
        var helle = DividendAllowanceInputs2027()
        helle.acquisitionCost = 250_000
        helle.acquisitionCostInterestBasisPoints = 1_155
        let helleResult = try helle.calculate(ownerCashSalary2026: 0)
        XCTAssertEqual(helleResult.acquisitionCostInterestBasis, 150_000)
        XCTAssertEqual(helleResult.acquisitionCostInterest, 17_325)
    }

    func testQualifiedDividendTaxMatchesSkatteverketParisaExample() throws {
        // Skatteverket: 78,000 SEK within the allowance produces 15,600 SEK tax.
        // https://www.skatteverket.se/foretag/drivaforetag/foretagsformer/famansforetag/raknautskattenpadinutdelning.4.b1014b415f3321c0de27ce.html
        var plan = IncomePlan(annualSalary: 420_000)
        let dividendID = plan.addEntry(kind: .ownCompanyDividend)
        let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == dividendID })
        plan.entries[index].amount = 78_000

        let calculation = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
        )
        XCTAssertEqual(calculation.dividendTax, 15_600)
        XCTAssertEqual(plan.entries[index].amount - calculation.dividendTax, 62_400)
    }

    func testPersistedPlanWithoutNewParityFieldsStillDecodes() throws {
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

    func testFullYearAdjustmentCalibrationMatchesRustGUI() throws {
        var plan = IncomePlan(monthlySalary: 93_000)
        plan.adjustmentPercent = 33
        plan.entries[0].end = Date2026(month: 10, day: 18)
        plan.entries[0].adjustmentApplies = true
        plan.entries[0].useFullYearProjectionAsAdjustmentBasis = true

        let calculation = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
        )
        let calibration = try XCTUnwrap(calculation.adjustmentCalibration)
        XCTAssertEqual(calibration.basisIncome, 1_116_000)
        XCTAssertEqual(calibration.assumedTaxAtBasis, 368_280)
        XCTAssertEqual(calibration.formulaTaxAtBasis, 392_457)
        XCTAssertEqual(calibration.impliedTaxAdjustment, 24_177)
        XCTAssertEqual(calculation.annualTax.total, 275_457)
        XCTAssertEqual(calculation.ordinaryFinalTax, 251_280)
        XCTAssertEqual(calculation.withheldTax, 294_030)
        XCTAssertEqual(calculation.taxBalance, -42_750)
    }

    func testFullYearAdjustmentCalibrationAnchorsProjectionAtZeroBalance() throws {
        var projectedPlan = IncomePlan(monthlySalary: 93_000)
        projectedPlan.adjustmentPercent = 33
        projectedPlan.entries[0].adjustmentApplies = true
        projectedPlan.entries[0].useFullYearProjectionAsAdjustmentBasis = true

        let projected = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: projectedPlan)
        )
        let calibration = try XCTUnwrap(projected.adjustmentCalibration)
        XCTAssertEqual(projected.annualIncome, calibration.basisIncome)
        XCTAssertEqual(projected.ordinaryFinalTax, calibration.assumedTaxAtBasis)
        XCTAssertEqual(projected.withheldTax, calibration.assumedTaxAtBasis)
        XCTAssertEqual(projected.taxBalance, 0)

        var actualPlan = projectedPlan
        actualPlan.entries[0].end = Date2026(month: 10, day: 18)
        let actual = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: actualPlan)
        )
        let formulaChange = Int64(actual.annualTax.total)
            - Int64(calibration.formulaTaxAtBasis)
        let withholdingChange = Int64(actual.withheldTax)
            - Int64(calibration.assumedTaxAtBasis)
        XCTAssertEqual(actual.taxBalance, formulaChange - withholdingChange)
        XCTAssertEqual(actual.taxBalance, -42_750)
    }

    func testDividendAddsFinalTaxWithoutWithholding() throws {
        var plan = IncomePlan(annualSalary: 420_000)
        let dividendID = plan.addEntry(kind: .ownCompanyDividend)
        let index = try XCTUnwrap(plan.entries.firstIndex { $0.id == dividendID })
        plan.entries[index].amount = 200_000

        let calculation = try XCTUnwrap(
            try PlanCalculation(table: 32, ageGroup: .under66, plan: plan)
        )
        XCTAssertEqual(calculation.annualIncome, 620_000)
        XCTAssertEqual(calculation.dividendTax, 40_000)
        XCTAssertEqual(calculation.totalTax, calculation.annualTax.total + 40_000)
        XCTAssertEqual(
            calculation.withheldTax,
            try IncomePlan(annualSalary: 420_000)
                .estimatedWithholding(table: 32, ageGroup: .under66).total
        )
    }

    func testOneTimeWithholdingTableMatchesOfficialBoundaries() {
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 25_041), 0)
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 25_042), 10)
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 82_800), 10)
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 82_801), 21)
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 660_000), 34)
        XCTAssertEqual(oneTimeWithholdingRate(column: .column1, annualIncome: 660_001), 54)
    }

    private func deduction(
        _ table: UInt8,
        _ column: TaxColumn,
        _ income: UInt32
    ) -> TaxDeduction? {
        try? TaxCalculator.monthlyDeduction(
            table: table,
            column: column,
            grossMonthlyIncome: income
        )
    }

    private func findGrossIncome(
        table: UInt8,
        column: TaxColumn,
        taxableBreakpoint: UInt32
    ) -> UInt32 {
        for grossIncome in stride(from: UInt32(0), through: 1_000_000, by: 100) {
            if let tax = TaxCalculator.calculateAnnualTax(
                table: table,
                column: column,
                grossYearlyIncome: grossIncome
            ), tax.taxableIncome >= taxableBreakpoint {
                return grossIncome
            }
        }
        XCTFail("Taxable breakpoint \(taxableBreakpoint) was not reached")
        return 0
    }

    private func assertFormulaTransition(
        table: UInt8,
        column: TaxColumn,
        breakpoint: UInt32
    ) throws {
        let transition = (breakpoint + 99) / 100 * 100
        let before = try XCTUnwrap(TaxCalculator.calculateAnnualTax(
            table: table,
            column: column,
            grossYearlyIncome: transition - 100
        ))
        let at = try XCTUnwrap(TaxCalculator.calculateAnnualTax(
            table: table,
            column: column,
            grossYearlyIncome: transition
        ))
        let after = try XCTUnwrap(TaxCalculator.calculateAnnualTax(
            table: table,
            column: column,
            grossYearlyIncome: transition + 100
        ))
        XCTAssertLessThanOrEqual(before.total, before.assessedIncome)
        XCTAssertLessThanOrEqual(at.total, at.assessedIncome)
        XCTAssertLessThanOrEqual(after.total, after.assessedIncome)

        let monthlyIncome = (transition > 6_000 ? transition - 6_000 : 0) / 12
        let lowerAnnualIncome = monthlyIncome * 12
        let upperAnnualIncome = (monthlyIncome + 1_000) * 12
        XCTAssertLessThanOrEqual(lowerAnnualIncome, transition)
        XCTAssertLessThanOrEqual(transition, upperAnnualIncome)

        let lowerTax = try XCTUnwrap(TaxCalculator.calculateAnnualTax(
            table: table,
            column: column,
            grossYearlyIncome: lowerAnnualIncome
        ))
        let upperTax = try XCTUnwrap(TaxCalculator.calculateAnnualTax(
            table: table,
            column: column,
            grossYearlyIncome: upperAnnualIncome
        ))
        let expected = Double(Int64(upperTax.total) - Int64(lowerTax.total)) * 100
            / Double(upperAnnualIncome - lowerAnnualIncome)
        let actual = try XCTUnwrap(TaxCalculator.calculateMarginalRate(
            table: table,
            column: column,
            monthlyIncome: monthlyIncome
        ))
        XCTAssertEqual(actual, expected)
        XCTAssertGreaterThanOrEqual(actual, 0)
        XCTAssertLessThanOrEqual(actual, 100)
    }
}
