enum TaxEngine {
    static let usesRustCore: Bool = {
        #if USE_RUST_CORE
        true
        #else
        false
        #endif
    }()

    static func planCalculation(
        table: UInt8,
        ageGroup: TaxAgeGroup,
        plan: IncomePlan
    ) throws -> PlanCalculation? {
        #if USE_RUST_CORE
        try RustTaxCore.planCalculation(table: table, ageGroup: ageGroup, plan: plan)
        #else
        try PlanCalculation(table: table, ageGroup: ageGroup, plan: plan)
        #endif
    }

    static var badgeText: String {
        #if USE_RUST_CORE
        RustTaxCore.engineBadgeText
        #else
        "Swift core active"
        #endif
    }
}
