import SwedishTaxFFI
import Foundation

struct Date2026: Codable, Equatable, Comparable, Sendable {
    var month: UInt8
    var day: UInt8

    init(month: UInt8, day: UInt8) {
        self.month = month
        self.day = day
    }

    static func daysInMonth(_ month: UInt8) -> UInt8 {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 2: 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    var clamped: Self {
        let validMonth = min(max(month, 1), 12)
        return Self(month: validMonth, day: min(max(day, 1), Self.daysInMonth(validMonth)))
    }

    var ordinal: UInt16 {
        let starts: [UInt16] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let value = clamped
        return starts[Int(value.month) - 1] + UInt16(value.day)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.clamped.ordinal < rhs.clamped.ordinal
    }
}

enum IncomeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case annualSalary
    case monthlySalary
    case oneTimeSalary
    case monthlyOccupationalPension
    case annualOccupationalPension
    case ownCompanyDividend

    var id: Self { self }

    var title: String {
        switch self {
        case .annualSalary: "Ordinary salary — annual total"
        case .monthlySalary: "Salary — monthly over a period"
        case .oneTimeSalary: "One-time salary / termination payment"
        case .monthlyOccupationalPension: "Tjänstepension — monthly over a period"
        case .annualOccupationalPension: "Tjänstepension — annual total"
        case .ownCompanyDividend: "Dividend from own AB"
        }
    }

    var shortTitle: String {
        switch self {
        case .annualSalary: "Annual salary"
        case .monthlySalary: "Monthly salary"
        case .oneTimeSalary: "One-time salary"
        case .monthlyOccupationalPension: "Monthly tjänstepension"
        case .annualOccupationalPension: "Annual tjänstepension"
        case .ownCompanyDividend: "Own-AB dividend"
        }
    }

    var isMonthly: Bool {
        self == .monthlySalary || self == .monthlyOccupationalPension
    }

    var isDividend: Bool { self == .ownCompanyDividend }

    var isSalary: Bool {
        self == .annualSalary || self == .monthlySalary || self == .oneTimeSalary
    }

    var isPension: Bool {
        self == .monthlyOccupationalPension || self == .annualOccupationalPension
    }

    var eligibility: String {
        switch self {
        case .annualSalary, .monthlySalary: "PGI + SGI"
        case .oneTimeSalary: "PGI · not ongoing SGI"
        case .monthlyOccupationalPension, .annualOccupationalPension: "No new PGI or SGI"
        case .ownCompanyDividend: "20% final tax · no PGI or SGI"
        }
    }
}

enum PayerRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case main = "Main payer"
    case secondary = "Secondary payer"

    var id: Self { self }
}

struct RegularPensionPremium: Codable, Equatable, Sendable {
    static let monthlyThreshold = RustTaxCore.planningPolicy.regular_pension_monthly_threshold
    var monthlyOverride: UInt32?

    init(monthlyOverride: UInt32? = nil) {
        self.monthlyOverride = monthlyOverride
    }

    static func benchmarkMonthly(_ monthlySalary: UInt32) -> UInt32 {
        var entry = IncomeEntry(id: 0, kind: .monthlySalary)
        entry.amount = monthlySalary
        return RustTaxCore.entrySupport(entry).pension_benchmark_monthly
    }
}

struct SalaryExchange: Codable, Equatable, Sendable {
    static let defaultUpliftBasisPoints = RustTaxCore.planningPolicy.default_exchange_uplift_basis_points
    static let allowanceMaximum = RustTaxCore.planningPolicy.employer_pension_allowance_maximum

    var sacrificedSalary: UInt32 = 0
    var employerAddsUplift = true
    var upliftBasisPoints: UInt32 = defaultUpliftBasisPoints
    var previousYearPensionSalaryBasis: UInt32?
    var pensionAndInsuranceCostsBeforeExchange: UInt32?
}

struct VacationCompensation: Codable, Equatable, Sendable {
    static let defaultRateBasisPoints = RustTaxCore.planningPolicy.default_vacation_rate_basis_points

    var annualEntitlementDays: UInt32
    var payoutDays: UInt32
    var rateBasisPoints: UInt32?
    var includedInPensionSalaryBasis = true
    var pensionPremiumOverride: UInt32?

    init(annualEntitlementDays: UInt32, start: Date2026, end: Date2026) {
        self.annualEntitlementDays = annualEntitlementDays
        payoutDays = Self.suggestedDays(annualEntitlementDays, start: start, end: end)
    }

