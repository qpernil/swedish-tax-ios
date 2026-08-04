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
            let calculation = try RustTaxCore.planCalculation(
                table: table,
                ageGroup: ageGroup,
                plan: plan
            )
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
                ForEach(supportedTaxTables, id: \.self) {
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

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View { ContentView() }
}
