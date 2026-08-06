//
//  DSControls.swift
//  AI Weight Loss Coach — Design System
//
//  Buttons, chips and selection controls. All of them carry their own
//  haptic and press animation, so callers never have to remember.
//
 
import SwiftUI
 
// MARK: - Press style
 
/// Scales and dims on press. Applied to every tappable surface.
struct DSPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
 
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
 
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}
 
// MARK: - Primary button
 
struct DSPrimaryButton: View {
    let title: String
    var icon: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var fullWidth: Bool = true
    let action: () -> Void
 
    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            DS.Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: DS.Size.iconSm, weight: .bold))
                    }
                    Text(title)
                        .font(DS.Typography.button)
                }
            }
            .foregroundStyle(DS.Colors.textOnBrand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: DS.Size.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : DS.Space.xl)
            .background(
                Capsule().fill(DS.Colors.brandGradient)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .dsShadow(.low)
        }
        .buttonStyle(DSPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityHint(isLoading ? "Loading" : "")
    }
}
 
// MARK: - Secondary button
 
struct DSSecondaryButton: View {
    let title: String
    var icon: String?
    var fullWidth: Bool = true
    let action: () -> Void
 
    var body: some View {
        Button {
            DS.Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DS.Size.iconSm, weight: .semibold))
                }
                Text(title)
                    .font(DS.Typography.button)
            }
            .foregroundStyle(DS.Colors.brand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: DS.Size.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : DS.Space.xl)
            .background(Capsule().fill(DS.Colors.brandSoft))
        }
        .buttonStyle(DSPressStyle())
    }
}
 
// MARK: - Text button
 
struct DSTextButton: View {
    let title: String
    var tint: Color = DS.Colors.brand
    let action: () -> Void
 
    var body: some View {
        Button {
            DS.Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(DS.Typography.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .dsTapTarget()
        }
        .buttonStyle(DSPressStyle(scale: 0.94))
    }
}
 
// MARK: - Icon button
 
struct DSIconButton: View {
    let icon: String
    var tint: Color = DS.Colors.textPrimary
    var background: Color = DS.Colors.surfaceSunken
    var accessibilityTitle: String
    let action: () -> Void
 
    var body: some View {
        Button {
            DS.Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: DS.Size.iconMd, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .background(background, in: Circle())
        }
        .buttonStyle(DSPressStyle(scale: 0.9))
        .accessibilityLabel(accessibilityTitle)
    }
}
 
// MARK: - Chip
 
struct DSChip: View {
    let title: String
    var icon: String?
    var isSelected: Bool = false
    var tint: Color = DS.Colors.brand
    let action: () -> Void
 
    var body: some View {
        Button {
            DS.Haptics.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(DS.Typography.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? DS.Colors.textOnBrand : DS.Colors.textSecondary)
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.chipHeight)
            .background(
                Capsule()
                    .fill(isSelected ? tint : DS.Colors.surfaceSunken)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : DS.Colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
 
// MARK: - Segmented control
//
// A custom control rather than Picker(.segmented) so it can carry the
// brand fill and an animated selection pill.
 
struct DSSegmentedControl<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
 
    @Namespace private var namespace
 
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
 
                Button {
                    DS.Haptics.selection()
                    withAnimation(DS.Motion.snappy) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(DS.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(
                            isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(DS.Colors.surface)
                                    .dsShadow(.low)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(DS.Space.xs)
        .background(Capsule().fill(DS.Colors.surfaceSunken))
    }
}
 
// MARK: - Toggle row
 
struct DSToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var tint: Color = DS.Colors.brand
    @Binding var isOn: Bool
 
    var body: some View {
        HStack(spacing: DS.Space.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.Size.iconSm, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
 
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .dsText(DS.Typography.bodyEmphasis)
                if let subtitle {
                    Text(subtitle)
                        .dsText(DS.Typography.footnote, color: DS.Colors.textSecondary)
                }
            }
 
            Spacer(minLength: DS.Space.sm)
 
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, DS.Space.xs)
        .dsHaptic(.selection, on: isOn)
        .accessibilityElement(children: .combine)
    }
}
 
// MARK: - List row
 
struct DSListRow: View {
    let title: String
    var value: String?
    var icon: String?
    var tint: Color = DS.Colors.brand
    var showsChevron: Bool = true
    var action: (() -> Void)?
 
    var body: some View {
        Button {
            DS.Haptics.tap()
            action?()
        } label: {
            HStack(spacing: DS.Space.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DS.Size.iconSm, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
 
                Text(title)
                    .dsText(DS.Typography.body)
 
                Spacer(minLength: DS.Space.sm)
 
                if let value {
                    Text(value)
                        .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                }
 
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.textTertiary)
                }
            }
            .frame(minHeight: DS.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle(scale: 0.99))
        .disabled(action == nil)
    }
}
 
// MARK: - Text field
//
// Content layer — solid surface, never glass. The focus ring is the only
// state signal, so it has to be unmistakable.
 
struct DSTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var isSecure: Bool = false
    /// Shown in danger colour under the field. Nil hides the row entirely.
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection: Bool = false
 