    static func suggestedDays(
        _ annualEntitlementDays: UInt32,
        start: Date2026,
        end: Date2026
    ) -> UInt32 {
        // Set raw input without invoking this initializer recursively.
        var vacation = SwedishTaxVacationCompensation()
        vacation.is_some = 1
        vacation.annual_entitlement_days = annualEntitlementDays
        var input = SwedishTaxIncomeEntry()
        input.kind = 1
        input.start = SwedishTaxDate(month: UInt32(start.month), day: UInt32(start.day))
        input.end = SwedishTaxDate(month: UInt32(end.month), day: UInt32(end.day))
        input.vacation_compensation = vacation
        let result = swedish_tax_entry_support(&input)
        precondition(result.status == 0)
        return result.suggested_vacation_days
    }
}

struct IncomeEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UInt64
    var description = ""
    var kind: IncomeKind
    var amount: UInt32 = 0
    var start = Date2026(month: 1, day: 1)
    var end = Date2026(month: 12, day: 31)
    var useAnnualDailyRateForPartialMonths = false
    var payerRole: PayerRole = .main
    var ownCompanySourced = false
    var adjustmentApplies = false
    var useFullYearProjectionAsAdjustmentBasis = false
    var additionalWithholdingPerPayment: UInt32?
    var actualWithholding: UInt32?
    var vacationCompensation: VacationCompensation?
    var regularPensionPremium: RegularPensionPremium?
    var salaryExchange: SalaryExchange?
    var includedInPensionSalaryBasis: Bool

    init(id: UInt64, kind: IncomeKind) {
        self.id = id
        self.kind = kind
        let salary = kind == .annualSalary || kind == .monthlySalary
        regularPensionPremium = salary ? RegularPensionPremium() : nil
        includedInPensionSalaryBasis = salary
    }


    private var support: SwedishTaxEntrySupport { RustTaxCore.entrySupport(self) }

    func amount(forMonth month: UInt8) -> UInt32 {
        guard (1...12).contains(month) else { return 0 }
        let m = support.monthly_amounts
        return [m.january, m.february, m.march, m.april, m.may, m.june,
                m.july, m.august, m.september, m.october, m.november, m.december][Int(month) - 1]
    }

    var annualAmount: UInt32 { support.annual_amount }
    var withholdingPaymentCount: UInt32 { support.withholding_payment_count }
    var requestedAdditionalWithholding: UInt32 { support.requested_additional_withholding }
    var totalAnnualAmount: UInt32 { support.total_annual_amount }
    var fullYearAdjustmentBasisAmount: UInt32 { support.full_year_adjustment_basis_amount }
    var vacationCompensationAmount: UInt32 { support.vacation_compensation_amount }
    var regularPensionPremiumAmount: UInt32 { support.regular_pension_premium_amount }
    var vacationPensionPremiumAmount: UInt32 { support.vacation_pension_premium_amount }
    var pensionSalaryBasisAmount: UInt32 { support.pension_salary_basis_amount }
    var salaryExchangeSacrifice: UInt32 { support.salary_exchange_sacrifice }
    var salaryExchangePensionContribution: UInt32 { support.salary_exchange_pension_contribution }
    var isValid: Bool { support.is_valid != 0 }

    mutating func prepareForKindChange(
        from previous: IncomeKind,
        adjustmentAvailable: Bool = false
    ) {
        guard previous != kind else { return }
        let salary = kind == .annualSalary || kind == .monthlySalary
        includedInPensionSalaryBasis = salary
        if salary, regularPensionPremium == nil { regularPensionPremium = RegularPensionPremium() }
        if !salary {
            regularPensionPremium = nil
            useFullYearProjectionAsAdjustmentBasis = false
        }
        if kind != .oneTimeSalary { salaryExchange = nil }
        if kind != .monthlySalary { vacationCompensation = nil }
        if !kind.isMonthly { useAnnualDailyRateForPartialMonths = false }
        if kind.isDividend {
            adjustmentApplies = false
            additionalWithholdingPerPayment = nil
        } else if previous.isDividend, payerRole == .main {
            adjustmentApplies = adjustmentAvailable
        }
        if !kind.isSalary { ownCompanySourced = false }
    }

    mutating func setPayerRole(_ role: PayerRole, adjustmentAvailable: Bool) {
        guard payerRole != role else { return }
        payerRole = role
        adjustmentApplies = adjustmentAvailable && role == .main && !kind.isDividend
    }

    /// Mirrors the Rust editor: changing the annual entitlement recalculates
    /// suggested payout days for the selected employment period.
    mutating func setVacationAnnualEntitlementDays(_ days: UInt32) {
        vacationCompensation = days == 0
            ? nil
            : VacationCompensation(
                annualEntitlementDays: days,
                start: start,
                end: end
            )
    }
}

