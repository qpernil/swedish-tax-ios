import Foundation

struct IncomeBasisProgress: Equatable, Sendable {
    let estimatedBasis: UInt32
    let maximumBasis: UInt32

    var percentOfMaximum: Double {
        Double(estimatedBasis) * 100 / Double(maximumBasis)
    }
}

enum IncomeBasisEstimate: Equatable, Sendable {
    case estimated(IncomeBasisProgress)
    case notBasedOnSelectedIncome
    case requiresAdditionalInformation
}

/// Estimates how the selected annual income uses the 2026 PGI and SGI ceilings.
enum IncomeBasisCalculator {
    /// Lowest 2026 annual income that can produce pensionable income (PGI).
    static let minimumPensionableIncome: UInt32 = 25_042

    /// Highest pensionable income (PGI) for income year 2026.
    static let maximumPensionableIncome: UInt32 = 625_500

    /// Income ceiling used when calculating the 2026 general pension fee.
    static let generalPensionFeeIncomeCeiling: UInt32 = 673_038

    /// Lowest 2026 annual work income that can produce an SGI.
    static let minimumSGIIncome: UInt32 = 14_200

    /// Highest sickness-benefit qualifying income (SGI) for 2026.
    static let maximumSGI: UInt32 = 592_000

    /// Estimates pensionable income after the general pension fee.
    static func publicPensionProgress(
        column: TaxColumn,
        grossYearlyIncome: UInt32
    ) -> IncomeBasisEstimate {
        switch column {
        case .column1, .column3, .column5:
            break
        case .column2, .column6:
            return .notBasedOnSelectedIncome
        case .column4:
            return .requiresAdditionalInformation
        }

        return publicPensionProgressForIncome(grossYearlyIncome)
    }

    /// Estimates PGI from aggregate pensionable work income.
    static func publicPensionProgressForIncome(
        _ grossYearlyIncome: UInt32
    ) -> IncomeBasisEstimate {
        let assessedIncome = TaxCalculator.roundDownHundred(grossYearlyIncome)
        let pensionableIncome: UInt32
        if assessedIncome < minimumPensionableIncome {
            pensionableIncome = 0
        } else {
            pensionableIncome = min(
                TaxCalculator.saturatingSubtract(
                    assessedIncome,
                    TaxCalculator.pensionFee(assessedIncome)
                ),
                maximumPensionableIncome
            )
        }

        return .estimated(
            IncomeBasisProgress(
                estimatedBasis: pensionableIncome,
                maximumBasis: maximumPensionableIncome
            )
        )
    }

    /// Estimates SGI for recurring salary. Försäkringskassan determines actual SGI.
    static func estimatedSGIProgress(
        column: TaxColumn,
        grossYearlyIncome: UInt32
    ) -> IncomeBasisEstimate {
        guard column == .column1 || column == .column3 else {
            return .notBasedOnSelectedIncome
        }

        return estimatedSGIProgressForIncome(grossYearlyIncome)
    }

    /// Estimates SGI from an annualized recurring-work-income rate.
    static func estimatedSGIProgressForIncome(
        _ grossYearlyIncome: UInt32
    ) -> IncomeBasisEstimate {
        let estimatedSGI = grossYearlyIncome < minimumSGIIncome
            ? 0
            : min(grossYearlyIncome, maximumSGI)
        return .estimated(
            IncomeBasisProgress(
                estimatedBasis: estimatedSGI,
                maximumBasis: maximumSGI
            )
        )
    }
}
