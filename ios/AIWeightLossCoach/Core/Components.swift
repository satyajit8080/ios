import SwiftUI

struct RingGauge: View {
    let progress: Double
    let lineWidth: CGFloat
    let tint: Color
    var track: Color = Color(.systemGray5)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

struct ProgressBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * max(min(value, 1), 0))
                    .animation(.easeOut(duration: 0.4), value: value)
            }
        }
        .frame(height: height)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.pine)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.pine)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.coral)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button { onDismiss() } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Palette.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PremiumLock: View {
    let feature: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Palette.amber)
            Text("\(feature) is part of Premium")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Unlimited coaching, AI meal plans and photo logging.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("See plans", action: onUpgrade)
                .buttonStyle(.borderedProminent)
                .tint(Palette.pine)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .cardSurface()
    }
}

struct MacroChips: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: 8) {
            chip("Protein", protein, Palette.protein)
            chip("Carbs", carbs, Palette.carbs)
            chip("Fat", fat, Palette.fat)
        }
    }

    private func chip(_ label: String, _ grams: Double, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(Units.grams(grams)).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