enum IncomePlanValidationIssue: Equatable, Sendable {
    case invalidPaymentPeriod(entryID: UInt64)
    case salaryExchangeExceedsAllowance(entryID: UInt64, maximum: UInt32)
}

struct IncomePlan: Codable, Equatable, Sendable {
    var entries: [IncomeEntry]
    var adjustmentPercent: UInt32?
    var dividendAllowance = DividendAllowanceInputs2027()
    private var nextID: UInt64

    init(monthlySalary: UInt32) {
        var entry = IncomeEntry(id: 1, kind: .monthlySalary)
        entry.description = "Ordinary income"
        entry.amount = monthlySalary
        entries = [entry]
        adjustmentPercent = nil
        dividendAllowance = DividendAllowanceInputs2027()
        nextID = 2
    }

    init(annualSalary: UInt32) {
        var entry = IncomeEntry(id: 1, kind: .annualSalary)
        entry.description = "Ordinary income"
        entry.amount = annualSalary
        entries = [entry]
        adjustmentPercent = nil
        dividendAllowance = DividendAllowanceInputs2027()
        nextID = 2
    }

    @discardableResult
    mutating func addEntry(kind: IncomeKind = .annualSalary) -> UInt64 {
        let id = nextID
        nextID = nextID == .max ? .max : nextID + 1
        var entry = IncomeEntry(id: id, kind: kind)
        entry.adjustmentApplies = adjustmentPercent != nil && !kind.isDividend
        entries.append(entry)
        return id
    }

    mutating func setAdjustmentEnabled(_ enabled: Bool) {
        guard enabled != (adjustmentPercent != nil) else { return }
        adjustmentPercent = enabled ? 30 : nil
        for index in entries.indices {
            entries[index].adjustmentApplies = enabled
                && entries[index].payerRole == .main
                && !entries[index].kind.isDividend
        }
    }

    mutating func removeEntry(id: UInt64) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty { addEntry() }
    }

    private var support: RustTaxCore.PlanSupport {
        // Failure indicates an incompatible native integration, not a plan validation issue.
        do { return try RustTaxCore.planSupport(self) }
        catch { preconditionFailure("Rust planning support failed: \(error)") }
    }

    var validationIssue: IncomePlanValidationIssue? { support.issue }
    var isValid: Bool { validationIssue == nil }
    var totals: IncomePlanTotals { support.totals }

    func salaryExchangeAllowance(for entryID: UInt64) -> SalaryExchangeAllowance? {
        guard let row = support.entries.first(where: { $0.entry_id == entryID }), row.has_allowance != 0 else { return nil }
        let a = row.allowance
        return SalaryExchangeAllowance(
            ceiling: a.ceiling,
            pensionSalaryBasisBefore: a.pension_salary_basis_before,
            pensionSalaryBasisAfter: a.pension_salary_basis_after,
            regularPensionPremiums: a.regular_pension_premiums,
            vacationPensionPremiums: a.vacation_pension_premiums,
            otherExchangeContributions: a.other_exchange_contributions,
            pensionContributionsBefore: a.pension_contributions_before,
            availableContribution: a.available_contribution,
            maximumSacrifice: a.maximum_sacrifice)
    }
}

struct IncomePlanTotals: Equatable, Sendable {
    var workIncome: UInt32 = 0
    var pensionIncome: UInt32 = 0
    var dividendIncome: UInt32 = 0
    var sgiAnnualRate: UInt32 = 0
    var adjustmentBasisWorkIncome: UInt32 = 0
    var pensionSalaryBasis: UInt32 = 0
    var regularPensionPremiums: UInt32 = 0
    var vacationPensionPremiums: UInt32 = 0
    var salaryExchangeSacrifice: UInt32 = 0
    var salaryExchangePensionContributions: UInt32 = 0

    var ordinaryIncome: UInt32 { workIncome.saturatingAdd(pensionIncome) }
    var monthlyTaxableIncome: UInt32 { ordinaryIncome / 12 }
    var grossIncome: UInt32 { ordinaryIncome.saturatingAdd(dividendIncome) }
    var annualProfile: AnnualIncomeProfile {
        AnnualIncomeProfile(workIncome: workIncome, pensionIncome: pensionIncome)
    }
    var totalEmployerPensionContributions: UInt32 {
        regularPensionPremiums.saturatingAdd(vacationPensionPremiums)
            .saturatingAdd(salaryExchangePensionContributions)
    }
}

