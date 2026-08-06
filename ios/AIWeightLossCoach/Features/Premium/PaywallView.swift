import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @Environment(SessionStore.self) private var session

    @State private var selectedID = AppConfig.annualProductID
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private let benefits: [(String, String, String)] = [
        ("bubble.left.and.text.bubble.right", "Unlimited coaching", "Ask as much as you want, whenever you want."),
        ("list.clipboard", "Meal plans built for you", "Weekly plans and grocery lists around your targets."),
        ("camera.viewfinder", "Unlimited photo scans", "Log a plate in seconds instead of hunting for entries."),
        ("chart.xyaxis.line", "Full history and trends", "Every chart, all the way back.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefitList

                    if store.products.isEmpty {
                        ProgressView().padding(.vertical, 30)
                    } else {
                        planPicker
                    }

                    if let errorMessage {
                        ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }

                    purchaseButton
                    footer
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await restore() } }.font(.subheadline)
                }
            }
            .task { await store.loadProducts() }
            .onChange(of: session.user?.isPremium) { _, isPremium in
                if isPremium == true { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Palette.amber)
            Text("Premium")
                .font(.title.weight(.bold))
            Text("The coaching, planning and history that make the numbers actually useful.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefitList: some View {
        VStack(spacing: 16) {
            ForEach(benefits, id: \.0) { icon, title, detail in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(Palette.pine)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .cardSurface()
    }

    private var planPicker: some View {
        VStack(spacing: 12) {
            ForEach(store.products, id: \.id) { product in
                Button {
                    selectedID = product.id
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: selectedID == product.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedID == product.id ? Palette.pine : Color(.systemGray3))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(product.id == AppConfig.annualProductID ? "Annual" : "Monthly")
                                    .font(.subheadline.weight(.semibold))
                                if product.id == AppConfig.annualProductID,
                                   let saving = store.annualSavingPercent {
                                    Text("Save \(saving)%")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Palette.amber.opacity(0.2), in: Capsule())
                                        .foregroundStyle(Palette.amber)
                                }
                            }
                            Text(subtitle(for: product))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.headline).monospacedDigit()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selectedID == product.id ? Palette.pine : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchase() }
            } label: {
                if isPurchasing {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text(trialLabel).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Palette.pine)
            .disabled(isPurchasing || store.products.isEmpty)

            Text("Cancel any time in Settings. Renews automatically until cancelled.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Link("Terms", destination: AppConfig.termsURL)
            Link("Privacy", destination: AppConfig.privacyURL)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var trialLabel: String {
        guard let product = store.products.first(where: { $0.id == selectedID }) else {
            return "Continue"
        }
        if product.subscription?.introductoryOffer != nil {
            return "Start free week"
        }
        return "Subscribe for \(product.displayPrice)"
    }

    private func subtitle(for product: Product) -> String {
        if product.id == AppConfig.annualProductID {
            return "Billed yearly · one week free"
        }
        return "Billed monthly · one week free"
    }

    private func purchase() async {
        guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        let success = await store.purchase(product)
        if success {
            await session.refreshUser()
            dismiss()
        } else if let failure = store.purchaseError {
            errorMessage = failure
        }
    }

    private func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        await store.restore()
        await session.refreshUser()
        if session.user?.isPremium == true {
            dismiss()
        } else {
            errorMessage = "We couldn't find an active subscription on this Apple ID."
        }
    }
}
