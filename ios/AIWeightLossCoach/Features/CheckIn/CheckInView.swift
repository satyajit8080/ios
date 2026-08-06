import SwiftUI

@MainActor
@Observable
final class CheckInViewModel {
    var prompt: CheckInPrompt?
    var result: CheckIn?
    var answers: [String: JSONValue] = [:]
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?
    var history: [CheckIn] = []
    var streak = 0

    private let api = APIClient.shared

    var canSubmit: Bool {
        guard let prompt else { return false }
        // The three scales are required; free text and extras are optional.
        let required = prompt.questions.filter { $0.type == "scale" }.map(\.id)
        return required.allSatisfy { answers[$0] != nil } && !isSubmitting
    }

    func load() async {
        isLoading = prompt == nil
        defer { isLoading = false }
        do {
            prompt = try await api.get("checkin/today")
            streak = prompt?.streak ?? 0
            if prompt?.completed == true {
                let past: CheckInHistory = try await api.get("checkin", query: ["limit": "30"])
                history = past.entries
                streak = past.streak
                result = past.entries.first
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            result = try await api.post("checkin", body: ["answers": answers])
            let past: CheckInHistory = try await api.get("checkin", query: ["limit": "30"])
            history = past.entries
            streak = past.streak
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func redo() {
        result = nil
        answers = [:]
    }
}

struct CheckInView: View {
    @State private var model = CheckInViewModel()
    @State private var showHistory = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if model.streak > 0 { streakBanner }

                if let result = model.result {
                    resultCard(result)
                    if !model.history.isEmpty { historyCard }
                } else if let prompt = model.prompt {
                    intro(prompt)
                    ForEach(prompt.questions) { question in
                        questionCard(question)
                    }
                    submitButton
                } else if model.isLoading {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily check-in")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var streakBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(Palette.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.streak) day streak").font(.subheadline.weight(.semibold))
                Text("Consecutive check-ins").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Palette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func intro(_ prompt: CheckInPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How's it going?").font(.title3.weight(.semibold))
            Text("Five quick questions. The coach reads them alongside your weight, calories and steps, then tells you what's actually worth changing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let steps = prompt.metrics["steps_today"]?.intValue,
               let weight = prompt.metrics["current_weight_kg"]?.doubleValue {
                Divider().padding(.vertical, 4)
                HStack(spacing: 12) {
                    miniMetric("Weight", Units.kg(weight))
                    miniMetric("Steps today", Units.count(steps))
                    if let logged = prompt.metrics["days_logged_last_7"]?.intValue {
                        miniMetric("Logged", "\(logged)/7 days")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func miniMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Question rendering

    @ViewBuilder
    private func questionCard(_ question: CheckInQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text).font(.subheadline.weight(.medium))

            switch question.type {
            case "scale": scaleInput(question)
            case "choice": choiceInput(question)
            case "number": numberInput(question)
            default: textInput(question)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func scaleInput(_ question: CheckInQuestion) -> some View {
        let low = Int(question.min ?? 1)
        let high = Int(question.max ?? 5)
        let selected = model.answers[question.id]?.intValue

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(low...high, id: \.self) { value in
                    Button {
                        model.answers[question.id] = .number(Double(value))
                    } label: {
                        Text("\(value)")
                            .font(.headline)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected == value ? Palette.pine : Color(.tertiarySystemGroupedBackground))
                            )
                            .foregroundStyle(selected == value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let labels = question.labels, labels.count >= 2 {
                HStack {
                    Text(labels.first ?? "").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let selected, selected - low < labels.count {
                        Text(labels[selected - low])
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.pine)
                    }
                    Spacer()
                    Text(labels.last ?? "").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func choiceInput(_ question: CheckInQuestion) -> some View {
        let selected = model.answers[question.id]?.stringValue

        return VStack(spacing: 8) {
            ForEach(question.options ?? [], id: \.self) { option in
                Button {
                    model.answers[question.id] = .string(option)
                } label: {
                    HStack {
                        Image(systemName: selected == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == option ? Palette.pine : Color(.systemGray3))
                        Text(option).font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func numberInput(_ question: CheckInQuestion) -> some View {
        let value = model.answers[question.id]?.doubleValue ?? 7

        return VStack(spacing: 6) {
            HStack {
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer()
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { model.answers[question.id] = .number($0) }
                ),
                in: (question.min ?? 0)...(question.max ?? 14),
                step: 0.5
            )
            .tint(Palette.pine)
        }
    }

    private func textInput(_ question: CheckInQuestion) -> some View {
        TextField(
            "Optional",
            text: Binding(
                get: { model.answers[question.id]?.stringValue ?? "" },
                set: { model.answers[question.id] = $0.isEmpty ? nil : .string($0) }
            ),
            axis: .vertical
        )
        .lineLimit(2...5)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            if model.isSubmitting {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Reading your numbers…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Get today's read").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Palette.pine)
        .disabled(!model.canSubmit)
    }

    // MARK: - Result

    private func resultCard(_ result: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let focus = result.focus, !focus.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's focus").sectionTitle()
                    Text(focus)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.pine)
                }
            }

            if let summary = result.summary {
                Text(summary)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if !result.recommendations.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("What to do").sectionTitle()
                    ForEach(Array(result.recommendations.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle().fill(Palette.pine.opacity(0.15)).frame(width: 22, height: 22)
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.pine)
                            }
                            Text(item).font(.subheadline)
                        }
                    }
                }
            }

            if result.provider == "fallback" {
                Text("The coach was unreachable, so this read comes straight from your numbers.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Checked in \(result.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Redo") { model.redo() }
                    .font(.caption.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent check-ins").sectionTitle()
            ForEach(model.history.dropFirst().prefix(7)) { entry in
                NavigationLink {
                    pastDetail(entry)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.recordedOn.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if let focus = entry.focus {
                                Text(focus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let mood = entry.mood {
                            Text(moodGlyph(mood)).font(.subheadline)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .cardSurface()
    }

    private func pastDetail(_ entry: CheckIn) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = entry.summary {
                    Text(summary).font(.callout)
                }
                if !entry.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommendations").sectionTitle()
                        ForEach(Array(entry.recommendations.enumerated()), id: \.offset) { _, item in
                            Label(item, systemImage: "arrow.right.circle")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(entry.recordedOn.formatted(.dateTime.day().month()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moodGlyph(_ mood: Int) -> String {
        switch mood {
        case 1: "😔"
        case 2: "😕"
        case 3: "😐"
        case 4: "🙂"
        default: "😄"
        }
    }
}