struct SalaryExchangeAllowance: Equatable, Sendable {
    let ceiling: UInt32
    let pensionSalaryBasisBefore: UInt32
    let pensionSalaryBasisAfter: UInt32
    let regularPensionPremiums: UInt32
    let vacationPensionPremiums: UInt32
    let otherExchangeContributions: UInt32
    let pensionContributionsBefore: UInt32
    let availableContribution: UInt32
    let maximumSacrifice: UInt32
}

enum AppliedWithholding: Equatable, Sendable {
    case actualAmount
    case table(TaxColumn)
    case tableAndOneTime(TaxColumn, UInt32)
    case oneTimeTable(UInt32)
    case secondary30
    case adjustmentPercent(UInt32)
    case none

    var description: String {
        switch self {
        case .actualAmount: "Actual amount entered"
        case .table(let column): "Table, column \(column.rawValue)"
        case .tableAndOneTime(let column, let percent):
            "Table, column \(column.rawValue) + one-time \(percent)%"
        case .oneTimeTable(let percent): "One-time table \(percent)%"
        case .secondary30: "Secondary payer 30%"
        case .adjustmentPercent(let percent): "Jämkning \(percent)%"
        case .none: "No preliminary withholding"
        }
    }
}

struct EntryWithholding: Equatable, Sendable {
    let entryID: UInt64
    let gross: UInt32
    let withheld: UInt32
    let regularWithheld: UInt32
    let supplementalWithheld: UInt32
    let additionalWithheld: UInt32
    let rule: AppliedWithholding
}

struct WithholdingSummary: Equatable, Sendable {
    let total: UInt32
    let entries: [EntryWithholding]
}

struct AdjustmentCalibration: Equatable, Sendable {
    let basisIncome: UInt32
    let percent: UInt32
    let formulaTaxAtBasis: UInt32
    let assumedTaxAtBasis: UInt32
    let impliedTaxAdjustment: Int64
    let projectedOrdinaryTax: UInt32
}

struct PlanCalculation: Equatable, Sendable {
    let monthlyIncome: UInt32
    let annualIncome: UInt32
    let ordinaryIncome: UInt32
    let workIncome: UInt32
    let pensionIncome: UInt32
    let dividendIncome: UInt32
    let sgiAnnualRate: UInt32
    let tableDeduction: TaxDeduction
    let annualTax: AnnualTax
    let adjustmentCalibration: AdjustmentCalibration?
    let ordinaryFinalTax: UInt32
    let dividendTax: UInt32
    let totalTax: UInt32
    let withholding: WithholdingSummary
    let withheldTax: UInt32
    let regularPensionPremiums: UInt32
    let vacationPensionPremiums: UInt32
    let salaryExchangeSacrifice: UInt32
    let salaryExchangePensionContributions: UInt32
    let pensionSalaryBasis: UInt32
    let employerPensionContributions: UInt32
    let marginalRate: Double
    let pensionProgress: IncomeBasisEstimate
    let sgiProgress: IncomeBasisEstimate

    var tableReferenceTax: UInt32 {
        switch tableDeduction.kind {
        case .amount: tableDeduction.value
        case .percent: percentage(monthlyIncome, tableDeduction.value)
        }
    }

    var tableReferenceNet: UInt32 { monthlyIncome.saturatingSubtract(tableReferenceTax) }
    var annualizedTableReferenceTax: UInt32 { tableReferenceTax.saturatingMultiply(12) }
    var effectiveRate: Double {
        ordinaryIncome == 0 ? 0 : Double(ordinaryFinalTax) * 100 / Double(ordinaryIncome)
    }
    var employerPensionShareOfBasis: Double {
        pensionSalaryBasis == 0
            ? 0
            : Double(employerPensionContributions) * 100 / Double(pensionSalaryBasis)
    }
    var annualNet: UInt32 { annualIncome.saturatingSubtract(totalTax) }
    var cashAfterWithholding: UInt32 { annualIncome.saturatingSubtract(withheldTax) }
    var taxBalance: Int64 { Int64(totalTax) - Int64(withheldTax) }
}

private func percentage(_ amount: UInt32, _ percent: UInt32) -> UInt32 {
    UInt32(min(UInt64(amount) * UInt64(percent) / 100, UInt64(UInt32.max)))
}
