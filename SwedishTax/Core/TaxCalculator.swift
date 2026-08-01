import Foundation

private enum WorkCreditKind {
    case none
    case under66
    case over66
}

private struct AnnualTaxBases {
    var grossIncome: UInt32
    var pensionFeeIncome: UInt32 = 0
    var workIncome: UInt32 = 0
    var enhancedAllowance = false
    var workCredit: WorkCreditKind = .none
    var hasSicknessCredit = false
}

enum TaxCalculator {
    static let minTaxTable: UInt8 = 29
    static let maxTaxTable: UInt8 = 42

    private static let priceBaseAmount: UInt32 = 59_200
    private static let stateTaxThreshold: UInt32 = 643_000
    private static let burialAndReligiousRate: UInt32 = 116
    private static let publicServiceFeeMaximum: UInt32 = 1_184
    private static let marginalIncomeInterval: UInt32 = 1_000
    private static let scale: UInt128 = 100_000_000

    static func monthlyDeduction(
        table: UInt8,
        column: TaxColumn,
        grossMonthlyIncome: UInt32
    ) -> TaxDeduction? {
        guard let rows = TaxTables.rows(for: table) else { return nil }
        guard grossMonthlyIncome != 0 else { return .amount(0) }

        var low = 0
        var high = rows.count - 1
        while low <= high {
            let middle = low + (high - low) / 2
            let row = rows[middle]
            if grossMonthlyIncome < row.minimum {
                high = middle - 1
            } else if grossMonthlyIncome > row.maximum {
                low = middle + 1
            } else {
                let value = row.values[column.index]
                return row.kind == .amount ? .amount(value) : .percent(value)
            }
        }
        return nil
    }

    static func calculateAnnualTax(
        table: UInt8,
        column: TaxColumn,
        grossYearlyIncome: UInt32
    ) -> AnnualTax? {
        let bases: AnnualTaxBases
        switch column {
        case .column1:
            bases = AnnualTaxBases(
                grossIncome: grossYearlyIncome,
                pensionFeeIncome: grossYearlyIncome,
                workIncome: grossYearlyIncome,
                enhancedAllowance: false,
                workCredit: .under66,
                hasSicknessCredit: false
            )
        case .column2:
            bases = AnnualTaxBases(
                grossIncome: grossYearlyIncome,
                enhancedAllowance: true
            )
        case .column3:
            bases = AnnualTaxBases(
                grossIncome: grossYearlyIncome,
                pensionFeeIncome: grossYearlyIncome,
                workIncome: grossYearlyIncome,
                enhancedAllowance: true,
                workCredit: .over66,
                hasSicknessCredit: false
            )
        case .column4:
            bases = AnnualTaxBases(
                grossIncome: grossYearlyIncome,
                hasSicknessCredit: true
            )
        case .column5:
            bases = AnnualTaxBases(
                grossIncome: grossYearlyIncome,
                pensionFeeIncome: grossYearlyIncome
            )
        case .column6:
            bases = AnnualTaxBases(grossIncome: grossYearlyIncome)
        }
        return calculateAnnualTax(table: table, bases: bases)
    }

    static func calculateAnnualTax(
        table: UInt8,
        ageGroup: TaxAgeGroup,
        profile: AnnualIncomeProfile
    ) -> AnnualTax? {
        calculateAnnualTax(
            table: table,
            bases: AnnualTaxBases(
                grossIncome: profile.total,
                pensionFeeIncome: profile.workIncome,
                workIncome: profile.workIncome,
                enhancedAllowance: ageGroup == .atLeast66,
                workCredit: ageGroup == .under66 ? .under66 : .over66,
                hasSicknessCredit: false
            )
        )
    }

