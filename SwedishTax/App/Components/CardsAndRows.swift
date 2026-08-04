import SwiftUI

struct EditorCard<Content: View>: View {
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

struct TaxCard<Content: View>: View {
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

struct ResultCard: View {
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

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

struct HelpButton: View {
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

struct ValueRow: Identifiable {
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

struct ValueRows: View {
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

struct IncomeBasisRow: View {
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
