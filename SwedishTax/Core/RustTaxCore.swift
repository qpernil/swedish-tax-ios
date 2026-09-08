import SwedishTaxFFI

enum RustTaxCoreError: Error, Equatable {
    case invalidInput
    case internalError
    case unsupportedStatus(UInt32)
    case unsupportedDeductionKind(UInt32)
    case invalidResponse(String)
}

/// Thin Swift mapping over the current C API exported by the Rust tax core.
enum RustTaxCore {
    static func monthlyDeduction(
        table: UInt8,
        column: TaxColumn,
        grossMonthlyIncome: UInt32
    ) throws -> TaxDeduction {
        let result = swedish_tax_monthly_deduction(
            UInt32(table),
            UInt32(column.rawValue),
            grossMonthlyIncome
        )

        switch result.status {
        case 0:
            break
        case 1:
            throw RustTaxCoreError.invalidInput
        case 2:
            throw RustTaxCoreError.internalError
        default:
            throw RustTaxCoreError.unsupportedStatus(result.status)
        }

        switch result.kind {
        case 0:
            return .amount(result.value)
        case 1:
            return .percent(result.value)
        default:
            throw RustTaxCoreError.unsupportedDeductionKind(result.kind)
        }
    }

    static func annualTax(
        table: UInt8,
        column: TaxColumn,
        grossYearlyIncome: UInt32
    ) throws -> AnnualTax {
        try annualTax(
            from: swedish_tax_annual_tax(
                UInt32(table),
                UInt32(column.rawValue),
                grossYearlyIncome
            )
        )
    }

    static func annualTax(
        table: UInt8,
        ageGroup: TaxAgeGroup,
        profile: AnnualIncomeProfile
    ) throws -> AnnualTax {
        try annualTax(
            from: swedish_tax_annual_tax_for_income_profile(
                UInt32(table),
                ageGroup == .under66 ? 0 : 1,
                profile.workIncome,
                profile.pensionIncome
            )
        )
    }

    private static func annualTax(
        from result: SwedishTaxAnnualTaxResult
    ) throws -> AnnualTax {
        try checkStatus(result.status)
        return AnnualTax(
            assessedIncome: result.assessed_income,
            basicAllowance: result.basic_allowance,
            taxableIncome: result.taxable_income,
            stateIncomeTax: result.state_income_tax,
            municipalIncomeTax: result.municipal_income_tax,
            burialAndReligiousFee: result.burial_and_religious_fee,
            pensionFee: result.pension_fee,
            pensionFeeCredit: result.pension_fee_credit,
            workIncomeCredit: result.work_income_credit,
            sicknessCompensationCredit: result.sickness_compensation_credit,
            earnedIncomeCredit: result.earned_income_credit,
            publicServiceFee: result.public_service_fee,
            total: result.total
        )
    }

    private static func checkStatus(_ status: UInt32) throws {
        switch status {
        case 0:
            return
        case 1:
            throw RustTaxCoreError.invalidInput
        case 2:
            throw RustTaxCoreError.internalError
        default:
            throw RustTaxCoreError.unsupportedStatus(status)
        }
    }

    static func planCalculation(
        table: UInt8,
        ageGroup: TaxAgeGroup,
        plan: IncomePlan
    ) throws -> PlanCalculation {
        let entries = plan.entries.map(entryForRust)
        return try entries.withUnsafeBufferPointer { entries in
            var request = SwedishTaxPlanRequest()
            request.table = UInt32(table)
            request.age_group = ageGroup == .under66 ? 0 : 1
            request.entries = entries.baseAddress
            request.entries_count = entries.count
            request.adjustment_percent = optional(plan.adjustmentPercent)
            request.dividend_allowance = dividendAllowanceForRust(plan.dividendAllowance)

            let result = withUnsafePointer(to: &request) { request in
                swedish_tax_calculate_plan(request)
            }
            defer { swedish_tax_calculation_result_free(result) }
            try checkStatus(result.status)
            return try PlanCalculation(rust: result)
        }
    }

