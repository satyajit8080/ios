import SwiftUI

@MainActor
@Observable
final class CoachViewModel {
    var messages: [ChatMessage] = []
    var draft = ""
    var isSending = false
    var isLoading = false
    var errorMessage: String?
    var paywallMessage: String?

    private let api = APIClient.shared

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load() async {
        isLoading = messages.isEmpty
        defer { isLoading = false }
        do {
            messages = try await api.get("coach/history")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isSending = true
        errorMessage = nil
        paywallMessage = nil

        let pending = ChatMessage(id: UUID(), role: "user", content: text, createdAt: Date())
        messages.append(pending)

        do {
            let response: ChatResponse = try await api.post("coach", body: ["message": text])
            messages.append(response.reply)
        } catch APIError.paymentRequired(let message) {
            paywallMessage = message
            messages.removeAll { $0.id == pending.id }
            draft = text
        } catch {
            errorMessage = error.localizedDescription
            messages.removeAll { $0.id == pending.id }
            draft = text
        }
        isSending = false
    }

    func clear() async {
        _ = try? await api.delete("coach/history")
        messages = []
    }
}

struct CoachView: View {
    @Binding var showPaywall: Bool
    @Environment(SessionStore.self) private var session
    @State private var model = CoachViewModel()

    private let starters = [
        "Why has my weight stalled this week?",
        "What should I eat tonight to hit my protein?",
        "How do I stay on track eating out?",
        "Review my last two weeks."
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if model.messages.isEmpty && !model.isLoading {
                                intro
                            }
                            ForEach(model.messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                            if model.isSending {
                                TypingIndicator().id("typing")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.messages.count) {
                        if let last = model.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let message = model.paywallMessage {
                    VStack(spacing: 10) {
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                        Button("See Premium") { showPaywall = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.pine)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Palette.amber.opacity(0.14))
                }

                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                composer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink("Daily check-in") { CheckInView() }
                        NavigationLink("What the coach remembers") { CoachMemoryView() }
                        Divider()
                        Button("Clear conversation", role: .destructive) { Task { await model.clear() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await model.load() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your coach reads your data")
                    .font(.title3.weight(.semibold))
                Text("Weigh-ins, meals, steps and habits all feed into the answers, so ask about your own numbers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(starters, id: \.self) { starter in
                Button {
                    model.draft = starter
                    Task { await model.send() }
                } label: {
                    HStack {
                        Text(starter).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if !(session.user?.isPremium ?? false) {
                Text("Free plan: \(AppConfig.freeCoachMessagesPerDay) messages a day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask your coach…", text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())

            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(model.canSend ? Palette.pine : Color(.systemGray3), in: Circle())
            }
            .disabled(!model.canSend)
        }
        .padding(12)
        .background(.bar)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? Palette.pine : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(isUser ? .white : .primary)
                    .textSelection(.enabled)
                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(.systemGray2))
                    .frame(width: 7, height: 7)
                    .opacity(phase == Double(index) ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { phase = 2 }
        }
    }
}

struct CoachMemoryView: View {
    @State private var memories: [Memory] = []
    @State private var isLoading = true

    struct Memory: Codable, Identifiable, Sendable {
        var id: String { key }
        let key: String
        let value: String
    }

    var body: some View {
        List {
            if memories.isEmpty && !isLoading {
                EmptyStateView(
                    systemImage: "brain",
                    title: "Nothing stored yet",
                    message: "As you chat, the coach keeps durable details like your diet style or allergies. Numbers are never stored here.",
                    actionTitle: nil,
                    action: nil
                )
                .listRowSeparator(.hidden)
            }
            ForEach(memories) { memory in
                VStack(alignment: .leading, spacing: 3) {
                    Text(memory.key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.semibold))
                    Text(memory.value).font(.footnote).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Forget", role: .destructive) {
                        Task {
                            _ = try? await APIClient.shared.delete("coach/memory/\(memory.key)")
                            memories.removeAll { $0.key == memory.key }
                        }
                    }
                }
            }
        }
        .navigationTitle("Coach memory")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            memories = (try? await APIClient.shared.get("coach/memory")) ?? []
            isLoading = false
        }
    }
}
