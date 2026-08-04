import SwiftUI
import UIKit

private enum CalculationState {
    case available(PlanCalculation)
    case invalid(IncomePlanValidationIssue?)
    case taxDataUnavailable(String)

    var calculation: PlanCalculation? {
        guard case let .available(calculation) = self else { return nil }
        return calculation
    }

    var withholding: WithholdingSummary? { calculation?.withholding }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var table: UInt8
    @State private var ageGroup: TaxAgeGroup
    @State private var plan: IncomePlan
    @State private var editingEntryID: UInt64?
    @State private var helpTopic: HelpTopic?
    @State private var showingAbout = false
    @State private var showingTrace = false

    private var calculationState: CalculationState {
        if let issue = plan.validationIssue {
            return .invalid(issue)
        }
        do {
            guard let calculation = try TaxEngine.planCalculation(
                table: table,
                ageGroup: ageGroup,
                plan: plan
            ) else {
                return .invalid(nil)
            }
            return .available(calculation)
        } catch {
            return .taxDataUnavailable(error.localizedDescription)
        }
    }

    private var persistedState: PersistedAppState {
        PersistedAppState(table: table, ageGroup: ageGroup, plan: plan)
    }

    init() {
        let restored: PersistedAppState? = try? AppStateStore.live.load()
        let state = restored ?? PersistedAppState()
        _table = State(initialValue: state.table)
        _ageGroup = State(initialValue: state.ageGroup)
        _plan = State(initialValue: state.plan)
    }

