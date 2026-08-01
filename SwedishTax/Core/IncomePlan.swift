import Foundation

struct Date2026: Equatable, Comparable, Sendable {
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

enum IncomeKind: String, CaseIterable, Identifiable, Sendable {
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
        case .ownCompanyDividend: "Dividend from own AB — within gränsbelopp"
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

enum PayerRole: String, CaseIterable, Identifiable, Sendable {
    case main = "Main payer"
    case secondary = "Secondary payer"

    var id: Self { self }
}

struct RegularPensionPremium: Equatable, Sendable {
    static let monthlyThreshold: UInt32 = 52_125
    var monthlyOverride: UInt32?

    init(monthlyOverride: UInt32? = nil) {
        self.monthlyOverride = monthlyOverride
    }

    static func benchmarkMonthly(_ monthlySalary: UInt32) -> UInt32 {
        let lower = min(monthlySalary, monthlyThreshold)
        let upper = monthlySalary.saturatingSubtract(monthlyThreshold)
        let numerator = UInt64(lower) * 450 + UInt64(upper) * 3_000
        return UInt32(min((numerator + 5_000) / 10_000, UInt64(UInt32.max)))
    }

    func monthlyAmount(for monthlySalary: UInt32) -> UInt32 {
        monthlyOverride ?? Self.benchmarkMonthly(monthlySalary)
    }
}

struct SalaryExchange: Equatable, Sendable {
    static let defaultUpliftBasisPoints: UInt32 = 576
    static let allowanceMaximum: UInt32 = 592_000

    var sacrificedSalary: UInt32 = 0
    var employerAddsUplift = true
    var upliftBasisPoints: UInt32 = defaultUpliftBasisPoints

    var pensionContribution: UInt32 {
        employerAddsUplift
            ? roundedBasisPoints(
                sacrificedSalary,
                UInt32(10_000).saturatingAdd(upliftBasisPoints)
            )
            : sacrificedSalary
    }

    static func allowanceCeiling(pensionSalaryBasis: UInt32) -> UInt32 {
        min(roundedBasisPoints(pensionSalaryBasis, 3_500), allowanceMaximum)
    }

    func maximumSacrifice(
        paymentAmount: UInt32,
        pensionSalaryBasisBefore: UInt32,
        pensionContributionsBefore: UInt32,
        paymentIsPensionable: Bool
    ) -> UInt32 {
        var low: UInt32 = 0
        var high = paymentAmount
        while low < high {
            let candidate = low + (high - low + 1) / 2
            let basisAfter = paymentIsPensionable
                ? pensionSalaryBasisBefore.saturatingSubtract(candidate)
                : pensionSalaryBasisBefore
            var proposal = self
            proposal.sacrificedSalary = candidate
            let valid = pensionContributionsBefore
                .saturatingAdd(proposal.pensionContribution) <= Self.allowanceCeiling(
                    pensionSalaryBasis: basisAfter
                )
            if valid { low = candidate } else { high = candidate - 1 }
        }
        return low
    }
}

struct VacationCompensation: Equatable, Sendable {
    var annualEntitlementDays: UInt32
    var payoutDays: UInt32
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
        let first = start.clamped
        let last = end.clamped
        guard first <= last else { return 0 }
        let employmentDays = UInt32(last.ordinal - first.ordinal + 1)
        return annualEntitlementDays.saturatingMultiply(employmentDays).saturatingAdd(364) / 365
    }

    func amount(monthlySalary: UInt32) -> UInt32 {
        let denominator: UInt64 = 21 * 10_000
        let numeratorPerDay: UInt64 = 10_000 + 43 * 21
        let numerator = UInt64(monthlySalary) * UInt64(payoutDays) * numeratorPerDay
        return UInt32(min((numerator + denominator / 2) / denominator, UInt64(UInt32.max)))
    }
}

struct IncomeEntry: Identifiable, Equatable, Sendable {
    let id: UInt64
    var description = ""
    var kind: IncomeKind
    var amount: UInt32 = 0
    var start = Date2026(month: 1, day: 1)
    var end = Date2026(month: 12, day: 31)
    var payerRole: PayerRole = .main
    var adjustmentApplies = false
    var useFullYearProjectionAsAdjustmentBasis = false
    var customWithholdingPercent: UInt32?
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

    func amount(forMonth month: UInt8) -> UInt32 {
        guard kind.isMonthly, start <= end, (1...12).contains(month) else { return 0 }
        let first = start.clamped
        let last = end.clamped
        guard month >= first.month, month <= last.month else { return 0 }
        let firstDay: UInt8 = month == first.month ? first.day : 1
        let lastDay: UInt8 = month == last.month ? last.day : Date2026.daysInMonth(month)
        let activeDays = UInt32(lastDay - firstDay + 1)
        return amount.saturatingMultiply(activeDays) / UInt32(Date2026.daysInMonth(month))
    }

