import Foundation

enum TaxColumn: UInt8, CaseIterable, Identifiable, Sendable {
    case column1 = 1
    case column2
    case column3
    case column4
    case column5
    case column6

    var id: UInt8 { rawValue }

    var title: String { "Column \(rawValue)" }

    var shortDescription: String {
        switch self {
        case .column1: "Salary, under 66"
        case .column2: "Pension, 66 or older"
        case .column3: "Salary, 66 or older"
        case .column4: "Sickness or activity compensation"
        case .column5: "Other pensionable compensation"
        case .column6: "Pension, under 66"
        }
    }

    var explanation: String {
        switch self {
        case .column1:
            "Work income eligible for the earned-income tax credit."
        case .column2:
            "No general pension contribution or earned-income tax credit."
        case .column3:
            "Work income eligible for the enhanced earned-income tax credit."
        case .column4:
            "For people under 66 and eligible for its specific tax reduction."
        case .column5:
            "For example unemployment benefits; no earned-income tax credit."
        case .column6:
            "No general pension contribution or earned-income tax credit."
        }
    }

    var index: Int { Int(rawValue) - 1 }
}

enum TaxAgeGroup: String, CaseIterable, Identifiable, Sendable {
    case under66 = "Under 66"
    case atLeast66 = "66 or older"

    var id: Self { self }

    var salaryColumn: TaxColumn {
        switch self {
        case .under66: .column1
        case .atLeast66: .column3
        }
    }

    var pensionColumn: TaxColumn {
        switch self {
        case .under66: .column6
        case .atLeast66: .column2
        }
    }
}

struct AnnualIncomeProfile: Equatable, Sendable {
    var workIncome: UInt32
    var pensionIncome: UInt32

    var total: UInt32 { workIncome.saturatingAdd(pensionIncome) }
}

enum TaxDeductionKind: Sendable {
    case amount
    case percent
}

struct TaxDeduction: Equatable, Sendable {
    let kind: TaxDeductionKind
    let value: UInt32

    static func amount(_ value: UInt32) -> Self {
        Self(kind: .amount, value: value)
    }

    static func percent(_ value: UInt32) -> Self {
        Self(kind: .percent, value: value)
    }
}

struct AnnualTax: Equatable, Sendable {
    let assessedIncome: UInt32
    let basicAllowance: UInt32
    let taxableIncome: UInt32
    let stateIncomeTax: UInt32
    let municipalIncomeTax: UInt32
    let burialAndReligiousFee: UInt32
    let pensionFee: UInt32
    let pensionFeeCredit: UInt32
    let workIncomeCredit: UInt32
    let sicknessCompensationCredit: UInt32
    let earnedIncomeCredit: UInt32
    let publicServiceFee: UInt32
    let total: UInt32
}

enum IncomePeriod: String, CaseIterable, Identifiable, Sendable {
    case monthly = "Monthly"
    case annual = "Annual"

    var id: Self { self }
}

struct TaxCalculation: Equatable, Sendable {
    let monthlyIncome: UInt32
    let annualIncome: UInt32
    let tableDeduction: TaxDeduction
    let annualTax: AnnualTax
    let marginalRate: Double
    let pensionProgress: IncomeBasisEstimate
    let sgiProgress: IncomeBasisEstimate

    init?(
        table: UInt8,
        column: TaxColumn,
        period: IncomePeriod,
        income: UInt32
    ) {
        switch period {
        case .monthly:
            monthlyIncome = income
            annualIncome = UInt32(
                min(UInt64(income) * 12, UInt64(UInt32.max))
            )
        case .annual:
            monthlyIncome = income / 12
            annualIncome = income
        }

        guard
            let deduction = TaxCalculator.monthlyDeduction(
                table: table,
                column: column,
                grossMonthlyIncome: monthlyIncome
            ),
            let annualTax = TaxCalculator.calculateAnnualTax(
                table: table,
                column: column,
                grossYearlyIncome: annualIncome
            ),
            let marginalRate = TaxCalculator.calculateMarginalRate(
                table: table,
                column: column,
                monthlyIncome: monthlyIncome
            )
        else {
            return nil
        }

        tableDeduction = deduction
        self.annualTax = annualTax
        self.marginalRate = marginalRate
        pensionProgress = IncomeBasisCalculator.publicPensionProgress(
            column: column,
            grossYearlyIncome: annualIncome
        )
        sgiProgress = IncomeBasisCalculator.estimatedSGIProgress(
            column: column,
            grossYearlyIncome: annualIncome
        )
    }

    var formulaMonthlyTax: UInt32 { annualTax.total / 12 }

    var formulaMonthlyNet: UInt32 {
        monthlyIncome > formulaMonthlyTax ? monthlyIncome - formulaMonthlyTax : 0
    }

    var effectiveRate: Double {
        annualIncome == 0 ? 0 : Double(annualTax.total) * 100 / Double(annualIncome)
    }
}

extension UInt32 {
    func saturatingAdd(_ other: UInt32) -> UInt32 {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? .max : value
    }

    func saturatingSubtract(_ other: UInt32) -> UInt32 {
        self >= other ? self - other : 0
    }

    func saturatingMultiply(_ other: UInt32) -> UInt32 {
        let product = UInt64(self) * UInt64(other)
        return UInt32(Swift.min(product, UInt64(UInt32.max)))
    }
}