    @FocusState private var isFocused: Bool
 
    private var borderColor: Color {
        if error != nil { return DS.Colors.danger }
        return isFocused ? DS.Colors.brand : DS.Colors.border
    }
 
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DS.Size.iconSm, weight: .medium))
                        .foregroundStyle(isFocused ? DS.Colors.brand : DS.Colors.textTertiary)
                        .frame(width: 20)
                }
 
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .focused($isFocused)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textPrimary)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(disableAutocorrection)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.5 : 1)
            )
            .dsAnimation(DS.Motion.snappy, value: isFocused)
 
            if let error {
                Text(error)
                    .dsText(DS.Typography.caption, color: DS.Colors.danger)
                    .transition(.opacity)
            }
        }
        .dsAnimation(DS.Motion.gentle, value: error)
    }
}
 
// MARK: - Slider row
//
// Label, live value, and a track. Used throughout onboarding.
 
struct DSSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Formatted value shown on the right, e.g. "72.5 kg".
    let display: String
    var tint: Color = DS.Colors.brand
 
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text(label)
                    .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                Spacer()
                Text(display)
                    .dsText(DS.Typography.metricSmall)
            }
            Slider(value: $value, in: range, step: step)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
 
#Preview("Fields") {
    @Previewable @State var email = ""
    @Previewable @State var weight = 75.0
 
    return VStack(spacing: DS.Space.lg) {
        DSTextField(
            placeholder: "Email",
            text: $email,
            icon: "envelope",
            contentType: .emailAddress,
            keyboard: .emailAddress,
            autocapitalization: .never,
            disableAutocorrection: true
        )
        DSTextField(
            placeholder: "Password",
            text: .constant(""),
            icon: "lock",
            isSecure: true,
            error: "At least 8 characters."
        )
        DSSliderRow(
            label: "Current weight",
            value: $weight,
            range: 35...250,
            step: 0.5,
            display: String(format: "%.1f kg", weight)
        )
    }
    .padding(DS.Space.lg)
    .background(DS.Colors.background)
}
 
#Preview("Controls") {
    @Previewable @State var segment = 1
    @Previewable @State var toggle = true
 
    return ScrollView {
        VStack(spacing: DS.Space.lg) {
            DSPrimaryButton(title: "Continue", icon: "arrow.right") {}
            DSPrimaryButton(title: "Saving", isLoading: true) {}
            DSSecondaryButton(title: "Scan a meal", icon: "camera.fill") {}
            DSTextButton(title: "Skip for now") {}
 
            DSSegmentedControl(
                options: [(0, "Week"), (1, "Month"), (2, "Year")],
                selection: $segment
            )
 
            HStack(spacing: DS.Space.sm) {
                DSChip(title: "High protein", icon: "bolt.fill", isSelected: true) {}
                DSChip(title: "Vegetarian") {}
            }
 
            DSCard {
                VStack(spacing: DS.Space.md) {
                    DSToggleRow(
                        title: "Daily reminders",
                        subtitle: "A nudge at 9am if you haven't logged",
                        icon: "bell.fill",
                        isOn: $toggle
                    )
                    Divider().overlay(DS.Colors.separator)
                    DSListRow(title: "Goal weight", value: "76 kg", icon: "target") {}
                }
            }
        }
        .padding(DS.Space.lg)
    }
    .background(DS.Colors.background)
}
