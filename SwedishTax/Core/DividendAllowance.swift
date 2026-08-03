let dividendBasicAmount2027: UInt32 = 333_600
let dividendWageDeduction2027: UInt32 = 667_200
let dividendWageAllowancePercent: UInt32 = 50
let dividendWageCapMultiplier: UInt32 = 50
let dividendAcquisitionCostThreshold: UInt32 = 100_000
let qualifiedDividendTaxPercent: UInt32 = 20

struct DividendAllowanceInputs2027: Codable, Equatable, Sendable {
    var onePersonCompany = true
    var ownershipBasisPoints: UInt32 = 10_000
    var otherQualifiedOwnershipBasisPoints: UInt32 = 0
    var spouseOwnershipBasisPoints: UInt32 = 0
    var companyCashPayroll2026: UInt32 = 0
    var highestRelatedCashSalary2026: UInt32 = 0
    var acquisitionCost: UInt32 = 0
    var acquisitionCostInterestBasisPoints: UInt32?
    var savedAllowance: UInt32 = 0

    func calculate(ownerCashSalary2026: UInt32) throws -> DividendAllowance2027 {
        guard ownershipBasisPoints <= 10_000 else {
            throw DividendAllowanceIssue.ownershipExceedsOneHundredPercent
        }
        let jointOwnership = ownershipBasisPoints.saturatingAdd(spouseOwnershipBasisPoints)
        guard jointOwnership <= 10_000 else {
            throw DividendAllowanceIssue.spouseOwnershipExceedsCompany
        }
        let companyCashPayroll = onePersonCompany
            ? ownerCashSalary2026
            : companyCashPayroll2026
        let highestRelatedCashSalary = onePersonCompany ? 0 : highestRelatedCashSalary2026
        guard ownerCashSalary2026 <= companyCashPayroll,
              highestRelatedCashSalary <= companyCashPayroll
        else {
            throw DividendAllowanceIssue.personalSalaryExceedsCompanyPayroll
        }

        let basicDenominator = max(
            ownershipBasisPoints.saturatingAdd(otherQualifiedOwnershipBasisPoints),
            10_000
        )
        let basicAmount = proportionFloor(
            dividendBasicAmount2027,
            ownershipBasisPoints,
            basicDenominator
        )
        let jointWageBasis = proportionFloor(companyCashPayroll, jointOwnership, 10_000)
        let jointWageBasisAfterDeduction = jointWageBasis
            .saturatingSubtract(dividendWageDeduction2027)
        let jointWageAllowance = percentageFloor(
            jointWageBasisAfterDeduction,
            dividendWageAllowancePercent
        )
        let wageAllowanceBeforeCap = jointOwnership == 0
            ? 0
            : proportionFloor(jointWageAllowance, ownershipBasisPoints, jointOwnership)
        let wageCapSalary = max(ownerCashSalary2026, highestRelatedCashSalary)
        let wageCap = wageCapSalary.saturatingMultiply(dividendWageCapMultiplier)
        let wageAllowance = min(wageAllowanceBeforeCap, wageCap)

        let acquisitionCostInterestBasis = acquisitionCost
            .saturatingSubtract(dividendAcquisitionCostThreshold)
        let acquisitionCostInterest: UInt32
        if acquisitionCostInterestBasis == 0 {
            acquisitionCostInterest = 0
        } else if let acquisitionCostInterestBasisPoints {
            acquisitionCostInterest = basisPointsFloor(
                acquisitionCostInterestBasis,
                acquisitionCostInterestBasisPoints
            )
        } else {
            throw DividendAllowanceIssue.missingAcquisitionCostInterestRate
        }
        let total = basicAmount
            .saturatingAdd(wageAllowance)
            .saturatingAdd(acquisitionCostInterest)
            .saturatingAdd(savedAllowance)
        return DividendAllowance2027(
            basicAmount: basicAmount,
            ownerCashSalary: ownerCashSalary2026,
            companyCashPayroll: companyCashPayroll,
            jointWageBasis: jointWageBasis,
            jointWageBasisAfterDeduction: jointWageBasisAfterDeduction,
            wageAllowanceBeforeCap: wageAllowanceBeforeCap,
            wageCapSalary: wageCapSalary,
            wageCap: wageCap,
            wageAllowance: wageAllowance,
            acquisitionCostInterestBasis: acquisitionCostInterestBasis,
            acquisitionCostInterest: acquisitionCostInterest,
            savedAllowance: savedAllowance,
            total: total
        )
    }
}

enum DividendAllowanceIssue: Error, Equatable, Sendable {
    case ownershipExceedsOneHundredPercent
    case spouseOwnershipExceedsCompany
    case personalSalaryExceedsCompanyPayroll
    case missingAcquisitionCostInterestRate
}

struct DividendAllowance2027: Equatable, Sendable {
    let basicAmount: UInt32
    let ownerCashSalary: UInt32
    let companyCashPayroll: UInt32
    let jointWageBasis: UInt32
    let jointWageBasisAfterDeduction: UInt32
    let wageAllowanceBeforeCap: UInt32
    let wageCapSalary: UInt32
    let wageCap: UInt32
    let wageAllowance: UInt32
    let acquisitionCostInterestBasis: UInt32
    let acquisitionCostInterest: UInt32
    let savedAllowance: UInt32
    let total: UInt32

    var taxAtTwentyPercent: UInt32 {
        percentageFloor(total, qualifiedDividendTaxPercent)
    }

    var netAfterTwentyPercentTax: UInt32 {
        total.saturatingSubtract(taxAtTwentyPercent)
    }
}

private func proportionFloor(
    _ amount: UInt32,
    _ numerator: UInt32,
    _ denominator: UInt32
) -> UInt32 {
    guard denominator > 0 else { return 0 }
    return UInt32(min(
        UInt64(amount) * UInt64(numerator) / UInt64(denominator),
        UInt64(UInt32.max)
    ))
}

private func percentageFloor(_ amount: UInt32, _ percent: UInt32) -> UInt32 {
    proportionFloor(amount, percent, 100)
}

private func basisPointsFloor(_ amount: UInt32, _ basisPoints: UInt32) -> UInt32 {
    proportionFloor(amount, basisPoints, 10_000)
}
