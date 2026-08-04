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

struct SalaryExchange: Codable, Equatable, Sendable {
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

struct VacationCompensation: Codable, Equatable, Sendable {
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
        let salaryDays = UInt64(monthlySalary) * UInt64(payoutDays)
        let numerator = salaryDays > UInt64.max / numeratorPerDay
            ? UInt64.max
            : salaryDays * numeratorPerDay
        let roundedNumerator = numerator > UInt64.max - denominator / 2
            ? UInt64.max
            : numerator + denominator / 2
        return UInt32(min(roundedNumerator / denominator, UInt64(UInt32.max)))
    }
}

struct IncomeEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UInt64
    var description = ""
    var kind: IncomeKind
    var amount: UInt32 = 0
    var start = Date2026(month: 1, day: 1)
    var end = Date2026(month: 12, day: 31)
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

    private enum CodingKeys: String, CodingKey {
        case id, description, kind, amount, start, end, payerRole
        case ownCompanySourced, adjustmentApplies
        case useFullYearProjectionAsAdjustmentBasis, additionalWithholdingPerPayment
        case actualWithholding, vacationCompensation, regularPensionPremium
        case salaryExchange, includedInPensionSalaryBasis
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(UInt64.self, forKey: .id)
        let kind = try values.decode(IncomeKind.self, forKey: .kind)
        self.init(id: id, kind: kind)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        amount = try values.decodeIfPresent(UInt32.self, forKey: .amount) ?? 0
        start = try values.decodeIfPresent(Date2026.self, forKey: .start)
            ?? Date2026(month: 1, day: 1)
        end = try values.decodeIfPresent(Date2026.self, forKey: .end)
            ?? Date2026(month: 12, day: 31)
        payerRole = try values.decodeIfPresent(PayerRole.self, forKey: .payerRole) ?? .main
        ownCompanySourced = try values.decodeIfPresent(
            Bool.self,
            forKey: .ownCompanySourced
        ) ?? false
        adjustmentApplies = try values.decodeIfPresent(
            Bool.self,
            forKey: .adjustmentApplies
        ) ?? false
        useFullYearProjectionAsAdjustmentBasis = try values.decodeIfPresent(
            Bool.self,
            forKey: .useFullYearProjectionAsAdjustmentBasis
        ) ?? false
        additionalWithholdingPerPayment = try values.decodeIfPresent(
            UInt32.self,
            forKey: .additionalWithholdingPerPayment
        )
        actualWithholding = try values.decodeIfPresent(UInt32.self, forKey: .actualWithholding)
        vacationCompensation = try values.decodeIfPresent(
            VacationCompensation.self,
            forKey: .vacationCompensation
        )
        regularPensionPremium = try values.decodeIfPresent(
            RegularPensionPremium.self,
            forKey: .regularPensionPremium
        )
        salaryExchange = try values.decodeIfPresent(SalaryExchange.self, forKey: .salaryExchange)
        includedInPensionSalaryBasis = try values.decodeIfPresent(
            Bool.self,
            forKey: .includedInPensionSalaryBasis
        ) ?? kind.isSalary
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(description, forKey: .description)
        try values.encode(kind, forKey: .kind)
        try values.encode(amount, forKey: .amount)
        try values.encode(start, forKey: .start)
        try values.encode(end, forKey: .end)
        try values.encode(payerRole, forKey: .payerRole)
        try values.encode(ownCompanySourced, forKey: .ownCompanySourced)
        try values.encode(adjustmentApplies, forKey: .adjustmentApplies)
        try values.encode(
            useFullYearProjectionAsAdjustmentBasis,
            forKey: .useFullYearProjectionAsAdjustmentBasis
        )
        try values.encodeIfPresent(
            additionalWithholdingPerPayment,
            forKey: .additionalWithholdingPerPayment
        )
        try values.encodeIfPresent(actualWithholding, forKey: .actualWithholding)
        try values.encodeIfPresent(vacationCompensation, forKey: .vacationCompensation)
        try values.encodeIfPresent(regularPensionPremium, forKey: .regularPensionPremium)
        try values.encodeIfPresent(salaryExchange, forKey: .salaryExchange)
        try values.encode(includedInPensionSalaryBasis, forKey: .includedInPensionSalaryBasis)
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

    var withholdingPaymentCount: UInt32 {
        switch kind {
        case .annualSalary, .annualOccupationalPension:
            return 12
        case .monthlySalary, .monthlyOccupationalPension:
            guard start.clamped <= end.clamped else { return 0 }
            return UInt32(end.clamped.month - start.clamped.month + 1)
        case .oneTimeSalary:
            return 1
        case .ownCompanyDividend:
            return 0
        }
    }

    var requestedAdditionalWithholding: UInt32 {
        (additionalWithholdingPerPayment ?? 0).saturatingMultiply(withholdingPaymentCount)
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

enum IncomePlanValidationIssue: Equatable, Sendable {
    case invalidPaymentPeriod(entryID: UInt64)
    case salaryExchangeExceedsAllowance(entryID: UInt64, maximum: UInt32)
}

struct IncomePlan: Codable, Equatable, Sendable {
    var entries: [IncomeEntry]
    var adjustmentPercent: UInt32?
    var dividendAllowance = DividendAllowanceInputs2027()
    private var nextID: UInt64

    private enum CodingKeys: String, CodingKey {
        case entries, adjustmentPercent, dividendAllowance, nextID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode([IncomeEntry].self, forKey: .entries)
        adjustmentPercent = try values.decodeIfPresent(UInt32.self, forKey: .adjustmentPercent)
        dividendAllowance = try values.decodeIfPresent(
            DividendAllowanceInputs2027.self,
            forKey: .dividendAllowance
        ) ?? DividendAllowanceInputs2027()
        nextID = try values.decodeIfPresent(UInt64.self, forKey: .nextID)
            ?? entries.map(\.id).max().map { $0 == .max ? .max : $0 + 1 }
            ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entries, forKey: .entries)
        try values.encodeIfPresent(adjustmentPercent, forKey: .adjustmentPercent)
        try values.encode(dividendAllowance, forKey: .dividendAllowance)
        try values.encode(nextID, forKey: .nextID)
    }

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

    var validationIssue: IncomePlanValidationIssue? {
        for entry in entries where !entry.isValid {
            return .invalidPaymentPeriod(entryID: entry.id)
        }
        for entry in entries where entry.salaryExchange != nil {
            guard let allowance = salaryExchangeAllowance(for: entry.id) else { continue }
            if entry.salaryExchangeSacrifice > allowance.maximumSacrifice {
                return .salaryExchangeExceedsAllowance(
                    entryID: entry.id,
                    maximum: allowance.maximumSacrifice
                )
            }
        }
        return nil
    }

    var isValid: Bool { validationIssue == nil }

    var ownCompanySourcedWorkIncome: UInt32 {
        entries
            .filter { $0.kind.isSalary && $0.ownCompanySourced }
            .reduce(0) { $0.saturatingAdd($1.totalAnnualAmount) }
    }

    func dividendAllowance2027() throws -> DividendAllowance2027 {
        try dividendAllowance.calculate(ownerCashSalary2026: ownCompanySourcedWorkIncome)
    }

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
    var annualNet: UInt32 { annualIncome.saturatingSubtract(totalTax) }
    var cashAfterWithholding: UInt32 { annualIncome.saturatingSubtract(withheldTax) }
    var taxBalance: Int64 { Int64(totalTax) - Int64(withheldTax) }
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