    var annualAmount: UInt32 {
        kind.isMonthly
            ? (1...12).reduce(0) { $0.saturatingAdd(amount(forMonth: UInt8($1))) }
            : amount
    }

    var isValid: Bool { !kind.isMonthly || start.clamped <= end.clamped }

    var totalAnnualAmount: UInt32 {
        annualAmount.saturatingAdd(vacationCompensationAmount)
            .saturatingSubtract(salaryExchangeSacrifice)
    }

    var fullYearAdjustmentBasisAmount: UInt32 {
        guard useFullYearProjectionAsAdjustmentBasis else { return 0 }
        return switch kind {
        case .monthlySalary: amount.saturatingMultiply(12)
        case .annualSalary: amount
        default: 0
        }
    }

    var vacationCompensationAmount: UInt32 {
        guard kind == .monthlySalary else { return 0 }
        return vacationCompensation?.amount(monthlySalary: amount) ?? 0
    }

    var regularPensionPremiumAmount: UInt32 {
        guard let premium = regularPensionPremium else { return 0 }
        switch kind {
        case .annualSalary:
            return premium.monthlyAmount(for: amount / 12).saturatingMultiply(12)
        case .monthlySalary:
            let monthly = premium.monthlyAmount(for: amount)
            return (1...12).reduce(0) { total, month in
                total.saturatingAdd(proratedMonthlyValue(month: UInt8(month), value: monthly))
            }
        default: return 0
        }
    }

    var vacationPensionPremiumAmount: UInt32 {
        guard
            kind == .monthlySalary,
            let vacationCompensation,
            vacationCompensation.includedInPensionSalaryBasis
        else { return 0 }
        if let actual = vacationCompensation.pensionPremiumOverride { return actual }
        return RegularPensionPremium.benchmarkMonthly(amount.saturatingAdd(vacationCompensationAmount))
            .saturatingSubtract(RegularPensionPremium.benchmarkMonthly(amount))
    }

    var pensionSalaryBasisAmount: UInt32 {
        let regular = includedInPensionSalaryBasis
            ? annualAmount.saturatingSubtract(salaryExchangeSacrifice)
            : 0
        let vacation = vacationCompensation?.includedInPensionSalaryBasis == true
            ? vacationCompensationAmount
            : 0
        return regular.saturatingAdd(vacation)
    }

    var salaryExchangeSacrifice: UInt32 {
        guard kind == .oneTimeSalary else { return 0 }
        return min(salaryExchange?.sacrificedSalary ?? 0, amount)
    }

    var salaryExchangePensionContribution: UInt32 {
        guard kind == .oneTimeSalary, var exchange = salaryExchange else { return 0 }
        exchange.sacrificedSalary = min(exchange.sacrificedSalary, amount)
        return exchange.pensionContribution
    }

    mutating func prepareForKindChange(from previous: IncomeKind) {
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

    private func proratedMonthlyValue(month: UInt8, value: UInt32) -> UInt32 {
        guard start <= end, (1...12).contains(month) else { return 0 }
        let first = start.clamped
        let last = end.clamped
        guard month >= first.month, month <= last.month else { return 0 }
        let firstDay: UInt8 = month == first.month ? first.day : 1
        let lastDay: UInt8 = month == last.month ? last.day : Date2026.daysInMonth(month)
        return value.saturatingMultiply(UInt32(lastDay - firstDay + 1))
            / UInt32(Date2026.daysInMonth(month))
    }
}

struct IncomePlan: Equatable, Sendable {
    var entries: [IncomeEntry]
    var adjustmentPercent: UInt32?
    private var nextID: UInt64

    init(monthlySalary: UInt32) {
        var entry = IncomeEntry(id: 1, kind: .monthlySalary)
        entry.description = "Ordinary income"
        entry.amount = monthlySalary
        entries = [entry]
        adjustmentPercent = nil
        nextID = 2
    }

    init(annualSalary: UInt32) {
        var entry = IncomeEntry(id: 1, kind: .annualSalary)
        entry.description = "Ordinary income"
        entry.amount = annualSalary
        entries = [entry]
        adjustmentPercent = nil
        nextID = 2
    }

    @discardableResult
    mutating func addEntry(kind: IncomeKind = .annualSalary) -> UInt64 {
        let id = nextID
        nextID = nextID == .max ? .max : nextID + 1
        entries.append(IncomeEntry(id: id, kind: kind))
        return id
    }

