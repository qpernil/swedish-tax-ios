import SwiftUI
import UIKit

struct IncomeEntryRow: View {
    let entry: IncomeEntry
    let withholding: EntryWithholding?
    let adjustmentPercent: UInt32?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.description.isEmpty ? entry.kind.shortTitle : entry.description)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(entry.kind.shortTitle) · \(entry.eligibilityText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let withholding {
                    Text("Withheld \(formatSEK(withholding.withheld))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.taxBlue)
                }
                if let adjustmentStatusText {
                    Label(adjustmentStatusText, systemImage: adjustmentIsApplied
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.taxAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.taxAmber.opacity(0.12), in: Capsule())
                }
                if entry.vacationCompensationAmount > 0 {
                    Text("Includes vacation pay \(formatSEK(entry.vacationCompensationAmount))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.taxGreen)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatSEK(entry.totalAnnualAmount))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(amountPeriodText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch entry.kind {
        case .annualSalary, .monthlySalary, .oneTimeSalary: "briefcase.fill"
        case .monthlyOccupationalPension, .annualOccupationalPension: "figure.walk.motion"
        case .ownCompanyDividend: "building.2.fill"
        }
    }

    private var iconColor: Color {
        entry.kind.isDividend ? .taxAmber : entry.kind.isPension ? .taxGreen : .taxBlue
    }

    private var adjustmentIsApplied: Bool {
        guard let withholding else { return false }
        if case .adjustmentPercent = withholding.rule { return true }
        return false
    }

    private var adjustmentStatusText: String? {
        guard let percent = adjustmentPercent, entry.adjustmentApplies else { return nil }
        if adjustmentIsApplied { return "Jämkning \(percent)% applied" }
        if let withholding { return "Jämkning overridden by \(withholding.rule.description)" }
        return "Jämkning \(percent)% selected"
    }

    private var amountPeriodText: String {
        switch entry.kind {
        case .oneTimeSalary, .ownCompanyDividend:
            "One-time total"
        default:
            "/ year"
        }
    }
}

private extension IncomeEntry {
    var eligibilityText: String { kind.eligibility }
}

struct IncomeEntryEditor: View {
    @Binding var plan: IncomePlan
    let entryID: UInt64
    let table: UInt8
    let ageGroup: TaxAgeGroup
    @Environment(\.dismiss) private var dismiss

    private var entry: Binding<IncomeEntry>? { $plan.incomeEntry(id: entryID) }

    private var withholdingResult: Result<EntryWithholding?, Error> {
        Result {
            try RustTaxCore.planCalculation(table: table, ageGroup: ageGroup, plan: plan)
                .withholding
                .entries.first { $0.entryID == entryID }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    ScrollView {
                        VStack(spacing: 14) {
                            basicCard(entry)
                            if entry.wrappedValue.kind.isMonthly { periodCard(entry) }
                            if entry.wrappedValue.kind == .monthlySalary { vacationCard(entry) }
                            if entry.wrappedValue.kind == .annualSalary || entry.wrappedValue.kind == .monthlySalary {
                                pensionCard(entry)
                            }
                            if entry.wrappedValue.kind == .oneTimeSalary { salaryExchangeCard(entry) }
                            withholdingCard(entry)
                            impactCard(entry.wrappedValue)
                            Button(role: .destructive) {
                                plan.removeEntry(id: entryID)
                                dismiss()
                            } label: {
                                Label("Delete income", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color.taxBackground)
                } else {
                    ContentUnavailableView("Income not found", systemImage: "exclamationmark.triangle")
                }
            }
            .background(TapOutsideKeyboardDismissView())
            .navigationTitle("Edit income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func basicCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Payment", systemImage: "banknote") {
            LabeledContent("Description") {
                SelectAllTextField("Employer or payment", text: entry.description)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel("Income type")
                Picker("Income type", selection: entry.kind) {
                    ForEach(IncomeKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .onChange(of: entry.wrappedValue.kind) { old, _ in
                    entry.wrappedValue.prepareForKindChange(
                        from: old,
                        adjustmentAvailable: plan.adjustmentPercent != nil
                    )
                }
            }
            Divider()
            UIntField(
                title: entry.wrappedValue.kind.isMonthly ? "Amount per month" : "Annual / one-time amount",
                value: entry.amount,
                suffix: "SEK"
            )
            if entry.wrappedValue.kind.isSalary {
                Divider()
                Toggle(
                    "Paid by my own company or qualifying group",
                    isOn: entry.ownCompanySourced
                )
                Text("Feeds the preliminary 2027 3:12 owner-salary and payroll calculation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(entry.wrappedValue.kind.eligibility)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.taxBlue)
        }
    }

    private func periodCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Payment period", systemImage: "calendar") {
            Date2026Field(title: "First day", value: entry.start)
                .onChange(of: entry.wrappedValue.start) { _, _ in
                    updateSuggestedVacationDays(entry)
                }
            Divider()
            Date2026Field(title: "Last day", value: entry.end)
                .onChange(of: entry.wrappedValue.end) { _, _ in
                    updateSuggestedVacationDays(entry)
                }
            Text("Both the first and last day are included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Use full year") {
                entry.wrappedValue.start = Date2026(month: 1, day: 1)
                entry.wrappedValue.end = Date2026(month: 12, day: 31)
                updateSuggestedVacationDays(entry)
            }
            .buttonStyle(.bordered)
            if !entry.wrappedValue.isValid {
                Label("Last day must be on or after first day", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Text("Annual amount: \(formatSEK(entry.wrappedValue.annualAmount))")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func vacationCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Vacation compensation", systemImage: "sun.max") {
            Toggle("Include vacation payout", isOn: Binding(
                get: { entry.wrappedValue.vacationCompensation != nil },
                set: { enabled in
                    entry.wrappedValue.vacationCompensation = enabled
                        ? VacationCompensation(
                            annualEntitlementDays: 25,
                            start: entry.wrappedValue.start,
                            end: entry.wrappedValue.end
                        )
                        : nil
                }
            ))
            if entry.wrappedValue.vacationCompensation != nil {
                UIntField(
                    title: "Vacation days per full year",
                    value: Binding(
                        get: {
                            entry.wrappedValue.vacationCompensation?.annualEntitlementDays ?? 25
                        },
                        set: { days in
                            entry.wrappedValue.setVacationAnnualEntitlementDays(min(days, 100))
                        }
                    ),
                    suffix: "days",
                    maximum: 100
                )
                UIntField(
                    title: "Days paid out",
                    value: vacationBinding(entry, \.payoutDays, default: 25),
                    suffix: "days",
                    maximum: 365
                )
                Button("Use suggested days") { updateSuggestedVacationDays(entry) }
                    .buttonStyle(.bordered)
                Text("Same-pay estimate: monthly salary / 21 plus 0.43% per paid day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Vacation compensation", value: formatSEK(entry.wrappedValue.vacationCompensationAmount))
                    .fontWeight(.semibold)
                Toggle("Treat this payout as pensionable", isOn: Binding(
                    get: { entry.wrappedValue.vacationCompensation?.includedInPensionSalaryBasis ?? true },
                    set: { included in
                        guard var vacation = entry.wrappedValue.vacationCompensation else { return }
                        vacation.includedInPensionSalaryBasis = included
                        if !included { vacation.pensionPremiumOverride = nil }
                        entry.wrappedValue.vacationCompensation = vacation
                    }
                ))
                Toggle("Use actual pension contribution for this vacation payout", isOn: Binding(
                    get: { entry.wrappedValue.vacationCompensation?.pensionPremiumOverride != nil },
                    set: { enabled in
                        var vacation = entry.wrappedValue.vacationCompensation!
                        vacation.pensionPremiumOverride = enabled
                            ? entry.wrappedValue.vacationPensionPremiumAmount
                            : nil
                        entry.wrappedValue.vacationCompensation = vacation
                    }
                ))
                if entry.wrappedValue.vacationCompensation?.pensionPremiumOverride != nil {
                    UIntField(
                        title: "Actual pension contribution for vacation payout",
                        value: vacationOptionalBinding(entry, \.pensionPremiumOverride),
                        suffix: "SEK"
                    )
                }
            }
        }
    }

    private func pensionCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Employer tjänstepension", systemImage: "chart.line.uptrend.xyaxis") {
            Toggle("Treat this salary as pensionable", isOn: entry.includedInPensionSalaryBasis)
            Toggle("Calculate employer contribution", isOn: Binding(
                get: { entry.wrappedValue.regularPensionPremium != nil },
                set: { entry.wrappedValue.regularPensionPremium = $0 ? RegularPensionPremium() : nil }
            ))
            if entry.wrappedValue.regularPensionPremium != nil {
                Text("Benchmark: 4.5% through 52,125 SEK/month, then 30%.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                let monthly = entry.wrappedValue.kind == .annualSalary
                    ? entry.wrappedValue.amount / 12
                    : entry.wrappedValue.amount
                LabeledContent("Monthly benchmark", value: formatSEK(RegularPensionPremium.benchmarkMonthly(monthly)))
                Toggle("Use actual monthly pension contribution", isOn: Binding(
                    get: { entry.wrappedValue.regularPensionPremium?.monthlyOverride != nil },
                    set: { enabled in
                        var premium = entry.wrappedValue.regularPensionPremium!
                        premium.monthlyOverride = enabled
                            ? RegularPensionPremium.benchmarkMonthly(monthly)
                            : nil
                        entry.wrappedValue.regularPensionPremium = premium
                    }
                ))
                if entry.wrappedValue.regularPensionPremium?.monthlyOverride != nil {
                    UIntField(
                        title: "Actual monthly pension contribution",
                        value: pensionOverrideBinding(entry),
                        suffix: "SEK"
                    )
                }
                LabeledContent("Contribution for period", value: formatSEK(entry.wrappedValue.regularPensionPremiumAmount))
                    .fontWeight(.semibold)
            }
            if plan.adjustmentPercent != nil {
                Divider()
                Toggle("Use full-year projection as jämkning basis", isOn: entry.useFullYearProjectionAsAdjustmentBasis)
                if entry.wrappedValue.useFullYearProjectionAsAdjustmentBasis {
                    Text("Basis: \(formatSEK(entry.wrappedValue.fullYearAdjustmentBasisAmount))")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.taxAmber)
                }
            }
        }
    }

    private func salaryExchangeCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Salary exchange", systemImage: "arrow.left.arrow.right") {
            Toggle("Treat this payment as pensionable", isOn: entry.includedInPensionSalaryBasis)
            Toggle("Exchange part for tjänstepension", isOn: Binding(
                get: { entry.wrappedValue.salaryExchange != nil },
                set: { enabled in
                    entry.wrappedValue.salaryExchange = enabled ? SalaryExchange() : nil
                    if enabled, let maximum = plan.salaryExchangeAllowance(for: entryID)?.maximumSacrifice {
                        entry.wrappedValue.salaryExchange?.sacrificedSalary = maximum
                    }
                }
            ))
            if entry.wrappedValue.salaryExchange != nil {
                Toggle("Employer adds uplift", isOn: salaryExchangeBoolBinding(entry, \.employerAddsUplift, default: true))
                if entry.wrappedValue.salaryExchange?.employerAddsUplift == true {
                    BasisPointsPercentageField(
                        title: "Employer uplift",
                        basisPoints: salaryExchangeBinding(
                            entry,
                            \.upliftBasisPoints,
                            default: SalaryExchange.defaultUpliftBasisPoints
                        )
                    )
                }
                if let allowance = plan.salaryExchangeAllowance(for: entryID) {
                    ValueRows(rows: [
                        ValueRow("Pensionable salary before exchange", formatSEK(allowance.pensionSalaryBasisBefore)),
                        ValueRow("Pensionable salary after exchange", formatSEK(allowance.pensionSalaryBasisAfter)),
                        ValueRow("35% contribution ceiling", formatSEK(allowance.ceiling)),
                        ValueRow("Contribution room", formatSEK(allowance.availableContribution))
                    ])
                    UIntField(
                        title: "Salary to exchange",
                        value: salaryExchangeBinding(entry, \.sacrificedSalary, default: 0),
                        suffix: "SEK",
                        maximum: allowance.maximumSacrifice
                    )
                    Button("Use maximum: \(formatSEK(allowance.maximumSacrifice))") {
                        entry.wrappedValue.salaryExchange?.sacrificedSalary = allowance.maximumSacrifice
                    }
                    .buttonStyle(.bordered)
                }
                LabeledContent("Resulting pension contribution", value: formatSEK(entry.wrappedValue.salaryExchangePensionContribution))
                    .fontWeight(.semibold)
                LabeledContent("Taxable cash payment", value: formatSEK(entry.wrappedValue.totalAnnualAmount))
            }
            Text("Indicative current-year main-rule estimate: employer pension contributions are limited to 35% of pensionable salary, capped at 592,000 SEK for 2026.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func withholdingCard(_ entry: Binding<IncomeEntry>) -> some View {
        EditorCard(title: "Preliminary withholding", systemImage: "building.columns") {
            Toggle("Use actual tax withheld", isOn: Binding(
                get: { entry.wrappedValue.actualWithholding != nil },
                set: { enabled in
                    entry.wrappedValue.actualWithholding = enabled ? 0 : nil
                    if enabled { entry.wrappedValue.additionalWithholdingPerPayment = nil }
                }
            ))
            Text("Use the known SEK amount shown on the payslip. This replaces the app's table, 30%, jämkning, and additional-withholding calculation for this entry.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if entry.wrappedValue.actualWithholding != nil {
                UIntField(
                    title: "Actual tax withheld",
                    value: Binding(
                        get: { entry.wrappedValue.actualWithholding ?? 0 },
                        set: { entry.wrappedValue.actualWithholding = $0 }
                    ),
                    suffix: "SEK",
                    maximum: 100_000_000
                )
            }
            if entry.wrappedValue.kind.isDividend {
                Text("Without an entered actual amount, no preliminary withholding is assumed. The app adds 20% final tax for dividends within gränsbelopp.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Payer", selection: Binding(
                    get: { entry.wrappedValue.payerRole },
                    set: {
                        entry.wrappedValue.setPayerRole(
                            $0,
                            adjustmentAvailable: plan.adjustmentPercent != nil
                        )
                    }
                )) {
                    Text("Main payer — table").tag(PayerRole.main)
                    Text("Secondary payer — 30%").tag(PayerRole.secondary)
                }
                .pickerStyle(.menu)
                if plan.adjustmentPercent != nil {
                    Toggle("Use jämkning", isOn: entry.adjustmentApplies)
                }
                Toggle("Add voluntary extra withholding", isOn: Binding(
                    get: { entry.wrappedValue.additionalWithholdingPerPayment != nil },
                    set: { enabled in
                        entry.wrappedValue.additionalWithholdingPerPayment = enabled ? 1_000 : nil
                        if enabled { entry.wrappedValue.actualWithholding = nil }
                    }
                ))
                Text("Enter the extra SEK you asked the payer to deduct from each payment. It is added on top of table tax, 30%, or jämkning to reduce expected residual tax.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if entry.wrappedValue.additionalWithholdingPerPayment != nil {
                    UIntField(
                        title: entry.wrappedValue.withholdingPaymentCount > 1
                            ? "Extra per payment"
                            : "Extra withholding",
                        value: Binding(
                            get: { entry.wrappedValue.additionalWithholdingPerPayment ?? 1_000 },
                            set: { entry.wrappedValue.additionalWithholdingPerPayment = $0 }
                        ),
                        suffix: "SEK"
                    )
                    if entry.wrappedValue.withholdingPaymentCount > 1 {
                        LabeledContent(
                            "Planned extra for period",
                            value: formatSEK(entry.wrappedValue.requestedAdditionalWithholding)
                        )
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            switch withholdingResult {
            case let .success(withholding?):
                Divider()
                LabeledContent("Calculated withholding", value: formatSEK(withholding.withheld))
                    .fontWeight(.semibold)
                Text(
                    withholding.additionalWithheld > 0
                        ? "\(withholding.rule.description) + \(formatSEK(withholding.additionalWithheld)) additional"
                        : withholding.rule.description
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .success(nil):
                EmptyView()
            case let .failure(error):
                Divider()
                Label("Tax data unavailable", systemImage: "doc.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func impactCard(_ entry: IncomeEntry) -> some View {
        EditorCard(title: "Entry impact", systemImage: "scope") {
            ValueRows(rows: impactRows(entry))
        }
    }

    private func impactRows(_ entry: IncomeEntry) -> [ValueRow] {
        var rows = [ValueRow("Cash income", formatSEK(entry.totalAnnualAmount))]
        if entry.vacationCompensationAmount > 0 {
            rows.append(
                ValueRow(
                    "of which vacation compensation",
                    formatSEK(entry.vacationCompensationAmount)
                )
            )
        }
        rows.append(contentsOf: [
            ValueRow("PGI / SGI", entry.kind.eligibility),
            ValueRow("Pensionable salary", formatSEK(entry.pensionSalaryBasisAmount)),
            ValueRow("Employer pension", formatSEK(
                entry.regularPensionPremiumAmount
                    .saturatingAdd(entry.vacationPensionPremiumAmount)
                    .saturatingAdd(entry.salaryExchangePensionContribution)
            ))
        ])
        return rows
    }

    private func updateSuggestedVacationDays(_ entry: Binding<IncomeEntry>) {
        guard var vacation = entry.wrappedValue.vacationCompensation else { return }
        vacation.payoutDays = VacationCompensation.suggestedDays(
            vacation.annualEntitlementDays,
            start: entry.wrappedValue.start,
            end: entry.wrappedValue.end
        )
        entry.wrappedValue.vacationCompensation = vacation
    }

    private func vacationBinding(
        _ entry: Binding<IncomeEntry>,
        _ keyPath: WritableKeyPath<VacationCompensation, UInt32>,
        default defaultValue: UInt32
    ) -> Binding<UInt32> {
        Binding(
            get: { entry.wrappedValue.vacationCompensation?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                guard var vacation = entry.wrappedValue.vacationCompensation else { return }
                vacation[keyPath: keyPath] = value
                entry.wrappedValue.vacationCompensation = vacation
            }
        )
    }

    private func vacationOptionalBinding(
        _ entry: Binding<IncomeEntry>,
        _ keyPath: WritableKeyPath<VacationCompensation, UInt32?>
    ) -> Binding<UInt32> {
        Binding(
            get: { entry.wrappedValue.vacationCompensation?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard var vacation = entry.wrappedValue.vacationCompensation else { return }
                vacation[keyPath: keyPath] = value
                entry.wrappedValue.vacationCompensation = vacation
            }
        )
    }

    private func pensionOverrideBinding(_ entry: Binding<IncomeEntry>) -> Binding<UInt32> {
        Binding(
            get: { entry.wrappedValue.regularPensionPremium?.monthlyOverride ?? 0 },
            set: { value in
                guard var premium = entry.wrappedValue.regularPensionPremium else { return }
                premium.monthlyOverride = value
                entry.wrappedValue.regularPensionPremium = premium
            }
        )
    }

    private func salaryExchangeBinding(
        _ entry: Binding<IncomeEntry>,
        _ keyPath: WritableKeyPath<SalaryExchange, UInt32>,
        default defaultValue: UInt32
    ) -> Binding<UInt32> {
        Binding(
            get: { entry.wrappedValue.salaryExchange?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                guard var exchange = entry.wrappedValue.salaryExchange else { return }
                exchange[keyPath: keyPath] = value
                entry.wrappedValue.salaryExchange = exchange
            }
        )
    }

    private func salaryExchangeBoolBinding(
        _ entry: Binding<IncomeEntry>,
        _ keyPath: WritableKeyPath<SalaryExchange, Bool>,
        default defaultValue: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { entry.wrappedValue.salaryExchange?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                guard var exchange = entry.wrappedValue.salaryExchange else { return }
                exchange[keyPath: keyPath] = value
                entry.wrappedValue.salaryExchange = exchange
            }
        )
    }
}

extension Binding where Value == IncomePlan {
    /// Keeps an editor binding tied to an entry's identity rather than its array index.
    /// SwiftUI can read an outgoing view once more after the entry has been deleted, so
    /// the last known value is used for those reads and writes are ignored after removal.
    func incomeEntry(id: UInt64) -> Binding<IncomeEntry>? {
        guard let snapshot = wrappedValue.entries.first(where: { $0.id == id }) else {
            return nil
        }
        return Binding<IncomeEntry>(
            get: {
                wrappedValue.entries.first(where: { $0.id == id }) ?? snapshot
            },
            set: { updatedEntry in
                guard let index = wrappedValue.entries.firstIndex(where: { $0.id == id }) else {
                    return
                }
                wrappedValue.entries[index] = updatedEntry
            }
        )
    }
}

private struct TapOutsideKeyboardDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissUIView {
        KeyboardDismissUIView()
    }

    func updateUIView(_ uiView: KeyboardDismissUIView, context: Context) {}

    static func dismantleUIView(_ uiView: KeyboardDismissUIView, coordinator: Void) {
        uiView.uninstall()
    }
}

private final class KeyboardDismissUIView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var recognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissActiveKeyboard)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window !== installedWindow else { return }
        uninstall()
        installedWindow = window
        window?.addGestureRecognizer(recognizer)
    }

    func uninstall() {
        installedWindow?.removeGestureRecognizer(recognizer)
        installedWindow = nil
    }

    @objc private func dismissActiveKeyboard() {
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView: UIView? = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }
}
