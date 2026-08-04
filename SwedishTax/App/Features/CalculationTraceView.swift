import SwiftUI

struct CalculationTraceView: View {
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
                        Text("\(formatSEK(calculation.workIncome)) work income + \(formatSEK(calculation.pensionIncome)) pension income")
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