    mutating func removeEntry(id: UInt64) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty { addEntry() }
    }

    var isValid: Bool { entries.allSatisfy(\.isValid) }

    var totals: IncomePlanTotals {
        entries.reduce(into: IncomePlanTotals()) { totals, entry in
            let amount = entry.totalAnnualAmount
            totals.regularPensionPremiums = totals.regularPensionPremiums
                .saturatingAdd(entry.regularPensionPremiumAmount)
            totals.vacationPensionPremiums = totals.vacationPensionPremiums
                .saturatingAdd(entry.vacationPensionPremiumAmount)
            totals.pensionSalaryBasis = totals.pensionSalaryBasis
                .saturatingAdd(entry.pensionSalaryBasisAmount)
            totals.adjustmentBasisWorkIncome = totals.adjustmentBasisWorkIncome
                .saturatingAdd(entry.fullYearAdjustmentBasisAmount)
            totals.salaryExchangeSacrifice = totals.salaryExchangeSacrifice
                .saturatingAdd(entry.salaryExchangeSacrifice)
            totals.salaryExchangePensionContributions = totals.salaryExchangePensionContributions
                .saturatingAdd(entry.salaryExchangePensionContribution)
            switch entry.kind {
            case .annualSalary, .monthlySalary, .oneTimeSalary:
                totals.workIncome = totals.workIncome.saturatingAdd(amount)
            case .monthlyOccupationalPension, .annualOccupationalPension:
                totals.pensionIncome = totals.pensionIncome.saturatingAdd(amount)
            case .ownCompanyDividend:
                totals.dividendIncome = totals.dividendIncome.saturatingAdd(amount)
            }
            switch entry.kind {
            case .annualSalary:
                totals.sgiAnnualRate = totals.sgiAnnualRate.saturatingAdd(amount)
            case .monthlySalary:
                totals.sgiAnnualRate = totals.sgiAnnualRate
                    .saturatingAdd(entry.amount.saturatingMultiply(12))
            default: break
            }
        }
    }

    func estimatedWithholding(table: UInt8, ageGroup: TaxAgeGroup) -> WithholdingSummary {
        let totals = totals
        let rows = entries.map { entry -> EntryWithholding in
            let gross = entry.totalAnnualAmount
            let result = entryWithholding(
                entry,
                gross: gross,
                totals: totals,
                table: table,
                ageGroup: ageGroup
            )
            return EntryWithholding(
                entryID: entry.id,
                gross: gross,
                withheld: result.0,
                rule: result.1
            )
        }
        return WithholdingSummary(
            total: rows.reduce(0) { $0.saturatingAdd($1.withheld) },
            entries: rows
        )
    }

    func salaryExchangeAllowance(for entryID: UInt64) -> SalaryExchangeAllowance? {
        guard
            let entry = entries.first(where: { $0.id == entryID }),
            let exchange = entry.salaryExchange
        else { return nil }
        let totals = totals
        let selectedContribution = entry.salaryExchangePensionContribution
        let otherExchange = totals.salaryExchangePensionContributions
            .saturatingSubtract(selectedContribution)
        let contributionsBefore = totals.regularPensionPremiums
            .saturatingAdd(totals.vacationPensionPremiums)
            .saturatingAdd(otherExchange)
        let sacrificeInBasis = entry.includedInPensionSalaryBasis
            ? entry.salaryExchangeSacrifice
            : 0
        let basisBefore = totals.pensionSalaryBasis.saturatingAdd(sacrificeInBasis)
        let basisAfter = basisBefore.saturatingSubtract(sacrificeInBasis)
        let ceiling = SalaryExchange.allowanceCeiling(pensionSalaryBasis: basisAfter)
        return SalaryExchangeAllowance(
            ceiling: ceiling,
            pensionSalaryBasisBefore: basisBefore,
            pensionSalaryBasisAfter: basisAfter,
            regularPensionPremiums: totals.regularPensionPremiums,
            vacationPensionPremiums: totals.vacationPensionPremiums,
            otherExchangeContributions: otherExchange,
            availableContribution: ceiling.saturatingSubtract(contributionsBefore),
            maximumSacrifice: exchange.maximumSacrifice(
                paymentAmount: entry.amount,
                pensionSalaryBasisBefore: basisBefore,
                pensionContributionsBefore: contributionsBefore,
                paymentIsPensionable: entry.includedInPensionSalaryBasis
            )
        )
    }