    var body: some View {
        let calculationState = calculationState
        let stateToPersist = persistedState
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    hero
                    setupCard
                    incomePlanCard(withholding: calculationState.withholding)
                    adjustmentCard(calibration: calculationState.calculation?.adjustmentCalibration)

                    if let calculation = calculationState.calculation {
                        results(calculation)
                    } else {
                        unavailableCard(for: calculationState)
                    }

                    dividendAllowanceCard

                    Text("Preliminary estimate based on Skatteverket tables and SKV 433, edition 36.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.taxBackground)
            .navigationTitle("Swedish Tax")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                }
            }
            .sheet(item: $helpTopic) { topic in
                HelpSheet(topic: topic)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: Binding(
                get: { editingEntryID != nil },
                set: { if !$0 { editingEntryID = nil } }
            )) {
                if let editingEntryID {
                    IncomeEntryEditor(
                        plan: $plan,
                        entryID: editingEntryID,
                        table: table,
                        ageGroup: ageGroup
                    )
                }
            }
            .sheet(isPresented: $showingTrace) {
                if let calculation = calculationState.calculation {
                    CalculationTraceView(
                        plan: plan,
                        table: table,
                        calculation: calculation
                    )
                }
            }
        }
        .task(id: stateToPersist) {
            do {
                try await Task.sleep(for: .milliseconds(350))
                try AppStateStore.live.save(stateToPersist)
            } catch is CancellationError {
                // A newer edit superseded this pending save.
            } catch {
                assertionFailure("Unable to save income plan: \(error)")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            try? AppStateStore.live.save(persistedState)
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Swedish Tax 2026")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.taxPrimary)
                Text("Income plan and tax reconciliation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(TaxEngine.badgeText, systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.taxGreen)
            }
            Spacer(minLength: 12)
            Text("2026")
                .font(.caption.bold())
                .foregroundStyle(Color.taxAmber)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.taxAmber.opacity(0.1), in: Capsule())
        }
    }

    private var setupCard: some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Tax settings", systemImage: "slider.horizontal.3")
                    .font(.headline)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { settingFields }
                    VStack(alignment: .leading, spacing: 14) { settingFields }
                }
            }
        }
    }

    @ViewBuilder
    private var settingFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FieldLabel("Tax table")
                HelpButton { helpTopic = .table }
            }
            Picker("Tax table", selection: $table) {
                ForEach(TaxCalculator.minTaxTable...TaxCalculator.maxTaxTable, id: \.self) {
                    Text("Table \($0)").tag($0)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FieldLabel("Age at start of 2026")
                HelpButton { helpTopic = .age }
            }
            Picker("Age at start of 2026", selection: $ageGroup) {
                ForEach(TaxAgeGroup.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func incomePlanCard(withholding: WithholdingSummary?) -> some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Income plan", systemImage: "list.bullet.rectangle.portrait")
                        .font(.headline)
                    Spacer()
                    Menu {
                        ForEach(IncomeKind.allCases) { kind in
                            Button(kind.shortTitle) {
                                editingEntryID = plan.addEntry(kind: kind)
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                }

                ForEach(Array(plan.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    Button { editingEntryID = entry.id } label: {
                        IncomeEntryRow(
                            entry: entry,
                            withholding: withholding?.entries.first { $0.entryID == entry.id },
                            adjustmentPercent: plan.adjustmentPercent
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                let totals = plan.totals
                HStack(alignment: .firstTextBaseline) {
                    Text("Total cash income")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(formatSEK(totals.grossIncome))
                        .font(.headline.monospacedDigit())
                }
                Text("Salary \(formatSEK(totals.workIncome)) · pension \(formatSEK(totals.pensionIncome)) · dividend \(formatSEK(totals.dividendIncome))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func adjustmentCard(calibration: AdjustmentCalibration?) -> some View {
        let payerCount = plan.entries.filter {
            !$0.kind.isDividend && $0.adjustmentApplies
                && $0.actualWithholding == nil
        }.count
        let overriddenPayerCount = plan.entries.filter {
            !$0.kind.isDividend && $0.adjustmentApplies
                && $0.actualWithholding != nil
        }.count
        let applicationSummary = payerCount > 0
            ? "Applied to \(payerCount) \(payerCount == 1 ? "payer" : "payers")"
                + (overriddenPayerCount > 0 ? "; overridden on \(overriddenPayerCount)" : "")
            : overriddenPayerCount > 0
                ? "Overridden by custom or actual withholding on \(overriddenPayerCount) \(overriddenPayerCount == 1 ? "payer" : "payers")"
                : "Not applied to any payer"
        return TaxCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use a percentage jämkning decision", isOn: Binding(
                        get: { plan.adjustmentPercent != nil },
                        set: { plan.setAdjustmentEnabled($0) }
                    ))
                    if plan.adjustmentPercent != nil {
                        PercentageStepper(
                            title: "Decision withholding",
                            value: Binding(
                                get: { plan.adjustmentPercent ?? 30 },
                                set: { plan.adjustmentPercent = min($0, 100) }
                            )
                        )
                        Label(
                            applicationSummary,
                            systemImage: payerCount == 0
                                ? "exclamationmark.circle.fill"
                                : "checkmark.circle.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(payerCount == 0 ? Color.red : Color.taxAmber)
                        Text("Choose which payer sees the decision inside each income entry. A recurring salary can also supply its full-year basis for the final-tax projection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Label("Jämkning", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        HelpButton { helpTopic = .adjustment }
                        Spacer()
                        if let percent = plan.adjustmentPercent {
                            Text(
                                payerCount > 0
                                    ? "\(percent)% · \(payerCount) \(payerCount == 1 ? "payer" : "payers")"
                                        + (overriddenPayerCount > 0 ? " + \(overriddenPayerCount) overridden" : "")
                                    : overriddenPayerCount > 0
                                        ? "\(percent)% · overridden"
                                        : "\(percent)% · no payer"
                            )
                                .font(.caption.bold())
                                .foregroundStyle(Color.taxAmber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.taxAmber.opacity(0.12), in: Capsule())
                        }
                    }
                    if let calibration {
                        HStack(spacing: 5) {
                            Label("Full-year calibration", systemImage: "calendar.badge.clock")
                            Spacer(minLength: 8)
                            Text("Implied adjustment \(formatSignedSEK(-calibration.impliedTaxAdjustment))")
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.taxAmber)
                    }
                }
                .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
    }

    @ViewBuilder
    private func results(_ calculation: PlanCalculation) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tax result")
                    .font(.title3.bold())
                Spacer()
                Text("Table \(table) · columns \(ageGroup.salaryColumn.rawValue)/\(ageGroup.pensionColumn.rawValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.taxBlue)
            }

            ResultCard(
                title: calculation.adjustmentCalibration == nil
                    ? "Final tax estimate"
                    : "Jämkning-calibrated tax projection",
                value: formatSEK(calculation.totalTax),
                systemImage: "function",
                color: .taxGreen,
                detail: "Marginal tax: \(calculation.marginalRate.formatted(.number.precision(.fractionLength(1))))%",
                detailAction: { helpTopic = .marginalRate }
            )
            ResultCard(
                title: "Calculated withholding",
                value: formatSEK(calculation.withheldTax),
                systemImage: "building.columns.fill",
                color: .taxBlue,
                detail: "Cash after withholding: \(formatSEK(calculation.cashAfterWithholding))"
            )
            ResultCard(
                title: "Annual net after final tax",
                value: formatSEK(calculation.annualNet),
                systemImage: "banknote.fill",
                color: .taxPrimary,
                detail: taxBalanceSummary(calculation.taxBalance),
                detailColor: taxBalanceColor(calculation.taxBalance)
            )

            reconciliationCard(calculation)

            Button {
                showingTrace = true
            } label: {
                Label("Show calculation trace", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            monthlyReferenceCard(calculation)
            incomeBasisCard(calculation)
            annualBreakdownCard(calculation)
        }
    }

    private func reconciliationCard(_ calculation: PlanCalculation) -> some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Annual reconciliation", systemImage: "equal.circle")
                    .font(.headline)
                ValueRows(rows: reconciliationRows(calculation))
            }
        }
    }

    private func monthlyReferenceCard(_ calculation: PlanCalculation) -> some View {
        TaxCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reference only: annual taxable salary and pension divided by 12, then looked up as salary. Actual payer withholding is calculated entry by entry above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    ValueRows(rows: [
                        ValueRow("Average monthly income", formatSEK(calculation.monthlyIncome)),
                        ValueRow("Table deduction", deductionText(calculation.tableDeduction)),
                        ValueRow("Monthly cash after table tax", formatSEK(calculation.tableReferenceNet)),
                        ValueRow("Annualized table deduction", formatSEK(calculation.annualizedTableReferenceTax))
                    ])
                }
            } label: {
                Label("Monthly table reference", systemImage: "tablecells")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
    }

    private func incomeBasisCard(_ calculation: PlanCalculation) -> some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 5) {
                    Label("Income-basis ceilings", systemImage: "chart.bar.fill")
                        .font(.headline)
                    HelpButton { helpTopic = .incomeBases }
                }
                IncomeBasisRow(
                    title: "Allmän pension (PGI)",
                    estimate: calculation.pensionProgress,
                    color: .taxBlue
                )
                Divider()
                IncomeBasisRow(
                    title: "Estimated SGI",
                    estimate: calculation.sgiProgress,
                    color: .taxGreen
                )
            }
        }
    }

    private func annualBreakdownCard(_ calculation: PlanCalculation) -> some View {
        TaxCard {
            DisclosureGroup {
                VStack(spacing: 6) {
                    ValueRows(rows: annualRows(calculation.annualTax))
                    if let calibration = calculation.adjustmentCalibration {
                        Divider().padding(.vertical, 4)
                        Text("Jämkning calibration")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ValueRows(rows: calibrationRows(calibration))
                        Text(impliedAdjustmentExplanation(calibration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if calculation.dividendIncome > 0 {
                        Divider().padding(.vertical, 4)
                        ValueRows(rows: [
                            ValueRow("Own-AB dividend", formatSEK(calculation.dividendIncome)),
                            ValueRow("Dividend tax at 20%", formatSEK(calculation.dividendTax)),
                            ValueRow("Total final tax", formatSEK(calculation.totalTax), isTotal: true)
                        ])
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    calculation.adjustmentCalibration == nil
                        ? "Annual formula breakdown"
                        : "Annual tax projection breakdown",
                    systemImage: "list.bullet.rectangle"
                )
                .font(.headline)
                .foregroundStyle(.primary)
            }
            .tint(.secondary)
        }
    }

    @ViewBuilder
    private func unavailableCard(for state: CalculationState) -> some View {
        TaxCard {
            switch state {
            case .available:
                EmptyView()
            case let .invalid(issue):
                ContentUnavailableView(
                    "Calculation unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(validationMessage(for: issue))
                )
            case let .taxDataUnavailable(message):
                ContentUnavailableView(
                    "Tax data unavailable",
                    systemImage: "doc.badge.exclamationmark",
                    description: Text(message)
                )
            }
        }
    }

    private var dividendAllowanceCard: some View {
        TaxCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "One-person company — marked salary is total payroll",
                        isOn: $plan.dividendAllowance.onePersonCompany
                    )
                    BasisPointsPercentageField(
                        title: "Your ownership",
                        basisPoints: $plan.dividendAllowance.ownershipBasisPoints
                    )
                    BasisPointsPercentageField(
                        title: "Spouse ownership",
                        basisPoints: $plan.dividendAllowance.spouseOwnershipBasisPoints
                    )
                    BasisPointsPercentageField(
                        title: "Your ownership in other qualified companies",
                        basisPoints: $plan.dividendAllowance.otherQualifiedOwnershipBasisPoints,
                        maximumBasisPoints: 1_000_000
                    )
                    if !plan.dividendAllowance.onePersonCompany {
                        UIntField(
                            title: "Company/group payroll in 2026",
                            value: $plan.dividendAllowance.companyCashPayroll2026,
                            suffix: "SEK"
                        )
                        UIntField(
                            title: "Highest related person's salary",
                            value: $plan.dividendAllowance.highestRelatedCashSalary2026,
                            suffix: "SEK"
                        )
                    }
                    UIntField(
                        title: "Acquisition cost",
                        value: $plan.dividendAllowance.acquisitionCost,
                        suffix: "SEK"
                    )
                    UIntField(
                        title: "Saved allowance",
                        value: $plan.dividendAllowance.savedAllowance,
                        suffix: "SEK"
                    )

                    Divider()
                    dividendAllowanceResult
                    Text("The actual dividend also requires sufficient free equity, a prudence assessment, and a shareholder decision.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
                .padding(.trailing, 16)
            } label: {
                Label("Preliminary 2027 dividend allowance", systemImage: "building.2.crop.circle")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private var dividendAllowanceResult: some View {
        let result: Result<DividendAllowance2027, Error> = Result {
            try plan.dividendAllowance2027()
        }

        switch result {
        case let .success(allowance):
            LabeledContent("Maximum dividend at 20%", value: formatSEK(allowance.total))
                .fontWeight(.semibold)
            LabeledContent("Basic amount", value: formatSEK(allowance.basicAmount))
            LabeledContent("Wage-based allowance", value: formatSEK(allowance.wageAllowance))
            LabeledContent("Personal tax if fully used", value: formatSEK(allowance.taxAtTwentyPercent))
            LabeledContent("Net after 20% tax", value: formatSEK(allowance.netAfterTwentyPercentTax))
                .fontWeight(.semibold)
            Text("Marked 2026 own-company salary: \(formatSEK(allowance.ownerCashSalary)). Dividend paid in 2027 is declared on K10 in 2028.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .failure(error):
            if let issue = error as? DividendAllowanceIssue {
                Label(dividendAllowanceIssueText(issue), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Label("Unable to calculate the allowance.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func dividendAllowanceIssueText(_ issue: DividendAllowanceIssue) -> String {
        switch issue {
        case .ownershipExceedsOneHundredPercent:
            "Your ownership in this company cannot exceed 100%."
        case .spouseOwnershipExceedsCompany:
            "Your and your spouse's combined ownership cannot exceed 100%."
        case .personalSalaryExceedsCompanyPayroll:
            "Owner or related-person salary cannot exceed company/group payroll."
        case .missingAcquisitionCostInterestRate:
            "The exact 2027 acquisition-cost interest rate is not known until 30 November 2026."
        }
    }

    private func validationMessage(for issue: IncomePlanValidationIssue?) -> String {
        switch issue {
        case .invalidPaymentPeriod:
            "Check that each payment period's last day is on or after its first day."
        case let .salaryExchangeExceedsAllowance(_, maximum):
            "Salary exchange exceeds the current maximum of \(formatSEK(maximum)). Open the entry and reduce it."
        case nil:
            "Check the income-plan values and try again."
        }
    }

    private func reconciliationRows(_ value: PlanCalculation) -> [ValueRow] {
        let vacationCompensation = plan.entries.reduce(UInt32(0)) {
            $0.saturatingAdd($1.vacationCompensationAmount)
        }
        var rows = [
            ValueRow("Taxable salary and pension", formatSEK(value.ordinaryIncome)),
            ValueRow("Own-AB dividend", formatSEK(value.dividendIncome)),
            ValueRow("Employer pension contributions", formatSEK(value.employerPensionContributions)),
            ValueRow("Final tax estimate", formatSEK(value.totalTax)),
            ValueRow("Preliminary tax withheld", formatCredit(value.withheldTax)),
            ValueRow("Cash after withholding", formatSEK(value.cashAfterWithholding))
        ]
        if value.salaryExchangeSacrifice > 0 {
            rows.insert(ValueRow("Salary exchanged", formatCredit(value.salaryExchangeSacrifice)), at: 2)
        }
        if vacationCompensation > 0 {
            rows.insert(
                ValueRow("of which vacation compensation", formatSEK(vacationCompensation)),
                at: 1
            )
        }
        rows.append(ValueRow(
            "Expected balance",
            taxBalanceValue(value.taxBalance),
            isTotal: true,
            valueColor: taxBalanceColor(value.taxBalance),
            detail: taxBalanceKind(value.taxBalance)
        ))
        return rows
    }

    private func annualRows(_ tax: AnnualTax) -> [ValueRow] {
        [
            ValueRow("Assessed income", formatSEK(tax.assessedIncome)),
            ValueRow("Basic allowance", formatCredit(tax.basicAllowance)),
            ValueRow("Taxable income", formatSEK(tax.taxableIncome)),
            ValueRow("State income tax", formatSEK(tax.stateIncomeTax)),
            ValueRow("Municipal income tax", formatSEK(tax.municipalIncomeTax)),
            ValueRow("Burial and religious fee", formatSEK(tax.burialAndReligiousFee)),
            ValueRow("Pension fee", formatSEK(tax.pensionFee)),
            ValueRow("Pension fee credit", formatCredit(tax.pensionFeeCredit)),
            ValueRow("Work income credit", formatCredit(tax.workIncomeCredit)),
            ValueRow("Sickness compensation credit", formatCredit(tax.sicknessCompensationCredit)),
            ValueRow("Earned income credit", formatCredit(tax.earnedIncomeCredit)),
            ValueRow("Public service fee", formatSEK(tax.publicServiceFee)),
            ValueRow("Formula tax", formatSEK(tax.total), isTotal: true)
        ]
    }

    private func calibrationRows(_ value: AdjustmentCalibration) -> [ValueRow] {
        [
            ValueRow("Full-year basis", formatSEK(value.basisIncome)),
            ValueRow("Formula tax at basis", formatSEK(value.formulaTaxAtBasis)),
            ValueRow("Assumed tax at \(value.percent)%", formatSEK(value.assumedTaxAtBasis)),
            ValueRow("Implied adjustment", formatSignedSEK(-value.impliedTaxAdjustment)),
            ValueRow("Projected salary/pension tax", formatSEK(value.projectedOrdinaryTax), isTotal: true)
        ]
    }
}

private struct IncomeEntryRow: View {
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

private struct IncomeEntryEditor: View {
    @Binding var plan: IncomePlan
    let entryID: UInt64
    let table: UInt8
    let ageGroup: TaxAgeGroup
    @Environment(\.dismiss) private var dismiss

    private var entry: Binding<IncomeEntry>? { $plan.incomeEntry(id: entryID) }

    private var withholdingResult: Result<EntryWithholding?, Error> {
        Result {
            try plan.estimatedWithholding(table: table, ageGroup: ageGroup)
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

private struct CalculationTraceView: View {
    let plan: IncomePlan
    let table: UInt8
    let calculation: PlanCalculation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TraceStep(number: 1, title: "Cash income") {
                        ForEach(plan.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                ValueRows(rows: [ValueRow(
                                    entry.description.isEmpty ? entry.kind.shortTitle : entry.description,
                                    formatSEK(entry.totalAnnualAmount)
                                )])
                                if entry.vacationCompensationAmount > 0 {
                                    Text("Includes \(formatSEK(entry.vacationCompensationAmount)) vacation compensation")
                                        .font(.caption)
                                        .foregroundStyle(Color.taxGreen)
                                }
                                if entry.salaryExchangeSacrifice > 0 {
                                    Text("After \(formatSEK(entry.salaryExchangeSacrifice)) salary exchange")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if entry.fullYearAdjustmentBasisAmount > 0 {
                                    Label(
                                        "Full-year jämkning basis: \(formatSEK(entry.fullYearAdjustmentBasisAmount))",
                                        systemImage: "calendar.badge.clock"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.taxAmber)
                                }
                            }
                        }
                        ValueRows(rows: [ValueRow("Total", formatSEK(calculation.annualIncome), isTotal: true)])
                    }
                    TraceStep(number: 2, title: "Payer withholding") {
                        let withholding = calculation.withholding
                        ForEach(withholding.entries, id: \.entryID) { row in
                            if let entry = plan.entries.first(where: { $0.id == row.entryID }) {
                                WithholdingTraceRow(entry: entry, row: row, table: table)
                            }
                        }
                        ValueRows(rows: [ValueRow("Total withheld", formatSEK(withholding.total), isTotal: true)])
                    }
                    TraceStep(number: 3, title: "Annual formula") {
                        Text("\(formatSEK(plan.totals.workIncome)) work income + \(formatSEK(plan.totals.pensionIncome)) pension income")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ValueRows(rows: [ValueRow("Formula tax", formatSEK(calculation.annualTax.total), isTotal: true)])
                    }
                    TraceStep(number: 4, title: "Final-tax projection") {
                        if let calibration = calculation.adjustmentCalibration {
                            Label(
                                "Full-year jämkning calibration · \(calibration.percent)%",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.taxAmber)
                            Text("The selected full-year salary projection calibrates the formula tax applied to the actual payment-period income.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(plan.entries.filter { $0.fullYearAdjustmentBasisAmount > 0 }) { entry in
                                LabeledContent(
                                    "Basis from \(entry.description.isEmpty ? entry.kind.shortTitle : entry.description)",
                                    value: formatSEK(entry.fullYearAdjustmentBasisAmount)
                                )
                                .font(.caption)
                            }
                            ValueRows(rows: [
                                ValueRow("Full-year basis", formatSEK(calibration.basisIncome)),
                                ValueRow("Formula tax at basis", formatSEK(calibration.formulaTaxAtBasis)),
                                ValueRow(
                                    "Assumed tax at \(calibration.percent)%",
                                    formatSEK(calibration.assumedTaxAtBasis)
                                ),
                                ValueRow(
                                    "Implied adjustment",
                                    formatSignedSEK(-calibration.impliedTaxAdjustment)
                                ),
                                ValueRow("Actual-period formula tax", formatSEK(calculation.annualTax.total)),
                                ValueRow(
                                    "Projected salary and pension tax",
                                    formatSEK(calculation.ordinaryFinalTax),
                                    isTotal: true
                                )
                            ])
                            Text(impliedAdjustmentExplanation(calibration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ValueRows(rows: [
                                ValueRow("Salary and pension tax", formatSEK(calculation.ordinaryFinalTax))
                            ])
                        }
                        ValueRows(rows: [
                            ValueRow("Dividend tax", formatSEK(calculation.dividendTax)),
                            ValueRow("Total final tax", formatSEK(calculation.totalTax), isTotal: true)
                        ])
                    }
                    TraceStep(number: 5, title: "Expected balance") {
                        if let calibration = calculation.adjustmentCalibration {
                            let formulaChange = Int64(calculation.annualTax.total)
                                - Int64(calibration.formulaTaxAtBasis)
                            let withholdingChange = Int64(calculation.withheldTax)
                                - Int64(calibration.assumedTaxAtBasis)
                            let ordinaryBalance = formulaChange - withholdingChange
                            Text("The projected income is treated as the zero-balance anchor. The expected balance is how much faster annual formula tax changes than withholding under the original jämkning.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ValueRows(rows: [
                                ValueRow(
                                    "Formula-tax change from projection",
                                    formatSignedSEK(formulaChange)
                                ),
                                ValueRow(
                                    "Withholding change from projection",
                                    formatSignedSEK(withholdingChange)
                                ),
                                ValueRow(
                                    "Formula change minus withholding change",
                                    formatSignedSEK(ordinaryBalance)
                                )
                            ])
                            if calculation.dividendTax > 0 {
                                ValueRows(rows: [
                                    ValueRow("Dividend tax", formatSEK(calculation.dividendTax))
                                ])
                            }
                        } else {
                            Text("Final tax minus preliminary withholding")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ValueRows(rows: [ValueRow(
                            "Expected balance",
                            taxBalanceValue(calculation.taxBalance),
                            isTotal: true,
                            valueColor: taxBalanceColor(calculation.taxBalance),
                            detail: taxBalanceKind(calculation.taxBalance)
                        )])
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color.taxBackground)
            .navigationTitle("Calculation trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WithholdingTraceRow: View {
    let entry: IncomeEntry
    let row: EntryWithholding
    let table: UInt8

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent(title, value: formatSEK(row.withheld))
                .fontWeight(.semibold)
            Label(ruleTitle, systemImage: ruleIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ruleColor)
            ForEach(Array(explanationLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }

    private var title: String {
        entry.description.isEmpty ? entry.kind.shortTitle : entry.description
    }

    private var ruleTitle: String {
        let base: String
        switch row.rule {
        case .actualAmount:
            base = "Entered actual withholding"
        case let .table(column):
            base = "Main payer · table \(table), column \(column.rawValue)"
        case let .tableAndOneTime(column, percent):
            base = "Main payer · table \(table), column \(column.rawValue) + one-time \(percent)%"
        case let .oneTimeTable(percent):
            base = "Main payer · one-time table \(percent)%"
        case .secondary30:
            base = "Secondary payer · 30%"
        case let .adjustmentPercent(percent):
            base = "\(entry.payerRole.rawValue) · jämkning decision \(percent)%"
        case .none:
            base = "No preliminary withholding"
        }
        return row.additionalWithheld > 0
            ? "\(base) + \(formatSEK(row.additionalWithheld)) extra"
            : base
    }

    private var ruleIcon: String {
        switch row.rule {
        case .actualAmount: "checkmark.circle"
        case .adjustmentPercent: "arrow.triangle.2.circlepath"
        case .secondary30: "building.2"
        case .none: "minus.circle"
        default: "tablecells"
        }
    }

    private var ruleColor: Color {
        if case .adjustmentPercent = row.rule { return .taxAmber }
        return .taxBlue
    }

    private var explanationLines: [String] {
        let baseWithheld = row.withheld.saturatingSubtract(row.additionalWithheld)
        var lines: [String]
        switch row.rule {
        case .actualAmount:
            lines = ["Actual tax withheld entered for this income row."]
        case let .adjustmentPercent(percent):
            lines = [percentageCalculation(
                gross: row.gross,
                percent: percent,
                withheld: baseWithheld
            )]
        case .secondary30:
            lines = [percentageCalculation(
                gross: row.gross,
                percent: 30,
                withheld: baseWithheld
            )]
        case let .oneTimeTable(percent):
            lines = [
                "Rate selected from total annual work income.",
                percentageCalculation(gross: row.gross, percent: percent, withheld: baseWithheld)
            ]
        case let .table(column):
            lines = [regularTableExplanation(column: column, withheld: row.regularWithheld)]
        case let .tableAndOneTime(column, percent):
            let vacation = entry.vacationCompensationAmount
            lines = [
                regularTableExplanation(column: column, withheld: row.regularWithheld),
                "Vacation pay: \(formatSEK(vacation)) × \(percent)% = \(formatSEK(row.supplementalWithheld))",
                "Combined withholding: \(formatSEK(row.regularWithheld)) + \(formatSEK(row.supplementalWithheld)) = \(formatSEK(baseWithheld))"
            ]
        case .none:
            lines = [entry.kind.isDividend
                ? "Own-company dividends are assumed to have no payer withholding."
                : "No withholding rule applies to this income."]
        }
        guard row.additionalWithheld > 0 else { return lines }

        if row.additionalWithheld < entry.requestedAdditionalWithholding {
            lines.append(
                "Additional withholding is limited to \(formatSEK(row.additionalWithheld)) so total withholding does not exceed gross income."
            )
        } else if entry.withholdingPaymentCount > 1 {
            lines.append(
                "Additional withholding: \(formatSEK(entry.additionalWithholdingPerPayment ?? 0)) × \(entry.withholdingPaymentCount) payments = \(formatSEK(row.additionalWithheld))"
            )
        } else {
            lines.append("Additional withholding: \(formatSEK(row.additionalWithheld))")
        }
        lines.append(
            "Total withholding: \(formatSEK(baseWithheld)) + \(formatSEK(row.additionalWithheld)) = \(formatSEK(row.withheld))"
        )
        return lines
    }

    private func percentageCalculation(
        gross: UInt32,
        percent: UInt32,
        withheld: UInt32
    ) -> String {
        "\(formatSEK(gross)) × \(percent)% = \(formatSEK(withheld))"
    }

    private func regularTableExplanation(column: TaxColumn, withheld: UInt32) -> String {
        if entry.kind.isMonthly {
            return "Each active month is looked up in table \(table), column \(column.rawValue); deductions total \(formatSEK(withheld))."
        }
        return "Annual income ÷ 12 is looked up in table \(table), column \(column.rawValue), then annualized to \(formatSEK(withheld))."
    }
}

private struct TraceStep<Content: View>: View {
    let number: Int
    let title: String
    let content: Content

    init(number: Int, title: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.content = content()
    }

    var body: some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(number))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Color.taxBlue, in: Circle())
                    Text(title).font(.headline)
                }
                content
            }
        }
    }
}

private struct Date2026Field: View {
    let title: String
    @Binding var value: Date2026

    init(title: String, value: Binding<Date2026>) {
        self.title = title
        _value = value
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Picker("Month", selection: $value.month) {
                    ForEach(UInt8(1)...UInt8(12), id: \.self) { month in
                        Text(monthName(month)).tag(month)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(title) month")

                Picker("Day", selection: $value.day) {
                    ForEach(UInt8(1)...Date2026.daysInMonth(value.month), id: \.self) { day in
                        Text(String(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(title) day")

                Text("2026")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.taxField, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.taxBorder, lineWidth: 0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .onChange(of: value.month) { _, newMonth in
            value.day = min(value.day, Date2026.daysInMonth(newMonth))
        }
    }
}

private struct SelectAllTextField: View {
    let prompt: String
    @Binding var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        TextField(
            text: $text,
            selection: $selection,
            prompt: Text(prompt)
        ) {
            Text(prompt)
        }
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { selectAll() }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }
}

private struct UIntField: View {
    let title: String
    @Binding var value: UInt32
    let suffix: String
    let maximum: UInt32
    @State private var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(
        title: String,
        value: Binding<UInt32>,
        suffix: String,
        maximum: UInt32 = 100_000_000
    ) {
        self.title = title
        _value = value
        self.suffix = suffix
        self.maximum = maximum
        _text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                TextField(
                    text: $text,
                    selection: $selection,
                    prompt: Text("0")
                ) {
                    Text(title)
                }
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 70)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = String(value)
                        selectAll()
                    } else {
                        text = String(value)
                    }
                }
                .onChange(of: text) { _, newText in
                    updateValue(from: newText)
                }
                .onChange(of: value) { _, newValue in
                    if !isFocused { text = String(newValue) }
                }
                Text(suffix)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func updateValue(from newText: String) {
        let digits = newText.filter { $0.isASCII && $0.isNumber }
        if digits != newText {
            text = digits
            return
        }
        guard !digits.isEmpty else {
            value = 0
            return
        }

        let parsed = UInt64(digits) ?? UInt64(maximum)
        let limited = UInt32(min(parsed, UInt64(maximum)))
        value = limited
        if parsed > UInt64(maximum) { text = String(limited) }
    }
}

private struct BasisPointsPercentageField: View {
    let title: String
    @Binding var basisPoints: UInt32
    let maximumBasisPoints: UInt32
    @State private var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(
        title: String,
        basisPoints: Binding<UInt32>,
        maximumBasisPoints: UInt32 = 10_000
    ) {
        self.title = title
        _basisPoints = basisPoints
        self.maximumBasisPoints = maximumBasisPoints
        _text = State(initialValue: formatBasisPointsPercentage(basisPoints.wrappedValue))
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                TextField(
                    text: $text,
                    selection: $selection,
                    prompt: Text("0")
                ) { Text(title) }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 70)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = formatBasisPointsPercentage(basisPoints)
                        selectAll()
                    } else {
                        text = formatBasisPointsPercentage(basisPoints)
                    }
                }
                .onChange(of: text) { _, newText in updateValue(from: newText) }
                .onChange(of: basisPoints) { _, newValue in
                    if !isFocused { text = formatBasisPointsPercentage(newValue) }
                }
                Text("%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func updateValue(from input: String) {
        let sanitized = sanitizePercentageText(input)
        if sanitized != input {
            text = sanitized
            return
        }
        guard let parsed = parseBasisPointsPercentage(sanitized) else { return }
        let limited = min(parsed, maximumBasisPoints)
        basisPoints = limited
        if parsed > maximumBasisPoints {
            text = formatBasisPointsPercentage(limited)
        }
    }
}

private struct PercentageStepper: View {
    let title: String
    @Binding var value: UInt32

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                Button {
                    if value > 0 { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 40, height: 36)
                }
                .disabled(value == 0)
                .accessibilityLabel("Decrease percentage")

                Text("\(value)%")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 58, minHeight: 36)
                    .overlay(alignment: .leading) { Divider() }
                    .overlay(alignment: .trailing) { Divider() }
                    .accessibilityLabel("\(value) percent")

                Button {
                    if value < 100 { value += 1 }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 40, height: 36)
                }
                .disabled(value == 100)
                .accessibilityLabel("Increase percentage")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.taxBlue)
            .background(Color.taxField, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.taxBorder, lineWidth: 0.75)
            }
        }
    }
}

private struct EditorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        TaxCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage).font(.headline)
                content
            }
        }
    }
}

private struct TaxCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.taxSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.taxBorder, lineWidth: 0.75)
            }
    }
}