    private static func calculateAnnualTax(
        table: UInt8,
        bases: AnnualTaxBases
    ) -> AnnualTax? {
        guard (minTaxTable...maxTaxTable).contains(table) else { return nil }

        let assessedIncome = roundDownHundred(bases.grossIncome)
        let assessedWorkIncome = roundDownHundred(min(bases.workIncome, assessedIncome))
        let assessedPensionFeeIncome = roundDownHundred(
            min(bases.pensionFeeIncome, assessedIncome)
        )
        let basicAllowance = basicAllowance(
            assessedIncome,
            enhanced: bases.enhancedAllowance
        )
        let taxableIncome = saturatingSubtract(assessedIncome, basicAllowance)

        let stateIncomeTax: UInt32 = taxableIncome >= stateTaxThreshold + 200
            ? percentageFloor(taxableIncome - stateTaxThreshold, 20, 100)
            : 0
        let municipalRate = UInt32(table) * 100 - burialAndReligiousRate
        let municipalIncomeTax = percentageFloor(taxableIncome, municipalRate, 10_000)
        let burialAndReligiousFee = percentageFloor(
            taxableIncome,
            burialAndReligiousRate,
            10_000
        )
        let pensionFee = pensionFee(assessedPensionFeeIncome)
        let publicServiceFee = min(taxableIncome / 100, publicServiceFeeMaximum)

        let pensionFeeCredit = min(
            pensionFee,
            UInt32(UInt64(stateIncomeTax) + UInt64(municipalIncomeTax))
        )
        let pensionCreditAgainstMunicipal = saturatingSubtract(
            pensionFeeCredit,
            stateIncomeTax
        )
        var municipalTaxLeft = saturatingSubtract(
            municipalIncomeTax,
            pensionCreditAgainstMunicipal
        )

        let calculatedWorkCredit: UInt32
        switch bases.workCredit {
        case .under66:
            calculatedWorkCredit = workIncomeCreditUnder66(
                assessedWorkIncome,
                allowance: basicAllowance,
                municipalRate: municipalRate
            )
        case .over66:
            calculatedWorkCredit = workIncomeCreditOver66(assessedWorkIncome)
        case .none:
            calculatedWorkCredit = 0
        }
        let workIncomeCredit = min(calculatedWorkCredit, municipalTaxLeft)
        municipalTaxLeft -= workIncomeCredit

        let calculatedSicknessCredit = bases.hasSicknessCredit
            ? sicknessCompensationCredit(
                assessedIncome,
                allowance: basicAllowance,
                municipalRate: municipalRate
            )
            : 0
        let sicknessCompensationCredit = min(calculatedSicknessCredit, municipalTaxLeft)
        municipalTaxLeft -= sicknessCompensationCredit

        let calculatedEarnedCredit: UInt32
        switch taxableIncome {
        case ...40_000:
            calculatedEarnedCredit = 0
        case ...240_000:
            calculatedEarnedCredit = percentageFloor(taxableIncome - 40_000, 75, 10_000)
        default:
            calculatedEarnedCredit = 1_500
        }
        let earnedIncomeCredit = min(calculatedEarnedCredit, municipalTaxLeft)

        let additions = UInt64(stateIncomeTax)
            + UInt64(municipalIncomeTax)
            + UInt64(burialAndReligiousFee)
            + UInt64(pensionFee)
            + UInt64(publicServiceFee)
        let credits = UInt64(pensionFeeCredit)
            + UInt64(workIncomeCredit)
            + UInt64(sicknessCompensationCredit)
            + UInt64(earnedIncomeCredit)
        guard let total = UInt32(exactly: additions - credits) else { return nil }

        return AnnualTax(
            assessedIncome: assessedIncome,
            basicAllowance: basicAllowance,
            taxableIncome: taxableIncome,
            stateIncomeTax: stateIncomeTax,
            municipalIncomeTax: municipalIncomeTax,
            burialAndReligiousFee: burialAndReligiousFee,
            pensionFee: pensionFee,
            pensionFeeCredit: pensionFeeCredit,
            workIncomeCredit: workIncomeCredit,
            sicknessCompensationCredit: sicknessCompensationCredit,
            earnedIncomeCredit: earnedIncomeCredit,
            publicServiceFee: publicServiceFee,
            total: total
        )
    }

    static func calculateMarginalRate(
        table: UInt8,
        column: TaxColumn,
        monthlyIncome: UInt32
    ) -> Double? {
        let (upperIncome, additionOverflow) = monthlyIncome.addingReportingOverflow(
            marginalIncomeInterval
        )
        guard !additionOverflow else { return nil }

        let lowerAnnual = UInt64(monthlyIncome) * 12
        let upperAnnual = UInt64(upperIncome) * 12
        guard upperAnnual <= UInt32.max else { return nil }
        guard
            let lowerTax = calculateAnnualTax(
                table: table,
                column: column,
                grossYearlyIncome: UInt32(lowerAnnual)
            ),
            let upperTax = calculateAnnualTax(
                table: table,
                column: column,
                grossYearlyIncome: UInt32(upperAnnual)
            )
        else { return nil }

        let difference = Int64(upperTax.total) - Int64(lowerTax.total)
        return Double(difference) * 100 / Double(upperAnnual - lowerAnnual)
    }

    static func roundDownHundred(_ value: UInt32) -> UInt32 {
        value / 100 * 100
    }

    private static func basicAllowance(_ income: UInt32, enhanced: Bool) -> UInt32 {
        let ordinary = ordinaryBasicAllowanceScaled(income)
        let raw = enhanced ? ordinary + enhancedBasicAllowancePartScaled(income) : ordinary
        return roundScaledUpToHundred(min(raw, scaled(income)))
    }

    private static func ordinaryBasicAllowanceScaled(_ income: UInt32) -> UInt128 {
        switch income {
        case ...58_608:
            pbb(423, 1_000)
        case ...161_024:
            pbb(423, 1_000) + ratio(scaled(income - 58_608), 20, 100)
        case ...184_112:
            pbb(77, 100)
        case ...466_496:
            pbb(77, 100) - ratio(scaled(income - 184_112), 10, 100)
        default:
            pbb(293, 1_000)
        }
    }