    private func entryWithholding(
        _ entry: IncomeEntry,
        gross: UInt32,
        totals: IncomePlanTotals,
        table: UInt8,
        ageGroup: TaxAgeGroup
    ) -> (UInt32, AppliedWithholding) {
        if entry.kind.isDividend { return (0, .none) }
        if let percent = entry.customWithholdingPercent {
            return (percentage(gross, percent), .customPercent(percent))
        }
        if entry.adjustmentApplies, let percent = adjustmentPercent {
            return (percentage(gross, percent), .adjustmentPercent(percent))
        }
        if entry.payerRole == .secondary {
            return (percentage(gross, 30), .secondary30)
        }
        let column = entry.kind.isPension ? ageGroup.pensionColumn : ageGroup.salaryColumn
        if entry.kind == .oneTimeSalary {
            let percent = oneTimeWithholdingRate(column: column, annualIncome: totals.workIncome)
            return (percentage(gross, percent), .oneTimeTable(percent))
        }
        let regularWithheld: UInt32
        if entry.kind.isMonthly {
            regularWithheld = (1...12).reduce(0) { total, month in
                total.saturatingAdd(
                    tableWithholding(
                        table: table,
                        column: column,
                        income: entry.amount(forMonth: UInt8(month))
                    )
                )
            }
        } else {
            regularWithheld = annualizedTableWithholding(
                table: table,
                column: column,
                annualIncome: entry.annualAmount
            )
        }
        let vacation = entry.vacationCompensationAmount
        guard vacation > 0 else { return (regularWithheld, .table(column)) }
        let percent = oneTimeWithholdingRate(column: column, annualIncome: totals.workIncome)
        return (
            regularWithheld.saturatingAdd(percentage(vacation, percent)),
            .tableAndOneTime(column, percent)
        )
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
    let availableContribution: UInt32
    let maximumSacrifice: UInt32
}

enum AppliedWithholding: Equatable, Sendable {
    case table(TaxColumn)
    case tableAndOneTime(TaxColumn, UInt32)
    case oneTimeTable(UInt32)
    case secondary30
    case adjustmentPercent(UInt32)
    case customPercent(UInt32)
    case none

    var description: String {
        switch self {
        case .table(let column): "Table, column \(column.rawValue)"
        case .tableAndOneTime(let column, let percent):
            "Table, column \(column.rawValue) + one-time \(percent)%"
        case .oneTimeTable(let percent): "One-time table \(percent)%"
        case .secondary30: "Secondary payer 30%"
        case .adjustmentPercent(let percent): "Jämkning \(percent)%"
        case .customPercent(let percent): "Custom \(percent)%"
        case .none: "No preliminary withholding"
        }
    }
}

struct EntryWithholding: Equatable, Sendable {
    let entryID: UInt64
    let gross: UInt32
    let withheld: UInt32
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
    let dividendIncome: UInt32
    let tableDeduction: TaxDeduction
    let annualTax: AnnualTax
    let adjustmentCalibration: AdjustmentCalibration?
    let ordinaryFinalTax: UInt32
    let dividendTax: UInt32
    let totalTax: UInt32
    let withheldTax: UInt32
    let regularPensionPremiums: UInt32
    let vacationPensionPremiums: UInt32
    let salaryExchangeSacrifice: UInt32
    let salaryExchangePensionContributions: UInt32
    let employerPensionContributions: UInt32
    let marginalRate: Double
    let pensionProgress: IncomeBasisEstimate
    let sgiProgress: IncomeBasisEstimate

