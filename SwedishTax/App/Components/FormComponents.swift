import SwiftUI
import UIKit

struct Date2026Field: View {
    let title: String
    @Binding var value: Date2026

    init(title: String, value: Binding<Date2026>) {
        self.title = title
        _value = value
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Picker("Month", selection: $value.month) {
                    ForEach(UInt8(1)...UInt8(12), id: \.self) { month in
                        Text(monthName(month)).tag(month)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(title) month")

                Picker("Day", selection: $value.day) {
                    ForEach(UInt8(1)...Date2026.daysInMonth(value.month), id: \.self) { day in
                        Text(String(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("\(title) day")

                Text("2026")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.taxField, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.taxBorder, lineWidth: 0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .onChange(of: value.month) { _, newMonth in
            value.day = min(value.day, Date2026.daysInMonth(newMonth))
        }
    }
}

struct SelectAllTextField: View {
    let prompt: String
    @Binding var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        TextField(
            text: $text,
            selection: $selection,
            prompt: Text(prompt)
        ) {
            Text(prompt)
        }
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { selectAll() }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }
}

struct UIntField: View {
    let title: String
    @Binding var value: UInt32
    let suffix: String
    let maximum: UInt32
    @State private var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(
        title: String,
        value: Binding<UInt32>,
        suffix: String,
        maximum: UInt32 = 100_000_000
    ) {
        self.title = title
        _value = value
        self.suffix = suffix
        self.maximum = maximum
        _text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                TextField(
                    text: $text,
                    selection: $selection,
                    prompt: Text("0")
                ) {
                    Text(title)
                }
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 70)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = String(value)
                        selectAll()
                    } else {
                        text = String(value)
                    }
                }
                .onChange(of: text) { _, newText in
                    updateValue(from: newText)
                }
                .onChange(of: value) { _, newValue in
                    if !isFocused { text = String(newValue) }
                }
                Text(suffix)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func updateValue(from newText: String) {
        let digits = newText.filter { $0.isASCII && $0.isNumber }
        if digits != newText {
            text = digits
            return
        }
        guard !digits.isEmpty else {
            value = 0
            return
        }

        let parsed = UInt64(digits) ?? UInt64(maximum)
        let limited = UInt32(min(parsed, UInt64(maximum)))
        value = limited
        if parsed > UInt64(maximum) { text = String(limited) }
    }
}

struct BasisPointsPercentageField: View {
    let title: String
    @Binding var basisPoints: UInt32
    let maximumBasisPoints: UInt32
    @State private var text: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(
        title: String,
        basisPoints: Binding<UInt32>,
        maximumBasisPoints: UInt32 = 10_000
    ) {
        self.title = title
        _basisPoints = basisPoints
        self.maximumBasisPoints = maximumBasisPoints
        _text = State(initialValue: formatBasisPointsPercentage(basisPoints.wrappedValue))
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                TextField(
                    text: $text,
                    selection: $selection,
                    prompt: Text("0")
                ) { Text(title) }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 70)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = formatBasisPointsPercentage(basisPoints)
                        selectAll()
                    } else {
                        text = formatBasisPointsPercentage(basisPoints)
                    }
                }
                .onChange(of: text) { _, newText in updateValue(from: newText) }
                .onChange(of: basisPoints) { _, newValue in
                    if !isFocused { text = formatBasisPointsPercentage(newValue) }
                }
                Text("%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectAll() {
        DispatchQueue.main.async {
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func updateValue(from input: String) {
        let sanitized = sanitizePercentageText(input)
        if sanitized != input {
            text = sanitized
            return
        }
        guard let parsed = parseBasisPointsPercentage(sanitized) else { return }
        let limited = min(parsed, maximumBasisPoints)
        basisPoints = limited
        if parsed > maximumBasisPoints {
            text = formatBasisPointsPercentage(limited)
        }
    }
}

struct PercentageStepper: View {
    let title: String
    @Binding var value: UInt32

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                Button {
                    if value > 0 { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 40, height: 36)
                }
                .disabled(value == 0)
                .accessibilityLabel("Decrease percentage")

                Text("\(value)%")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 58, minHeight: 36)
                    .overlay(alignment: .leading) { Divider() }
                    .overlay(alignment: .trailing) { Divider() }
                    .accessibilityLabel("\(value) percent")

                Button {
                    if value < 100 { value += 1 }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 40, height: 36)
                }
                .disabled(value == 100)
                .accessibilityLabel("Increase percentage")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.taxBlue)
            .background(Color.taxField, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.taxBorder, lineWidth: 0.75)
            }
        }
    }
}
