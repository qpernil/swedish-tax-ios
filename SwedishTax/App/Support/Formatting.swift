import SwiftUI

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

func sanitizePercentageText(_ input: String) -> String {
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

func groupedDigits(_ value: UInt32) -> String {
    let digits = String(value)
    var output = ""
    for (index, character) in digits.enumerated() {
        if index > 0, (digits.count - index).isMultiple(of: 3) { output.append(" ") }
        output.append(character)
    }
    return output
}

func formatSEK(_ value: UInt32) -> String { "\(groupedDigits(value)) SEK" }
func formatCredit(_ value: UInt32) -> String { value == 0 ? formatSEK(0) : "−\(formatSEK(value))" }
func formatSignedSEK(_ value: Int64) -> String {
    if value > 0 { return "+\(formatSEK(UInt32(value)))" }
    if value < 0 { return "−\(formatSEK(UInt32(-value)))" }
    return formatSEK(0)
}
func impliedAdjustmentExplanation(_ calibration: AdjustmentCalibration) -> String {
    "Assumed tax \(formatSEK(calibration.assumedTaxAtBasis)) − formula tax \(formatSEK(calibration.formulaTaxAtBasis)) = \(formatSignedSEK(-calibration.impliedTaxAdjustment)) implied adjustment."
}
func deductionText(_ deduction: TaxDeduction) -> String {
    deduction.kind == .amount
        ? "\(formatSEK(deduction.value)) / month"
        : "\(deduction.value)% of payment"
}
func taxBalanceSummary(_ balance: Int64) -> String {
    balance == 0
        ? "No expected balance"
        : "Expected balance: \(taxBalanceValue(balance)) · \(taxBalanceKind(balance))"
}
func taxBalanceValue(_ balance: Int64) -> String {
    balance > 0 ? "−\(formatSEK(UInt32(balance)))"
        : balance < 0 ? "+\(formatSEK(UInt32(-balance)))"
        : formatSEK(0)
}
func taxBalanceKind(_ balance: Int64) -> String {
    balance > 0 ? "Tax debt" : balance < 0 ? "Tax refund" : "Settled"
}
func taxBalanceColor(_ balance: Int64) -> Color {
    balance > 0 ? .red : balance < 0 ? .taxGreen : .primary
}
func monthName(_ month: UInt8) -> String {
    Calendar.current.monthSymbols[Int(min(max(month, 1), 12)) - 1]
}