    init?(table: UInt8, ageGroup: TaxAgeGroup, plan: IncomePlan) {
        guard plan.isValid else { return nil }
        let totals = plan.totals
        annualIncome = totals.grossIncome
        ordinaryIncome = totals.ordinaryIncome
        dividendIncome = totals.dividendIncome
        monthlyIncome = totals.monthlyTaxableIncome
        guard
            let tableDeduction = TaxCalculator.monthlyDeduction(
                table: table,
                column: ageGroup.salaryColumn,
                grossMonthlyIncome: monthlyIncome
            ),
            let annualTax = TaxCalculator.calculateAnnualTax(
                table: table,
                ageGroup: ageGroup,
                profile: totals.annualProfile
            )
        else { return nil }
        self.tableDeduction = tableDeduction
        self.annualTax = annualTax

        if let percent = plan.adjustmentPercent, totals.adjustmentBasisWorkIncome > 0 {
            let basis = totals.adjustmentBasisWorkIncome
            guard let formulaAtBasis = TaxCalculator.calculateAnnualTax(
                table: table,
                ageGroup: ageGroup,
                profile: AnnualIncomeProfile(workIncome: basis, pensionIncome: 0)
            ) else { return nil }
            let assumed = percentage(basis, percent)
            let implied = Int64(formulaAtBasis.total) - Int64(assumed)
            let projected = (Int64(annualTax.total) - implied)
                .clamped(to: 0...Int64(UInt32.max))
            adjustmentCalibration = AdjustmentCalibration(
                basisIncome: basis,
                percent: percent,
                formulaTaxAtBasis: formulaAtBasis.total,
                assumedTaxAtBasis: assumed,
                impliedTaxAdjustment: implied,
                projectedOrdinaryTax: UInt32(projected)
            )
        } else {
            adjustmentCalibration = nil
        }
        ordinaryFinalTax = adjustmentCalibration?.projectedOrdinaryTax ?? annualTax.total
        dividendTax = percentage(totals.dividendIncome, 20)
        totalTax = ordinaryFinalTax.saturatingAdd(dividendTax)
        withheldTax = plan.estimatedWithholding(table: table, ageGroup: ageGroup).total
        regularPensionPremiums = totals.regularPensionPremiums
        vacationPensionPremiums = totals.vacationPensionPremiums
        salaryExchangeSacrifice = totals.salaryExchangeSacrifice
        salaryExchangePensionContributions = totals.salaryExchangePensionContributions
        employerPensionContributions = totals.totalEmployerPensionContributions
        let upperWork = totals.workIncome.saturatingAdd(12_000)
        guard let upperTax = TaxCalculator.calculateAnnualTax(
            table: table,
            ageGroup: ageGroup,
            profile: AnnualIncomeProfile(
                workIncome: upperWork,
                pensionIncome: totals.pensionIncome
            )
        ) else { return nil }
        marginalRate = (Double(upperTax.total) - Double(annualTax.total)) * 100 / 12_000
        pensionProgress = IncomeBasisCalculator.publicPensionProgressForIncome(totals.workIncome)
        sgiProgress = IncomeBasisCalculator.estimatedSGIProgressForIncome(totals.sgiAnnualRate)
    }

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
    var annualNet: UInt32 { annualIncome.saturatingSubtract(totalTax) }
    var cashAfterWithholding: UInt32 { annualIncome.saturatingSubtract(withheldTax) }
    var taxBalance: Int64 { Int64(totalTax) - Int64(withheldTax) }
}

func oneTimeWithholdingRate(column: TaxColumn, annualIncome: UInt32) -> UInt32 {
    let thresholds: [(UInt32, UInt32)]
    switch column {
    case .column1:
        thresholds = [(25_041, 0), (82_800, 10), (192_000, 21), (477_600, 26),
                      (660_000, 34), (.max, 54)]
    case .column2:
        thresholds = [(65_800, 0), (477_600, 26), (660_000, 34), (.max, 55)]
    case .column3:
        thresholds = [(25_041, 0), (331_200, 10), (477_600, 26), (660_000, 34),
                      (.max, 55)]
    case .column4:
        thresholds = [(25_041, 0), (54_000, 3), (192_000, 22), (660_000, 26),
                      (.max, 46)]
    case .column5:
        thresholds = [(25_041, 0), (32_400, 10), (160_800, 29), (184_800, 34),
                      (660_000, 38), (.max, 54)]
    case .column6:
        thresholds = [(25_041, 0), (160_800, 29), (184_800, 34), (660_000, 38),
                      (.max, 54)]
    }
    return thresholds.first(where: { annualIncome <= $0.0 })?.1 ?? 0
}

private func tableWithholding(table: UInt8, column: TaxColumn, income: UInt32) -> UInt32 {
    guard let deduction = TaxCalculator.monthlyDeduction(
        table: table,
        column: column,
        grossMonthlyIncome: income
    ) else { return 0 }
    return deduction.kind == .amount ? deduction.value : percentage(income, deduction.value)
}

private func annualizedTableWithholding(
    table: UInt8,
    column: TaxColumn,
    annualIncome: UInt32
) -> UInt32 {
    guard let deduction = TaxCalculator.monthlyDeduction(
        table: table,
        column: column,
        grossMonthlyIncome: annualIncome / 12
    ) else { return 0 }
    return deduction.kind == .amount
        ? deduction.value.saturatingMultiply(12)
        : percentage(annualIncome, deduction.value)
}

private func percentage(_ amount: UInt32, _ percent: UInt32) -> UInt32 {
    UInt32(min(UInt64(amount) * UInt64(percent) / 100, UInt64(UInt32.max)))
}

private func roundedBasisPoints(_ amount: UInt32, _ basisPoints: UInt32) -> UInt32 {
    UInt32(min(
        (UInt64(amount) * UInt64(basisPoints) + 5_000) / 10_000,
        UInt64(UInt32.max)
    ))
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