    static func dividendAllowance(
        table: UInt8,
        ageGroup: TaxAgeGroup,
        plan: IncomePlan
    ) throws -> DividendAllowance2027 {
        let entries = plan.entries.map(entryForRust)
        return try entries.withUnsafeBufferPointer { entries in
            var request = SwedishTaxPlanRequest()
            request.table = UInt32(table)
            request.age_group = ageGroup == .under66 ? 0 : 1
            request.entries = entries.baseAddress
            request.entries_count = entries.count
            request.adjustment_percent = optional(plan.adjustmentPercent)
            request.dividend_allowance = dividendAllowanceForRust(plan.dividendAllowance)

            let result = withUnsafePointer(to: &request) { request in
                swedish_tax_dividend_allowance_for_plan(request)
            }
            try checkStatus(result.status)
            switch result.issue_kind {
            case 0:
                return DividendAllowance2027(
                    basicAmount: result.basic_amount,
                    ownerCashSalary: result.owner_cash_salary,
                    companyCashPayroll: result.company_cash_payroll,
                    jointWageBasis: result.joint_wage_basis,
                    jointWageBasisAfterDeduction: result.joint_wage_basis_after_deduction,
                    wageAllowanceBeforeCap: result.wage_allowance_before_cap,
                    wageCapSalary: result.wage_cap_salary,
                    wageCap: result.wage_cap,
                    wageAllowance: result.wage_allowance,
                    acquisitionCostInterestBasis: result.acquisition_cost_interest_basis,
                    acquisitionCostInterest: result.acquisition_cost_interest,
                    savedAllowance: result.saved_allowance,
                    total: result.total,
                    taxAtTwentyPercent: result.tax_at_twenty_percent,
                    netAfterTwentyPercentTax: result.net_after_twenty_percent_tax
                )
            case 1:
                throw DividendAllowanceIssue.ownershipExceedsOneHundredPercent
            case 2:
                throw DividendAllowanceIssue.spouseOwnershipExceedsCompany
            case 3:
                throw DividendAllowanceIssue.personalSalaryExceedsCompanyPayroll
            case 4:
                throw DividendAllowanceIssue.missingAcquisitionCostInterestRate
            default:
                throw RustTaxCoreError.invalidResponse(
                    "Unknown dividend allowance issue \(result.issue_kind)"
                )
            }
        }
    }

    static let planningPolicy = swedish_tax_planning_policy()

    /// Typed editor inputs always decode. A nonzero status is an integration failure,
    /// never an invitation to substitute a second implementation of the rules.
    static func entrySupport(_ entry: IncomeEntry) -> SwedishTaxEntrySupport {
        var input = entryForRust(entry)
        let result = swedish_tax_entry_support(&input)
        precondition(result.status == 0, "Rust entry support failed: \(result.status)")
        return result
    }

    struct PlanSupport {
        let totals: IncomePlanTotals
        let issue: IncomePlanValidationIssue?
        let entries: [SwedishTaxEntrySupport]
    }

    static func planSupport(_ plan: IncomePlan) throws -> PlanSupport {
        let entries = plan.entries.map(entryForRust)
        return try entries.withUnsafeBufferPointer { entries in
            var request = SwedishTaxPlanRequest()
            request.table = 32 // Editor support is independent of the selected table.
            request.entries = entries.baseAddress
            request.entries_count = entries.count
            request.adjustment_percent = optional(plan.adjustmentPercent)
            request.dividend_allowance = dividendAllowanceForRust(plan.dividendAllowance)
            let result = swedish_tax_plan_support(&request)
            defer { swedish_tax_plan_support_free(result) }
            try checkStatus(result.status)
            guard result.entries_count == entries.count,
                  result.entries_count <= result.entries_capacity,
                  result.entries_count == 0 || result.entries != nil else {
                throw RustTaxCoreError.invalidResponse("Invalid planning buffer")
            }
            let issue: IncomePlanValidationIssue?
            switch result.issue_kind {
            case 0: issue = nil
            case 1: issue = .invalidPaymentPeriod(entryID: result.issue_entry_id)
            case 2: issue = .salaryExchangeExceedsAllowance(entryID: result.issue_entry_id, maximum: result.issue_maximum)
            default: throw RustTaxCoreError.invalidResponse("Unknown planning issue")
            }
            let t = result.totals
            return PlanSupport(totals: IncomePlanTotals(
                workIncome: t.work_income,
                pensionIncome: t.pension_income,
                dividendIncome: t.dividend_income,
                sgiAnnualRate: t.sgi_annual_rate,
                adjustmentBasisWorkIncome: t.adjustment_basis_work_income,
                pensionSalaryBasis: t.pension_salary_basis,
                regularPensionPremiums: t.regular_pension_premiums,
                vacationPensionPremiums: t.vacation_pension_premiums,
                salaryExchangeSacrifice: t.salary_exchange_sacrifice,
                salaryExchangePensionContributions: t.salary_exchange_pension_contributions), issue: issue,
                entries: Array(UnsafeBufferPointer(start: result.entries, count: result.entries_count)))
        }
    }

    private static func optional(_ value: UInt32?) -> SwedishTaxOptionalU32 {
        var result = SwedishTaxOptionalU32()
        result.is_some = value == nil ? 0 : 1
        result.value = value ?? 0
        return result
    }