    private static func enhancedBasicAllowancePartScaled(_ income: UInt32) -> UInt128 {
        switch income {
        case ...53_872:
            pbb(687, 1_000)
        case ...65_712:
            pbb(885, 1_000) - ratio(scaled(income), 20, 100)
        case ...116_328:
            pbb(600, 1_000) + ratio(scaled(income), 57, 1_000)
        case ...161_024:
            pbb(333, 1_000) + ratio(scaled(income), 1_949, 10_000)
        case ...184_112:
            ratio(scaled(income), 3_949, 10_000) - pbb(212, 1_000)
        case ...191_808:
            ratio(scaled(income), 4_949, 10_000) - pbb(523, 1_000)
        case ...296_000:
            ratio(scaled(income), 356, 1_000) - pbb(73, 1_000)
        case ...466_496:
            pbb(17, 1_000) + ratio(scaled(income), 338, 1_000)
        case ...478_336:
            pbb(703, 1_000) + ratio(scaled(income), 251, 1_000)
        case ...660_672:
            pbb(2_732, 1_000)
        case ...760_128:
            pbb(9_651, 1_000) - ratio(scaled(income), 62, 100)
        default:
            pbb(1_691, 1_000)
        }
    }

    static func pensionFee(_ income: UInt32) -> UInt32 {
        guard income >= IncomeBasisCalculator.minimumPensionableIncome else { return 0 }
        let raw = ratio(
            scaled(min(income, IncomeBasisCalculator.generalPensionFeeIncomeCeiling)),
            7,
            100
        )
        return UInt32((raw + 50 * scale - 1) / (100 * scale) * 100)
    }

    private static func workIncomeCreditUnder66(
        _ income: UInt32,
        allowance: UInt32,
        municipalRate: UInt32
    ) -> UInt32 {
        let beforeAllowance: UInt128
        switch income {
        case ...53_872:
            beforeAllowance = scaled(income)
        case ...191_808:
            beforeAllowance = pbb(91, 100)
                + ratio(scaled(income - 53_872), 3_874, 10_000)
        case ...478_336:
            beforeAllowance = pbb(1_813, 1_000)
                + ratio(scaled(income - 191_808), 251, 1_000)
        default:
            beforeAllowance = pbb(3_027, 1_000)
        }
        let allowanceScaled = scaled(allowance)
        let base = beforeAllowance > allowanceScaled ? beforeAllowance - allowanceScaled : 0
        return scaledPercentageFloor(base, municipalRate, 10_000)
    }

    private static func workIncomeCreditOver66(_ income: UInt32) -> UInt32 {
        let credit: UInt128
        switch income {
        case ...103_600:
            credit = ratio(scaled(income), 22, 100)
        case ...310_208:
            credit = pbb(2_635, 10_000) + ratio(scaled(income), 7, 100)
        default:
            credit = pbb(6_293, 10_000)
        }
        return UInt32(credit / scale)
    }

    private static func sicknessCompensationCredit(
        _ income: UInt32,
        allowance: UInt32,
        municipalRate: UInt32
    ) -> UInt32 {
        let beforeAllowance: UInt128
        switch income {
        case ...53_872:
            beforeAllowance = scaled(income)
        case ...191_808:
            beforeAllowance = pbb(91, 100)
                + ratio(scaled(income - 53_872), 3_874, 10_000)
        default:
            beforeAllowance = pbb(1_813, 1_000)
                + ratio(scaled(income - 191_808), 251, 1_000)
        }
        let allowanceScaled = scaled(allowance)
        let base = beforeAllowance > allowanceScaled ? beforeAllowance - allowanceScaled : 0
        let calculated = scaledPercentageFloor(base, municipalRate, 10_000)
        let minimumBase = ratio(scaled(income), 45, 1_000)
        let minimum = scaledPercentageFloor(minimumBase, municipalRate, 10_000)
        return max(calculated, minimum)
    }

    private static func scaled(_ value: UInt32) -> UInt128 {
        UInt128(value) * scale
    }

    private static func pbb(_ numerator: UInt128, _ denominator: UInt128) -> UInt128 {
        UInt128(priceBaseAmount) * scale * numerator / denominator
    }

    private static func ratio(
        _ value: UInt128,
        _ numerator: UInt128,
        _ denominator: UInt128
    ) -> UInt128 {
        value * numerator / denominator
    }

    private static func roundScaledUpToHundred(_ value: UInt128) -> UInt32 {
        UInt32((value + 100 * scale - 1) / (100 * scale) * 100)
    }

    private static func percentageFloor(
        _ value: UInt32,
        _ numerator: UInt32,
        _ denominator: UInt32
    ) -> UInt32 {
        UInt32(UInt128(value) * UInt128(numerator) / UInt128(denominator))
    }

    private static func scaledPercentageFloor(
        _ value: UInt128,
        _ numerator: UInt32,
        _ denominator: UInt32
    ) -> UInt32 {
        UInt32(value * UInt128(numerator) / UInt128(denominator) / scale)
    }

    static func saturatingSubtract(_ value: UInt32, _ subtract: UInt32) -> UInt32 {
        value > subtract ? value - subtract : 0
    }
}