private struct ResultCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    var detail: String?
    var detailColor: Color = .primary
    var detailAction: (() -> Void)?

    var body: some View {
        TaxCard {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.72)
                    if let detail {
                        Group {
                            if let detailAction {
                                Button(action: detailAction) {
                                    Label(detail, systemImage: "questionmark.circle")
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(detail)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(detailColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct HelpButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Color.taxBlue)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
    }
}

private struct ValueRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let isTotal: Bool
    let valueColor: Color
    let detail: String?

    init(
        _ label: String,
        _ value: String,
        isTotal: Bool = false,
        valueColor: Color = .primary,
        detail: String? = nil
    ) {
        self.label = label
        self.value = value
        self.isTotal = isTotal
        self.valueColor = valueColor
        self.detail = detail
    }
}

private struct ValueRows: View {
    let rows: [ValueRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .foregroundStyle(row.isTotal ? .primary : .secondary)
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.value)
                            .fontWeight(row.isTotal ? .bold : .semibold)
                            .multilineTextAlignment(.trailing)
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(row.valueColor)
                }
                .font(row.isTotal ? .body : .subheadline)
                .padding(.vertical, row.isTotal ? 11 : 9)
            }
        }
    }
}

private struct IncomeBasisRow: View {
    let title: String
    let estimate: IncomeBasisEstimate
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            switch estimate {
            case let .estimated(progress):
                let percent = progress.percentOfMaximum
                HStack(alignment: .firstTextBaseline) {
                    Text(percent.formatted(.number.precision(.fractionLength(1))) + "%")
                        .font(.title3.bold())
                        .foregroundStyle(color)
                    Spacer()
                    Text("of 2026 maximum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(percent, 100), total: 100).tint(color)
                Text("\(formatSEK(progress.estimatedBasis)) / \(formatSEK(progress.maximumBasis))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .notBasedOnSelectedIncome:
                Text("Selected income does not establish this basis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .requiresAdditionalInformation:
                Text("Additional income information is required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum HelpTopic: String, Identifiable {
    case table, age, adjustment, marginalRate, incomeBases
    var id: Self { self }
}

private struct HelpSheet: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch topic {
                    case .table:
                        Text("Find your tax table").font(.title2.bold())
                        Text("Your A-tax certificate from Skatteverket states which table your payer should use. It is normally based on where you were registered on 1 November of the preceding year.")
                    case .age:
                        Text("Age and table columns").font(.title2.bold())
                        Text("Under 66 uses column 1 for salary and column 6 for pension. Age 66 or older uses column 3 for salary and column 2 for pension. Age is determined at the start of the income year.")
                    case .adjustment:
                        Text("Jämkning").font(.title2.bold())
                        Text("Enter the percentage from a Skatteverket decision and mark the payers that received it. A full-year recurring salary basis can calibrate the annual projection while the entered dates still control actual cash income.")
                    case .marginalRate:
                        Text("Marginal tax").font(.title2.bold())
                        Text("The app adds 12,000 SEK of annual work income and compares the two annual formula results. The additional tax is shown as a percentage.")
                    case .incomeBases:
                        Text("PGI and SGI estimates").font(.title2.bold())
                        Text("PGI uses aggregate pensionable work income after the general pension fee. SGI uses the annualized rate of recurring salary. Försäkringskassan determines actual SGI.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    Label("Income year 2026", systemImage: "calendar")
                    Label("Tables 29–42", systemImage: "tablecells")
                    Label("SKV 433, edition 36", systemImage: "doc.text")
                    Label(
                        "Calculation engine: \(TaxEngine.badgeText)",
                        systemImage: "checkmark.seal"
                    )
                    Label("Works entirely offline", systemImage: "lock.shield")
                }
                Section("Included planning features") {
                    Text("Multiple salary, pension, one-time payment, and own-AB dividend entries")
                    Text("Payer withholding, jämkning, vacation compensation, occupational pension, and salary exchange")
                }
                Section("Important") {
                    Text("This is a preliminary calculation using published-table assumptions. It is not an individualized final tax, pension, SGI, or salary-exchange assessment.")
                }
                Section("Official sources") {
                    Link("SKV 433 technical specification", destination: URL(string: "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf")!)
                    Link("Skatteverket monthly tables", destination: URL(string: "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt")!)
                    Link("2026 pensionable income (PGI)", destination: URL(string: "https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html")!)
                    Link("Sickness-benefit qualifying income (SGI)", destination: URL(string: "https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi")!)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

func formatBasisPointsPercentage(_ basisPoints: UInt32) -> String {
    let wholePercent = basisPoints / 100
    let fractionalPercent = basisPoints % 100
    if fractionalPercent == 0 { return String(wholePercent) }
    if fractionalPercent.isMultiple(of: 10) {
        return "\(wholePercent).\(fractionalPercent / 10)"
    }
    let fraction = fractionalPercent < 10
        ? "0\(fractionalPercent)"
        : String(fractionalPercent)
    return "\(wholePercent).\(fraction)"
}

func parseBasisPointsPercentage(_ text: String) -> UInt32? {
    if text.isEmpty { return 0 }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          parts.allSatisfy({ part in
              part.allSatisfy { $0.isASCII && $0.isNumber }
          }),
          parts.count == 1 || parts[1].count <= 2
    else { return nil }

    let wholeText = String(parts[0])
    let wholePercent = wholeText.isEmpty ? 0 : UInt64(wholeText)
    guard let wholePercent,
          wholePercent <= UInt64(UInt32.max) / 100
    else { return nil }

    let fractionalText = parts.count == 2 ? String(parts[1]) : ""
    let fractionalBasisPoints: UInt64
    switch fractionalText.count {
    case 0:
        fractionalBasisPoints = 0
    case 1:
        guard let digit = UInt64(fractionalText) else { return nil }
        fractionalBasisPoints = digit * 10
    case 2:
        guard let digits = UInt64(fractionalText) else { return nil }
        fractionalBasisPoints = digits
    default:
        return nil
    }

    let total = wholePercent * 100 + fractionalBasisPoints
    guard total <= UInt64(UInt32.max) else { return nil }
    return UInt32(total)
}

private func sanitizePercentageText(_ input: String) -> String {
    var output = ""
    var hasSeparator = false
    var fractionalDigits = 0
    for character in input {
        if character.isASCII, character.isNumber {
            if !hasSeparator || fractionalDigits < 2 {
                output.append(character)
                if hasSeparator { fractionalDigits += 1 }
            }
        } else if (character == "." || character == ","), !hasSeparator {
            output.append(".")
            hasSeparator = true
        }
    }
    return output
}

private func groupedDigits(_ value: UInt32) -> String {
    let digits = String(value)
    var output = ""
    for (index, character) in digits.enumerated() {
        if index > 0, (digits.count - index).isMultiple(of: 3) { output.append(" ") }
        output.append(character)
    }
    return output
}

private func formatSEK(_ value: UInt32) -> String { "\(groupedDigits(value)) SEK" }
private func formatCredit(_ value: UInt32) -> String { value == 0 ? formatSEK(0) : "−\(formatSEK(value))" }
private func formatSignedSEK(_ value: Int64) -> String {
    if value > 0 { return "+\(formatSEK(UInt32(value)))" }
    if value < 0 { return "−\(formatSEK(UInt32(-value)))" }
    return formatSEK(0)
}
private func impliedAdjustmentExplanation(_ calibration: AdjustmentCalibration) -> String {
    "Assumed tax \(formatSEK(calibration.assumedTaxAtBasis)) − formula tax \(formatSEK(calibration.formulaTaxAtBasis)) = \(formatSignedSEK(-calibration.impliedTaxAdjustment)) implied adjustment."
}
private func deductionText(_ deduction: TaxDeduction) -> String {
    deduction.kind == .amount
        ? "\(formatSEK(deduction.value)) / month"
        : "\(deduction.value)% of payment"
}
private func taxBalanceSummary(_ balance: Int64) -> String {
    balance == 0
        ? "No expected balance"
        : "Expected balance: \(taxBalanceValue(balance)) · \(taxBalanceKind(balance))"
}
private func taxBalanceValue(_ balance: Int64) -> String {
    balance > 0 ? "−\(formatSEK(UInt32(balance)))"
        : balance < 0 ? "+\(formatSEK(UInt32(-balance)))"
        : formatSEK(0)
}
private func taxBalanceKind(_ balance: Int64) -> String {
    balance > 0 ? "Tax debt" : balance < 0 ? "Tax refund" : "Settled"
}
private func taxBalanceColor(_ balance: Int64) -> Color {
    balance > 0 ? .red : balance < 0 ? .taxGreen : .primary
}
private func monthName(_ month: UInt8) -> String {
    Calendar.current.monthSymbols[Int(min(max(month, 1), 12)) - 1]
}

extension Color {
    static let taxBackground = Color(light: (244, 247, 246), dark: (15, 21, 20))
    static let taxSurface = Color(light: (255, 255, 255), dark: (27, 35, 33))
    static let taxField = Color(light: (247, 249, 248), dark: (20, 27, 25))
    static let taxBorder = Color(light: (210, 218, 215), dark: (57, 69, 65))
    static let taxPrimary = Color(light: (30, 44, 41), dark: (235, 242, 240))
    static let taxBlue = Color(light: (0, 82, 147), dark: (74, 161, 225))
    static let taxGreen = Color(light: (24, 121, 78), dark: (68, 190, 127))
    static let taxAmber = Color(light: (128, 91, 0), dark: (238, 190, 76))

    init(light: (Int, Int, Int), dark: (Int, Int, Int)) {
        self.init(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(components.0) / 255,
                green: CGFloat(components.1) / 255,
                blue: CGFloat(components.2) / 255,
                alpha: 1
            )
        })
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View { ContentView() }
}