    private static func entryForRust(_ value: IncomeEntry) -> SwedishTaxIncomeEntry {
        var result = SwedishTaxIncomeEntry()
        result.id = value.id
        result.kind = switch value.kind {
        case .annualSalary: 0
        case .monthlySalary: 1
        case .oneTimeSalary: 2
        case .monthlyOccupationalPension: 3
        case .annualOccupationalPension: 4
        case .ownCompanyDividend: 5
        }
        result.amount = value.amount
        result.start.month = UInt32(value.start.month)
        result.start.day = UInt32(value.start.day)
        result.end.month = UInt32(value.end.month)
        result.end.day = UInt32(value.end.day)
        result.use_annual_daily_rate_for_partial_months = value
            .useAnnualDailyRateForPartialMonths ? 1 : 0
        result.payer_role = value.payerRole == .main ? 0 : 1
        result.own_company_sourced = value.ownCompanySourced ? 1 : 0
        result.adjustment_applies = value.adjustmentApplies ? 1 : 0
        result.use_full_year_projection_as_adjustment_basis = value
            .useFullYearProjectionAsAdjustmentBasis ? 1 : 0
        result.additional_withholding_per_payment = optional(
            value.additionalWithholdingPerPayment
        )
        result.actual_withholding = optional(value.actualWithholding)
        result.vacation_compensation = vacationForRust(value.vacationCompensation)
        result.regular_pension_premium = pensionForRust(value.regularPensionPremium)
        result.salary_exchange = exchangeForRust(value.salaryExchange)
        result.included_in_pension_salary_basis = value.includedInPensionSalaryBasis ? 1 : 0
        return result
    }

    private static func vacationForRust(
        _ value: VacationCompensation?
    ) -> SwedishTaxVacationCompensation {
        var result = SwedishTaxVacationCompensation()
        guard let value else { return result }
        result.is_some = 1
        result.annual_entitlement_days = value.annualEntitlementDays
        result.payout_days = value.payoutDays
        result.rate_basis_points = value.rateBasisPoints
            ?? VacationCompensation.defaultRateBasisPoints
        result.included_in_pension_salary_basis = value.includedInPensionSalaryBasis ? 1 : 0
        result.pension_premium_override = optional(value.pensionPremiumOverride)
        return result
    }

    private static func pensionForRust(
        _ value: RegularPensionPremium?
    ) -> SwedishTaxRegularPensionPremium {
        var result = SwedishTaxRegularPensionPremium()
        guard let value else { return result }
        result.is_some = 1
        result.monthly_override = optional(value.monthlyOverride)
        return result
    }

    private static func exchangeForRust(
        _ value: SalaryExchange?
    ) -> SwedishTaxSalaryExchange {
        var result = SwedishTaxSalaryExchange()
        guard let value else { return result }
        result.is_some = 1
        result.sacrificed_salary = value.sacrificedSalary
        result.employer_adds_uplift = value.employerAddsUplift ? 1 : 0
        result.uplift_basis_points = value.upliftBasisPoints
        result.previous_year_pension_salary_basis = optional(
            value.previousYearPensionSalaryBasis
        )
        result.pension_and_insurance_costs_before_exchange = optional(
            value.pensionAndInsuranceCostsBeforeExchange
        )
        return result
    }

    private static func dividendAllowanceForRust(
        _ value: DividendAllowanceInputs2027
    ) -> SwedishTaxDividendAllowanceInputs {
        var result = SwedishTaxDividendAllowanceInputs()
        result.one_person_company = value.onePersonCompany ? 1 : 0
        result.ownership_basis_points = value.ownershipBasisPoints
        result.other_qualified_ownership_basis_points = value
            .otherQualifiedOwnershipBasisPoints
        result.spouse_ownership_basis_points = value.spouseOwnershipBasisPoints
        result.company_cash_payroll_2026 = value.companyCashPayroll2026
        result.highest_related_cash_salary_2026 = value.highestRelatedCashSalary2026
        result.acquisition_cost = value.acquisitionCost
        result.acquisition_cost_interest_basis_points = optional(
            value.acquisitionCostInterestBasisPoints
        )
        result.saved_allowance = value.savedAllowance
        return result
    }

    fileprivate static func withholdingRule(
        kind: UInt32,
        column: UInt32,
        percent: UInt32
    ) throws -> AppliedWithholding {
        switch kind {
        case 0: return .actualAmount
        case 1: return .table(try taxColumn(column))
        case 2: return .tableAndOneTime(try taxColumn(column), percent)
        case 3: return .oneTimeTable(percent)
        case 4: return .secondary30
        case 5: return .adjustmentPercent(percent)
        case 6: return .none
        default: throw RustTaxCoreError.invalidResponse("Unknown withholding rule \(kind)")
        }
    }

