import SwiftUI

@MainActor
@Observable
final class ChallengesViewModel {
    var challenges: [ChallengeStatus] = []
    var isLoading = false
    var errorMessage: String?
    var paywallMessage: String?

    func load() async {
        isLoading = challenges.isEmpty
        defer { isLoading = false }
        do {
            challenges = try await APIClient.shared.get("challenges")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func join(_ status: ChallengeStatus) async {
        do {
            _ = try await APIClient.shared.postVoid("challenges/\(status.challenge.id.uuidString)/join")
            await load()
        } catch APIError.paymentRequired(let message) {
            paywallMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leave(_ status: ChallengeStatus) async {
        _ = try? await APIClient.shared.delete("challenges/\(status.challenge.id.uuidString)/leave")
        await load()
    }
}

struct ChallengesView: View {
    @Binding var showPaywall: Bool
    @State private var model = ChallengesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }
                if let message = model.paywallMessage {
                    VStack(spacing: 10) {
                        Text(message).font(.footnote)
                        Button("See Premium") { showPaywall = true }
                            .buttonStyle(.borderedProminent).tint(Palette.pine)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Palette.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                ForEach(model.challenges) { status in card(status) }

                if model.challenges.isEmpty && !model.isLoading {
                    EmptyStateView(
                        systemImage: "flag.checkered",
                        title: "No challenges available",
                        message: "Check back soon — new challenges are added regularly.",
                        actionTitle: "Reload",
                        action: { Task { await model.load() } }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func card(_ status: ChallengeStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: icon(for: status.challenge.kind))
                    .font(.title2)
                    .foregroundStyle(tint(for: status.challenge.kind))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tint(for: status.challenge.kind).opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.challenge.title).font(.headline)
                    Text(status.challenge.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if status.completed {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.pine)
                }
            }

            Text(status.challenge.description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if status.joined {
                VStack(spacing: 6) {
                    ProgressBar(value: status.progressPct / 100, tint: tint(for: status.challenge.kind))
                    HStack {
                        Text(progressLabel(status)).font(.caption).monospacedDigit()
                        Spacer()
                        Text("\(status.daysLeft) days left").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Label("\(status.participants) joined", systemImage: "person.2")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label("\(status.challenge.xpReward) XP", systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(Palette.amber)
            }

            if status.joined {
                Button("Leave challenge", role: .destructive) { Task { await model.leave(status) } }
                    .font(.footnote)
            } else {
                Button("Join") { Task { await model.join(status) } }
                    .buttonStyle(.borderedProminent)
                    .tint(tint(for: status.challenge.kind))
                    .frame(maxWidth: .infinity)
            }
        }
        .cardSurface()
    }

    private func progressLabel(_ status: ChallengeStatus) -> String {
        switch status.challenge.kind {
        case "weight": String(format: "%.1f of %.1f kg", status.progress, status.challenge.targetValue)
        default: "\(Int(status.progress)) of \(Int(status.challenge.targetValue)) days"
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "weight": "scalemass"
        case "steps": "shoeprints.fill"
        default: "nosign"
        }
    }

    private func tint(for kind: String) -> Color {
        switch kind {
        case "weight": Palette.pine
        case "steps": Palette.plum
        default: Palette.coral
        }
    }
}
