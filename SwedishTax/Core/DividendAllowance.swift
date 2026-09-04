let dividendAcquisitionCostThreshold: UInt32 = 100_000

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
    let taxAtTwentyPercent: UInt32
    let netAfterTwentyPercentTax: UInt32
}