    fileprivate static func incomeBasis(
        _ value: SwedishTaxIncomeBasis
    ) throws -> IncomeBasisEstimate {
        switch value.kind {
        case 0:
            return .estimated(
                IncomeBasisProgress(
                    estimatedBasis: value.estimated_basis,
                    maximumBasis: value.maximum_basis
                )
            )
        case 1: return .notBasedOnSelectedIncome
        case 2: return .requiresAdditionalInformation
        default: throw RustTaxCoreError.invalidResponse("Unknown income basis \(value.kind)")
        }
    }

    private static func taxColumn(_ value: UInt32) throws -> TaxColumn {
        guard let raw = UInt8(exactly: value), let column = TaxColumn(rawValue: raw) else {
            throw RustTaxCoreError.invalidResponse("Invalid tax column \(value)")
        }
        return column
    }
}

private extension PlanCalculation {
    init(rust value: SwedishTaxCalculationResult) throws {
        monthlyIncome = value.monthly_income
        annualIncome = value.annual_income
        ordinaryIncome = value.ordinary_income
        workIncome = value.work_income
        pensionIncome = value.pension_income
        dividendIncome = value.dividend_income
        sgiAnnualRate = value.sgi_annual_rate
        switch value.deduction_kind {
        case 0: tableDeduction = .amount(value.deduction_value)
        case 1: tableDeduction = .percent(value.deduction_value)
        default:
            throw RustTaxCoreError.unsupportedDeductionKind(value.deduction_kind)
        }
        annualTax = AnnualTax(
            assessedIncome: value.annual_tax.assessed_income,
            basicAllowance: value.annual_tax.basic_allowance,
            taxableIncome: value.annual_tax.taxable_income,
            stateIncomeTax: value.annual_tax.state_income_tax,
            municipalIncomeTax: value.annual_tax.municipal_income_tax,
            burialAndReligiousFee: value.annual_tax.burial_and_religious_fee,
            pensionFee: value.annual_tax.pension_fee,
            pensionFeeCredit: value.annual_tax.pension_fee_credit,
            workIncomeCredit: value.annual_tax.work_income_credit,
            sicknessCompensationCredit: value.annual_tax.sickness_compensation_credit,
            earnedIncomeCredit: value.annual_tax.earned_income_credit,
            publicServiceFee: value.annual_tax.public_service_fee,
            total: value.annual_tax.total
        )
        if value.has_adjustment_calibration == 0 {
            adjustmentCalibration = nil
        } else {
            let calibration = value.adjustment_calibration
            adjustmentCalibration = AdjustmentCalibration(
                basisIncome: calibration.basis_income,
                percent: calibration.percent,
                formulaTaxAtBasis: calibration.formula_tax_at_basis,
                assumedTaxAtBasis: calibration.assumed_tax_at_basis,
                impliedTaxAdjustment: calibration.implied_tax_adjustment,
                projectedOrdinaryTax: calibration.projected_ordinary_tax
            )
        }
        ordinaryFinalTax = value.ordinary_final_tax
        dividendTax = value.dividend_tax
        totalTax = value.total_tax
        let entries: [EntryWithholding]
        if value.withholding_entries_count == 0 {
            entries = []
        } else {
            guard let start = value.withholding_entries else {
                throw RustTaxCoreError.invalidResponse("Missing withholding entries")
            }
            entries = try UnsafeBufferPointer(
                start: start,
                count: value.withholding_entries_count
            ).map { entry in
                EntryWithholding(
                    entryID: entry.entry_id,
                    gross: entry.gross,
                    withheld: entry.withheld,
                    regularWithheld: entry.regular_withheld,
                    supplementalWithheld: entry.supplemental_withheld,
                    additionalWithheld: entry.additional_withheld,
                    rule: try RustTaxCore.withholdingRule(
                        kind: entry.rule_kind,
                        column: entry.rule_column,
                        percent: entry.rule_percent
                    )
                )
            }
        }
        withholding = WithholdingSummary(total: value.withholding_total, entries: entries)
        withheldTax = value.withheld_tax
        regularPensionPremiums = value.regular_pension_premiums
        vacationPensionPremiums = value.vacation_pension_premiums
        salaryExchangeSacrifice = value.salary_exchange_sacrifice
        salaryExchangePensionContributions = value.salary_exchange_pension_contributions
        pensionSalaryBasis = value.pension_salary_basis
        employerPensionContributions = value.employer_pension_contributions
        marginalRate = value.marginal_rate
        pensionProgress = try RustTaxCore.incomeBasis(value.pension_progress)
        sgiProgress = try RustTaxCore.incomeBasis(value.sgi_progress)
    }
}
