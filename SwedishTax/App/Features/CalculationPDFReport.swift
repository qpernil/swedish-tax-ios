import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct CalculationPDFReport {
    let document: CalculationDocument
    let calculation: PlanCalculation
    var generatedAt = Date()

    var suggestedFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleanName = document.name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleanName.isEmpty ? "Calculation" : cleanName) - Swedish Tax 2026.pdf"
    }

    @MainActor
    func pdfData() throws -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = .zero

        let renderer = CalculationPageRenderer(documentName: document.name)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 0))

        let pageCount = renderer.numberOfPages
        guard pageCount > 0 else { throw CalculationPDFReportError.emptyReport }

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: renderer.paperRect)
        return pdfRenderer.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                renderer.drawPage(at: page, in: renderer.paperRect)
            }
        }
    }

    @MainActor
    func writeToTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Swedish Tax PDF Reports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(suggestedFilename, isDirectory: false)
        try pdfData().write(to: url, options: .atomic)
        return url
    }

    var html: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; }
            body {
              color: #1e2c29;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
              font-size: 10.5px;
              line-height: 1.38;
              -webkit-print-color-adjust: exact;
            }
            .report { padding: 0 1px; }
            .hero {
              background: #1e2c29;
              border-radius: 14px;
              color: #ffffff;
              margin: 0 0 14px;
              padding: 20px 22px 18px;
            }
            .eyebrow {
              color: #94d5b4;
              font-size: 9px;
              font-weight: 700;
              letter-spacing: .08em;
              margin-bottom: 5px;
              text-transform: uppercase;
            }
            h1 { font-size: 25px; line-height: 1.08; margin: 0 0 5px; }
            .hero-subtitle { color: #d7e2df; font-size: 11px; }
            .hero-meta { color: #aebfba; font-size: 8.5px; margin-top: 12px; }
            .summary-grid, .two-column {
              display: -webkit-box;
              display: flex;
              gap: 9px;
              margin-bottom: 11px;
            }
            .summary-card, .column { -webkit-box-flex: 1; flex: 1; }
            .summary-card {
              border: 1px solid #d2dad7;
              border-radius: 12px;
              padding: 11px 12px;
            }
            .summary-card.blue { border-top: 4px solid #005293; }
            .summary-card.green { border-top: 4px solid #18794e; }
            .summary-card.primary { border-top: 4px solid #1e2c29; }
            .summary-label { color: #62716d; font-size: 8.5px; font-weight: 700; }
            .summary-value { font-size: 16px; font-weight: 800; margin: 3px 0 2px; }
            .summary-card.blue .summary-value { color: #005293; }
            .summary-card.green .summary-value { color: #18794e; }
            .summary-detail { color: #62716d; font-size: 8px; }
            .section {
              border: 1px solid #d2dad7;
              border-radius: 12px;
              break-inside: avoid;
              margin: 0 0 11px;
              overflow: hidden;
            }
            .section.allow-break { break-inside: auto; }
            .section-title {
              background: #f4f7f6;
              border-bottom: 1px solid #d2dad7;
              font-size: 12px;
              font-weight: 800;
              padding: 9px 12px;
            }
            .standalone-title {
              background: #f4f7f6;
              border: 1px solid #d2dad7;
              border-radius: 12px;
              break-inside: avoid;
              font-size: 12px;
              font-weight: 800;
              margin: 0 0 9px;
              padding: 9px 12px;
            }
            .section-subtitle { color: #62716d; font-size: 8.5px; font-weight: 500; margin-left: 5px; }
            .section-body { padding: 7px 12px 9px; }
            .row {
              border-bottom: 1px solid #edf0ef;
              display: -webkit-box;
              display: flex;
              gap: 12px;
              padding: 6px 0;
            }
            .row:last-child { border-bottom: 0; }
            .row .label { color: #62716d; -webkit-box-flex: 1; flex: 1; }
            .row .value { font-weight: 650; max-width: 58%; text-align: right; }
            .row.total { border-top: 1.5px solid #9eaaa6; font-size: 11px; font-weight: 800; margin-top: 1px; }
            .row.total .label { color: #1e2c29; }
            .value.blue { color: #005293; }
            .value.green { color: #18794e; }
            .value.red { color: #b42318; }
            .note { color: #62716d; font-size: 8.5px; margin: 6px 0 2px; }
            .tag {
              background: #e6f0f7;
              border-radius: 99px;
              color: #005293;
              display: inline-block;
              font-size: 7.5px;
              font-weight: 700;
              margin: 0 4px 3px 0;
              padding: 3px 7px;
            }
            .tag.green { background: #e8f4ee; color: #18794e; }
            .tag.amber { background: #f6eedb; color: #805b00; }
            .income-card, .trace-step {
              border: 1px solid #d2dad7;
              border-radius: 10px;
              break-inside: avoid;
              margin: 0 0 9px;
              padding: 10px 12px;
            }
            .trace-step { margin-bottom: 6px; padding: 8px 12px; }
            .trace-step .row { padding: 5px 0; }
            .income-heading, .trace-heading {
              display: -webkit-box;
              display: flex;
              gap: 10px;
              margin-bottom: 6px;
            }
            .income-heading .name, .trace-heading .name { font-size: 11.5px; font-weight: 800; }
            .income-heading .amount { color: #005293; font-size: 11.5px; font-weight: 800; margin-left: auto; text-align: right; }
            .income-kind { color: #62716d; font-size: 8.5px; }
            .step-number {
              background: #1e2c29;
              border-radius: 50%;
              color: white;
              font-size: 8px;
              font-weight: 800;
              height: 19px;
              line-height: 19px;
              text-align: center;
              width: 19px;
            }
            .progress-track { background: #e5ebe8; border-radius: 5px; height: 6px; margin: 5px 0; overflow: hidden; }
            .progress-fill { background: #005293; height: 6px; }
            .progress-fill.green { background: #18794e; }
            .page-break { page-break-before: always; }
            .report-footer {
              border-top: 1px solid #d2dad7;
              color: #62716d;
              font-size: 8px;
              margin-top: 12px;
              padding-top: 10px;
            }
            .source-item {
              border-bottom: 1px solid #e5ebe8;
              padding: 10px 0;
            }
            .source-item:last-child { border-bottom: 0; }
            .source-name { font-size: 10px; font-weight: 800; margin-bottom: 3px; }
            .source-url {
              color: #005293;
              font-size: 8px;
              line-height: 1.45;
              overflow-wrap: anywhere;
              word-break: break-all;
              word-wrap: break-word;
            }
          </style>
        </head>
        <body>
          <div class="report">
            \(heroHTML)
            \(summaryHTML)
            <div class="two-column">
              <div class="column">\(taxSettingsHTML)</div>
              <div class="column">\(reconciliationHTML)</div>
            </div>
            \(incomePlanHTML)
            \(adjustmentHTML)
            <div class="two-column">
              <div class="column">\(monthlyReferenceHTML)</div>
              <div class="column">\(incomeBasesHTML)</div>
            </div>
            \(annualFormulaHTML)
            \(dividendAllowanceHTML)
            <div class="page-break"></div>
            \(calculationTraceHTML)
            <div class="report-footer">
              Preliminary planning estimate based on Skatteverket tables and SKV 433, edition 36.
              This is not an individualized final tax assessment or financial advice.
              All calculations are performed locally by Swedish Tax 2026.
            </div>
            \(officialSourcesHTML)
          </div>
        </body>
        </html>
        """
    }
}

private extension CalculationPDFReport {
    struct ReportRow {
        let label: String
        let value: String
        var isTotal = false
        var tone: String?
    }

    var officialSourcesHTML: String {
        let sources = [
            (
                "SKV 433 technical specification, edition 36 (2026)",
                "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf"
            ),
            (
                "Skatteverket official monthly tax tables for 2026",
                "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt"
            ),
            (
                "Skatteverket worked examples for SKV 433 (2026)",
                "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55f/1765284831853/bilaga-3-exempel-till-skv-433-2026.pdf"
            ),
            (
                "Skatteverket closely held company dividend rules (2026 reform)",
                "https://www.skatteverket.se/foretag/drivaforetag/foretagsformer/famansforetag/andradereglerinforinkomstdeklarationen2027.4.4a54dc8b19aa6175a152359.html"
            ),
            (
                "Skatteverket 2026 amounts and percentages (income base amount)",
                "https://www.skatteverket.se/foretag/skatterochavdrag/beloppochprocent/2026.106.1522bf3f19aea8075ba3294.html"
            ),
            (
                "Skatteverket pensionable income (PGI)",
                "https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html"
            ),
            (
                "Försäkringskassan sickness-benefit qualifying income (SGI)",
                "https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi"
            ),
        ]
        let items = sources.map { name, url in
            """
            <div class="source-item">
              <div class="source-name">\(escaped(name))</div>
              <div class="source-url">(\(escaped(url)))</div>
            </div>
            """
        }.joined()

        return """
        <div class="page-break"></div>
        <div class="standalone-title">
          Official sources <span class="section-subtitle">URLs printed in full</span>
        </div>
        <div class="section">
          <div class="section-body">
            <p class="note">
              Official sources used for the tax calculation, preliminary 2027 dividend allowance,
              and income-basis references.
            </p>
            \(items)
          </div>
        </div>
        """
    }

    var heroHTML: String {
        """
        <div class="hero">
          <div class="eyebrow">Swedish Tax 2026</div>
          <h1>\(escaped(document.name))</h1>
          <div class="hero-subtitle">Income plan and tax reconciliation</div>
          <div class="hero-meta">
            Generated \(escaped(reportDate(generatedAt))) &nbsp;|&nbsp;
            Tax table \(document.table) &nbsp;|&nbsp;
            \(escaped(document.ageGroup.rawValue))
          </div>
        </div>
        """
    }

    var summaryHTML: String {
        let balanceTone = calculation.taxBalance > 0 ? "red" : calculation.taxBalance < 0 ? "green" : ""
        return """
        <div class="summary-grid">
          \(summaryCard(
              title: calculation.adjustmentCalibration == nil
                  ? "Final tax estimate"
                  : "Jämkning-calibrated projection",
              value: currency(calculation.totalTax),
              detail: "Marginal tax \(decimal(calculation.marginalRate))%",
              style: "green"
          ))
          \(summaryCard(
              title: "Calculated withholding",
              value: currency(calculation.withheldTax),
              detail: "Cash after withholding \(currency(calculation.cashAfterWithholding))",
              style: "blue"
          ))
          \(summaryCard(
              title: "Annual net after final tax",
              value: currency(calculation.annualNet),
              detail: "Expected \(balanceLabel.lowercased()) \(balanceValue)",
              style: "primary \(balanceTone)"
          ))
        </div>
        """
    }

    var taxSettingsHTML: String {
        section(
            "Tax settings",
            subtitle: "Expanded",
            rows: [
                ReportRow(label: "Tax table", value: "Table \(document.table)"),
                ReportRow(label: "Age at start of 2026", value: document.ageGroup.rawValue),
                ReportRow(
                    label: "Salary / pension columns",
                    value: "\(document.ageGroup.salaryColumn.rawValue) / \(document.ageGroup.pensionColumn.rawValue)"
                ),
                ReportRow(label: "Created", value: reportDate(document.createdAt)),
                ReportRow(label: "Last modified", value: reportDate(document.modifiedAt)),
            ]
        )
    }

    var reconciliationHTML: String {
        var rows = [
            ReportRow(label: "Taxable salary and pension", value: currency(calculation.ordinaryIncome)),
            ReportRow(label: "Own-AB dividend", value: currency(calculation.dividendIncome)),
            ReportRow(
                label: "Modeled employer pension contributions",
                value: currency(calculation.employerPensionContributions)
            ),
            ReportRow(label: "Final tax estimate", value: currency(calculation.totalTax)),
            ReportRow(label: "Preliminary tax withheld", value: credit(calculation.withheldTax)),
            ReportRow(
                label: "Expected balance",
                value: "\(balanceValue) - \(balanceLabel)",
                isTotal: true,
                tone: calculation.taxBalance > 0 ? "red" : calculation.taxBalance < 0 ? "green" : nil
            ),
        ]
        if calculation.salaryExchangeSacrifice > 0 {
            rows.insert(
                ReportRow(label: "Salary exchanged", value: credit(calculation.salaryExchangeSacrifice)),
                at: 2
            )
        }
        return section("Annual reconciliation", subtitle: "Expanded", rows: rows)
    }

    var incomePlanHTML: String {
        let entryCards = document.plan.entries.map(incomeCard).joined()
        let totals = document.plan.totals
        let totalsRows = valueTable([
            ReportRow(label: "Salary", value: currency(totals.workIncome)),
            ReportRow(label: "Pension", value: currency(totals.pensionIncome)),
            ReportRow(label: "Dividend", value: currency(totals.dividendIncome)),
            ReportRow(label: "Total cash income", value: currency(totals.grossIncome), isTotal: true),
        ])
        return """
        <div class="page-break"></div>
        <div class="standalone-title">Income plan <span class="section-subtitle">All entries and options expanded</span></div>
        \(entryCards)
        <div class="section">
          <div class="section-title">Income totals</div>
          <div class="section-body">\(totalsRows)</div>
        </div>
        """
    }

    func incomeCard(_ entry: IncomeEntry) -> String {
        let withholding = calculation.withholding.entries.first { $0.entryID == entry.id }
        let name = entry.description.isEmpty ? entry.kind.shortTitle : entry.description
        var rows = [
            ReportRow(
                label: entry.kind.isMonthly ? "Amount per month" : "Annual / one-time amount",
                value: currency(entry.amount)
            ),
        ]
        if entry.kind.isMonthly {
            rows.append(ReportRow(label: "Payment period", value: "\(date2026(entry.start)) to \(date2026(entry.end))"))
        }
        rows.append(ReportRow(label: "Annual cash amount", value: currency(entry.totalAnnualAmount), isTotal: true))

        if !entry.kind.isDividend {
            rows.append(ReportRow(label: "Payer", value: entry.payerRole.rawValue))
            rows.append(ReportRow(
                label: "Jämkning decision",
                value: adjustmentStatus(for: entry, withholding: withholding)
            ))
            rows.append(ReportRow(
                label: "Additional withholding per payment",
                value: entry.additionalWithholdingPerPayment.map(currency) ?? "None"
            ))
            rows.append(ReportRow(
                label: "Actual / custom annual withholding",
                value: entry.actualWithholding.map(currency) ?? "Not entered"
            ))
        }
        if entry.kind.isSalary {
            rows.append(ReportRow(
                label: "Paid by own company / qualifying group",
                value: yesNo(entry.ownCompanySourced)
            ))
            rows.append(ReportRow(
                label: "Included in pension salary basis",
                value: yesNo(entry.includedInPensionSalaryBasis)
            ))
        }
        if let vacation = entry.vacationCompensation {
            rows.append(contentsOf: [
                ReportRow(label: "Vacation entitlement", value: "\(vacation.annualEntitlementDays) days"),
                ReportRow(label: "Vacation payout", value: "\(vacation.payoutDays) days"),
                ReportRow(label: "Vacation compensation", value: currency(entry.vacationCompensationAmount)),
                ReportRow(
                    label: "Vacation pay pension premium",
                    value: currency(entry.vacationPensionPremiumAmount)
                ),
            ])
        }
        if let regularPension = entry.regularPensionPremium {
            rows.append(contentsOf: [
                ReportRow(
                    label: "Regular pension premium setting",
                    value: regularPension.monthlyOverride.map { "Actual \(currency($0)) / month" }
                        ?? "Calculated benchmark"
                ),
                ReportRow(label: "Regular pension premium", value: currency(entry.regularPensionPremiumAmount)),
            ])
        }
        if let exchange = entry.salaryExchange {
            rows.append(contentsOf: [
                ReportRow(label: "Salary exchanged", value: currency(entry.salaryExchangeSacrifice)),
                ReportRow(label: "Employer uplift", value: yesNo(exchange.employerAddsUplift)),
                ReportRow(
                    label: "Uplift percentage",
                    value: "\(basisPoints(exchange.upliftBasisPoints))%"
                ),
                ReportRow(
                    label: "Exchange pension contribution",
                    value: currency(entry.salaryExchangePensionContribution)
                ),
            ])
        }
        if let withholding {
            rows.append(contentsOf: [
                ReportRow(label: "Withholding rule", value: withholding.rule.description, tone: "blue"),
                ReportRow(label: "Regular withholding", value: currency(withholding.regularWithheld)),
                ReportRow(label: "Supplemental withholding", value: currency(withholding.supplementalWithheld)),
                ReportRow(label: "Additional withholding", value: currency(withholding.additionalWithheld)),
                ReportRow(label: "Total withheld", value: currency(withholding.withheld), isTotal: true, tone: "blue"),
            ])
        }

        let tags = [
            "<span class=\"tag\">\(escaped(entry.kind.eligibility))</span>",
            entry.kind.isSalary ? "<span class=\"tag green\">Salary</span>" : "",
            entry.kind.isPension ? "<span class=\"tag green\">Pension</span>" : "",
            entry.kind.isDividend ? "<span class=\"tag amber\">Dividend</span>" : "",
        ].joined()
        let pageHeading = entry.kind.isDividend
            ? "<div class=\"page-break\"></div><div class=\"standalone-title\">Dividend income</div>"
            : ""
        return """
        \(pageHeading)
        <div class="income-card">
          <div class="income-heading">
            <div><div class="name">\(escaped(name))</div><div class="income-kind">\(escaped(entry.kind.shortTitle))</div></div>
            <div class="amount">\(escaped(currency(entry.totalAnnualAmount)))<div class="income-kind">annual cash</div></div>
          </div>
          <div>\(tags)</div>
          \(valueTable(rows))
        </div>
        """
    }

    var adjustmentHTML: String {
        guard let percent = document.plan.adjustmentPercent else {
            return section(
                "Jämkning",
                subtitle: "Expanded",
                rows: [ReportRow(label: "Percentage decision", value: "Not enabled")]
            )
        }

        let selected = document.plan.entries.filter { $0.adjustmentApplies && !$0.kind.isDividend }
        let applied = calculation.withholding.entries.filter {
            if case .adjustmentPercent = $0.rule { return true }
            return false
        }
        var rows = [
            ReportRow(label: "Decision withholding", value: "\(percent)%"),
            ReportRow(label: "Selected payers", value: "\(selected.count)"),
            ReportRow(label: "Payers where applied", value: "\(applied.count)"),
        ]
        if let calibration = calculation.adjustmentCalibration {
            rows.append(contentsOf: [
                ReportRow(label: "Full-year basis", value: currency(calibration.basisIncome)),
                ReportRow(label: "Formula tax at basis", value: currency(calibration.formulaTaxAtBasis)),
                ReportRow(label: "Assumed tax at \(calibration.percent)%", value: currency(calibration.assumedTaxAtBasis)),
                ReportRow(label: "Implied adjustment", value: signed(-calibration.impliedTaxAdjustment)),
                ReportRow(
                    label: "Projected salary and pension tax",
                    value: currency(calibration.projectedOrdinaryTax),
                    isTotal: true
                ),
            ])
        }
        return section(
            "Jämkning",
            subtitle: calculation.adjustmentCalibration == nil ? "Expanded" : "Full-year calibration expanded",
            rows: rows,
            note: calculation.adjustmentCalibration.map { calibration in
                "Assumed tax \(currency(calibration.assumedTaxAtBasis)) - formula tax "
                    + "\(currency(calibration.formulaTaxAtBasis)) = \(signed(-calibration.impliedTaxAdjustment)) implied adjustment."
            }
        )
    }

    var monthlyReferenceHTML: String {
        section(
            "Monthly table reference",
            subtitle: "Expanded",
            rows: [
                ReportRow(label: "Average monthly income", value: currency(calculation.monthlyIncome)),
                ReportRow(label: "Table deduction", value: deduction(calculation.tableDeduction)),
                ReportRow(label: "Monthly cash after table tax", value: currency(calculation.tableReferenceNet)),
                ReportRow(
                    label: "Annualized table deduction",
                    value: currency(calculation.annualizedTableReferenceTax)
                ),
            ],
            note: "Reference only. Actual payer withholding is calculated entry by entry."
        )
    }

    var incomeBasesHTML: String {
        """
        <div class="section">
          <div class="section-title">Income-basis ceilings <span class="section-subtitle">Expanded</span></div>
          <div class="section-body">
            \(basisProgress("Allmän pension (PGI)", estimate: calculation.pensionProgress, style: ""))
            \(basisProgress("Estimated SGI", estimate: calculation.sgiProgress, style: "green"))
          </div>
        </div>
        """
    }

    var annualFormulaHTML: String {
        let tax = calculation.annualTax
        var rows = [
            ReportRow(label: "Assessed income", value: currency(tax.assessedIncome)),
            ReportRow(label: "Basic allowance", value: credit(tax.basicAllowance)),
            ReportRow(label: "Taxable income", value: currency(tax.taxableIncome)),
            ReportRow(label: "State income tax", value: currency(tax.stateIncomeTax)),
            ReportRow(label: "Municipal income tax", value: currency(tax.municipalIncomeTax)),
            ReportRow(label: "Burial and religious fee", value: currency(tax.burialAndReligiousFee)),
            ReportRow(label: "Pension fee", value: currency(tax.pensionFee)),
            ReportRow(label: "Pension fee credit", value: credit(tax.pensionFeeCredit)),
            ReportRow(label: "Work income credit", value: credit(tax.workIncomeCredit)),
            ReportRow(label: "Sickness compensation credit", value: credit(tax.sicknessCompensationCredit)),
            ReportRow(label: "Earned income credit", value: credit(tax.earnedIncomeCredit)),
            ReportRow(label: "Public service fee", value: currency(tax.publicServiceFee)),
            ReportRow(label: "Formula tax", value: currency(tax.total), isTotal: true),
        ]
        if calculation.dividendIncome > 0 {
            rows.append(contentsOf: [
                ReportRow(label: "Own-AB dividend", value: currency(calculation.dividendIncome)),
                ReportRow(label: "Dividend tax at 20%", value: currency(calculation.dividendTax)),
                ReportRow(label: "Total final tax", value: currency(calculation.totalTax), isTotal: true),
            ])
        }
        return section(
            calculation.adjustmentCalibration == nil
                ? "Annual formula breakdown"
                : "Annual tax projection breakdown",
            subtitle: "Expanded",
            rows: rows
        )
    }

    var dividendAllowanceHTML: String {
        let inputs = document.plan.dividendAllowance
        var rows = [
            ReportRow(label: "One-person company", value: yesNo(inputs.onePersonCompany)),
            ReportRow(label: "Your ownership", value: "\(basisPoints(inputs.ownershipBasisPoints))%"),
            ReportRow(label: "Spouse ownership", value: "\(basisPoints(inputs.spouseOwnershipBasisPoints))%"),
            ReportRow(
                label: "Ownership in other qualified companies",
                value: "\(basisPoints(inputs.otherQualifiedOwnershipBasisPoints))%"
            ),
        ]
        if !inputs.onePersonCompany {
            rows.append(contentsOf: [
                ReportRow(label: "Company / group payroll in 2026", value: currency(inputs.companyCashPayroll2026)),
                ReportRow(
                    label: "Highest related person's salary",
                    value: currency(inputs.highestRelatedCashSalary2026)
                ),
            ])
        }
        rows.append(contentsOf: [
            ReportRow(label: "Acquisition cost", value: currency(inputs.acquisitionCost)),
            ReportRow(
                label: "Acquisition-cost interest rate",
                value: inputs.acquisitionCostInterestBasisPoints.map { "\(basisPoints($0))%" } ?? "Not entered"
            ),
            ReportRow(label: "Saved allowance", value: currency(inputs.savedAllowance)),
        ])

        do {
            let allowance = try document.plan.dividendAllowance2027()
            rows.append(contentsOf: [
                ReportRow(label: "Marked 2026 own-company salary", value: currency(allowance.ownerCashSalary)),
                ReportRow(label: "Basic amount", value: currency(allowance.basicAmount)),
                ReportRow(label: "Wage-based allowance", value: currency(allowance.wageAllowance)),
                ReportRow(label: "Maximum dividend at 20%", value: currency(allowance.total), isTotal: true, tone: "green"),
                ReportRow(label: "Personal tax if fully used", value: currency(allowance.taxAtTwentyPercent)),
                ReportRow(label: "Net after 20% tax", value: currency(allowance.netAfterTwentyPercentTax), isTotal: true),
            ])
            return dividendAllowanceCard(
                rows: rows,
                note: "The actual dividend also requires sufficient free equity, a prudence assessment, and a shareholder decision."
            )
        } catch let issue as DividendAllowanceIssue {
            rows.append(ReportRow(label: "Calculation status", value: dividendIssue(issue), isTotal: true, tone: "red"))
            return dividendAllowanceCard(rows: rows)
        } catch {
            rows.append(ReportRow(label: "Calculation status", value: "Unable to calculate", isTotal: true, tone: "red"))
            return dividendAllowanceCard(rows: rows)
        }
    }

    var calculationTraceHTML: String {
        let cashRows = document.plan.entries.map { entry in
            ReportRow(
                label: entry.description.isEmpty ? entry.kind.shortTitle : entry.description,
                value: currency(entry.totalAnnualAmount)
            )
        } + [ReportRow(label: "Total cash income", value: currency(calculation.annualIncome), isTotal: true)]

        let withholdingRows = calculation.withholding.entries.compactMap { withholding -> ReportRow? in
            guard let entry = document.plan.entries.first(where: { $0.id == withholding.entryID }) else { return nil }
            let name = entry.description.isEmpty ? entry.kind.shortTitle : entry.description
            return ReportRow(
                label: "\(name) - \(withholding.rule.description)",
                value: currency(withholding.withheld)
            )
        } + [ReportRow(label: "Total withheld", value: currency(calculation.withheldTax), isTotal: true)]

        var projectionRows = [
            ReportRow(label: "Salary and pension formula tax", value: currency(calculation.annualTax.total)),
        ]
        if let calibration = calculation.adjustmentCalibration {
            projectionRows.append(contentsOf: [
                ReportRow(label: "Full-year calibration basis", value: currency(calibration.basisIncome)),
                ReportRow(label: "Implied adjustment", value: signed(-calibration.impliedTaxAdjustment)),
                ReportRow(label: "Projected salary and pension tax", value: currency(calculation.ordinaryFinalTax)),
            ])
        }
        projectionRows.append(contentsOf: [
            ReportRow(label: "Dividend tax", value: currency(calculation.dividendTax)),
            ReportRow(label: "Total final tax", value: currency(calculation.totalTax), isTotal: true),
        ])

        return """
        <div class="standalone-title">Calculation trace <span class="section-subtitle">All five steps expanded</span></div>
        \(traceStep(1, "Cash income", rows: cashRows))
        \(traceStep(2, "Payer withholding", rows: withholdingRows))
        \(traceStep(3, "Annual formula", rows: [
                ReportRow(label: "Work income", value: currency(calculation.workIncome)),
                ReportRow(label: "Pension income", value: currency(calculation.pensionIncome)),
                ReportRow(label: "Formula tax", value: currency(calculation.annualTax.total), isTotal: true),
        ]))
        \(traceStep(4, "Final-tax projection", rows: projectionRows))
        \(traceStep(5, "Expected balance", rows: [
                ReportRow(label: "Total final tax", value: currency(calculation.totalTax)),
                ReportRow(label: "Preliminary withholding", value: credit(calculation.withheldTax)),
                ReportRow(
                    label: "Expected balance",
                    value: "\(balanceValue) - \(balanceLabel)",
                    isTotal: true,
                    tone: calculation.taxBalance > 0 ? "red" : calculation.taxBalance < 0 ? "green" : nil
                ),
        ]))
        """
    }

    func summaryCard(title: String, value: String, detail: String, style: String) -> String {
        """
        <div class="summary-card \(style)">
          <div class="summary-label">\(escaped(title))</div>
          <div class="summary-value">\(escaped(value))</div>
          <div class="summary-detail">\(escaped(detail))</div>
        </div>
        """
    }

    func section(
        _ title: String,
        subtitle: String? = nil,
        rows: [ReportRow],
        note: String? = nil
    ) -> String {
        let subtitleHTML = subtitle.map {
            "<span class=\"section-subtitle\">\(escaped($0))</span>"
        } ?? ""
        let noteHTML = note.map { "<div class=\"note\">\(escaped($0))</div>" } ?? ""
        return """
        <div class="section">
          <div class="section-title">\(escaped(title)) \(subtitleHTML)</div>
          <div class="section-body">\(valueTable(rows))\(noteHTML)</div>
        </div>
        """
    }

    func dividendAllowanceCard(rows: [ReportRow], note: String? = nil) -> String {
        let noteHTML = note.map { "<div class=\"note\">\(escaped($0))</div>" } ?? ""
        return """
        <div class="page-break"></div>
        <div class="standalone-title">
          Preliminary 2027 dividend allowance
          <span class="section-subtitle">Inputs and result expanded</span>
        </div>
        <div class="section">
          <div class="section-body">\(valueTable(rows))\(noteHTML)</div>
        </div>
        """
    }

    func valueTable(_ rows: [ReportRow]) -> String {
        rows.map { row in
            let totalClass = row.isTotal ? " total" : ""
            let toneClass = row.tone.map { " \($0)" } ?? ""
            return """
            <div class="row\(totalClass)">
              <div class="label">\(escaped(row.label))</div>
              <div class="value\(toneClass)">\(escaped(row.value))</div>
            </div>
            """
        }.joined()
    }

    func traceStep(_ number: Int, _ title: String, rows: [ReportRow]) -> String {
        """
        <div class="trace-step">
          <div class="trace-heading">
            <div class="step-number">\(number)</div>
            <div class="name">\(escaped(title))</div>
          </div>
          \(valueTable(rows))
        </div>
        """
    }

    func basisProgress(_ title: String, estimate: IncomeBasisEstimate, style: String) -> String {
        switch estimate {
        case let .estimated(progress):
            let percent = min(progress.percentOfMaximum, 100)
            return """
            <div style="margin-bottom: 10px">
              <div class="row"><div class="label">\(escaped(title))</div><div class="value \(style)">\(decimal(progress.percentOfMaximum))%</div></div>
              <div class="progress-track"><div class="progress-fill \(style)" style="width: \(percent)%"></div></div>
              <div class="note">\(escaped(currency(progress.estimatedBasis))) / \(escaped(currency(progress.maximumBasis))) of 2026 maximum</div>
            </div>
            """
        case .notBasedOnSelectedIncome:
            return valueTable([ReportRow(label: title, value: "Selected income does not establish this basis")])
        case .requiresAdditionalInformation:
            return valueTable([ReportRow(label: title, value: "Additional income information is required")])
        }
    }

    func adjustmentStatus(for entry: IncomeEntry, withholding: EntryWithholding?) -> String {
        guard let percent = document.plan.adjustmentPercent else { return "Not enabled" }
        guard entry.adjustmentApplies else { return "Not selected for this payer" }
        guard let withholding else { return "Selected at \(percent)%" }
        if case .adjustmentPercent = withholding.rule { return "Applied at \(percent)%" }
        return "Overridden by \(withholding.rule.description)"
    }

    var balanceValue: String { signed(-calculation.taxBalance) }
    var balanceLabel: String {
        calculation.taxBalance > 0 ? "Tax debt" : calculation.taxBalance < 0 ? "Tax refund" : "Settled"
    }

    func currency(_ value: UInt32) -> String { "\(groupedDigits(value)) SEK" }
    func credit(_ value: UInt32) -> String { value == 0 ? currency(0) : "-\(currency(value))" }
    func signed(_ value: Int64) -> String {
        if value > 0 { return "+\(currency(UInt32(value)))" }
        if value < 0 { return "-\(currency(UInt32(-value)))" }
        return currency(0)
    }
    func decimal(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_SE")).precision(.fractionLength(1)))
    }
    func basisPoints(_ value: UInt32) -> String { formatBasisPointsPercentage(value) }
    func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
    func deduction(_ value: TaxDeduction) -> String {
        value.kind == .amount ? "\(currency(value.value)) / month" : "\(value.value)% of payment"
    }

    func date2026(_ value: Date2026) -> String {
        let months = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        ]
        let clamped = value.clamped
        return "\(clamped.day) \(months[Int(clamped.month) - 1]) 2026"
    }

    func reportDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_SE")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }

    func dividendIssue(_ issue: DividendAllowanceIssue) -> String {
        switch issue {
        case .ownershipExceedsOneHundredPercent:
            "Your ownership in this company cannot exceed 100%."
        case .spouseOwnershipExceedsCompany:
            "Your and your spouse's combined ownership cannot exceed 100%."
        case .personalSalaryExceedsCompanyPayroll:
            "Owner or related-person salary cannot exceed company / group payroll."
        case .missingAcquisitionCostInterestRate:
            "The exact 2027 acquisition-cost interest rate is not known until 30 November 2026."
        }
    }

    func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }
}

enum CalculationPDFReportError: LocalizedError {
    case emptyReport

    var errorDescription: String? {
        switch self {
        case .emptyReport: "The PDF report did not contain any printable pages."
        }
    }
}

@MainActor
private final class CalculationPageRenderer: UIPrintPageRenderer {
    private static let a4 = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private let documentName: String

    init(documentName: String) {
        self.documentName = documentName
        super.init()
        setValue(NSValue(cgRect: Self.a4), forKey: "paperRect")
        setValue(
            NSValue(cgRect: Self.a4.insetBy(dx: 35, dy: 34)),
            forKey: "printableRect"
        )
        headerHeight = 24
        footerHeight = 22
    }

    override func drawHeaderForPage(at pageIndex: Int, in headerRect: CGRect) {
        guard pageIndex > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: UIColor(red: 98 / 255, green: 113 / 255, blue: 109 / 255, alpha: 1),
        ]
        pdfSafe(documentName).draw(
            in: headerRect.insetBy(dx: 1, dy: 5),
            withAttributes: attributes
        )
    }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let text = "Swedish Tax 2026  |  Page \(pageIndex + 1) of \(numberOfPages)" as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor(red: 98 / 255, green: 113 / 255, blue: 109 / 255, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        text.draw(in: footerRect.insetBy(dx: 1, dy: 5), withAttributes: attributes)
    }
}

private func pdfSafe(_ value: String) -> NSString {
    value
        .replacingOccurrences(of: "−", with: "-")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-") as NSString
}

struct ExportedPDFReport: Identifiable {
    let url: URL
    var id: URL { url }
}

struct PDFShareSheet: UIViewControllerRepresentable {
    let report: ExportedPDFReport

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [report.url], applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
