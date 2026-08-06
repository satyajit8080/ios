DSGlass.swift
//  AI Weight Loss Coach — Design System
//
//  Liquid Glass (iOS 26+) behind availability checks, falling back to
//  `.ultraThinMaterial` on iOS 17–25.
//
//  ── WHERE GLASS IS ALLOWED ──────────────────────────────────────────
//  Apple's HIG puts Liquid Glass in the FUNCTIONAL layer only:
//
//      ✅ Tab bar
//      ✅ Floating action buttons
//      ✅ Navigation bars and toolbars
//      ✅ Sheet chrome (handle, header, footer bar)
//      ✅ Context menus, transient overlays
//
//      ❌ Login form            ❌ Dashboard cards
//      ❌ Meal cards            ❌ Chat bubbles
//      ❌ Analytics cards       ❌ Paywall content
//
//  Content stays on solid `DSCard`. Two reasons this is a rule and not
//  a preference: stacked glass goes muddy fast, and glass behind dense
//  text fails contrast. An app with glass everywhere reads as one that
//  found a new modifier, not one that was designed.
//
//  ── ACCESSIBILITY ───────────────────────────────────────────────────
//  Reduce Transparency is honoured everywhere: the surface goes fully
//  opaque. Always test with it on — it is the single most common
//  Liquid Glass review failure.
//
 
import SwiftUI
 
// MARK: - Glass modifier
 
extension View {
 
    /// Applies Liquid Glass on iOS 26+, `.ultraThinMaterial` below, and a
    /// solid surface when Reduce Transparency is on.
    ///
    /// Apply this AFTER layout and appearance modifiers — padding and
    /// frame first, glass last.
    ///
    ///     Image(systemName: "camera")
    ///         .padding(DS.Space.lg)
    ///         .dsGlass(in: Circle(), interactive: true)
    ///
    /// - Parameters:
    ///   - shape: The glass surface's shape. Keep this consistent across
    ///     related elements or the group stops reading as one control.
    ///   - interactive: True for anything tappable. Adds the touch
    ///     response Liquid Glass uses to signal interactivity.
    ///   - tint: Semantic only — a primary action or an active state.
    ///     Never decoration.
    func dsGlass<S: Shape>(
        in shape: S = Capsule(),
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(DSGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }
}
 
private struct DSGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
 
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
 
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            // Fully opaque. No blur, no translucency.
            content
                .background(DS.Colors.surface, in: shape)
                .overlay(shape.stroke(DS.Colors.separator, lineWidth: 0.5))
        } else if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(DS.Colors.separator, lineWidth: 0.5))
        }
    }
 
    @available(iOS 26, *)
    private var glass: Glass {
        var result = Glass.regular
        if let tint {
            result = result.tint(tint)
        }
        if interactive {
            result = result.interactive()
        }
        return result
    }
}
 
// MARK: - Glass container
//
// Wrap sibling glass elements so they blend and morph as a group rather
// than reading as separate panes. Required whenever two or more glass
// surfaces sit near each other — the tab bar and its floating button,
// for instance.
 
struct DSGlassContainer<Content: View>: View {
    var spacing: CGFloat = DS.Space.lg
    @ViewBuilder var content: () -> Content
 
    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
 
// MARK: - Morphing identity
//
// Give two glass elements the same ID inside a container and iOS 26
// morphs one into the other across a state change. Below iOS 26 this is
// a no-op and the change is a plain transition.
 
extension View {
    @ViewBuilder
    func dsGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
 
// MARK: - Glass button style
 
extension View {
    /// System glass button styling on iOS 26+, the standard press
    /// animation below. For toolbar and floating actions only.
    @ViewBuilder
    func dsGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(DSPressStyle())
        }
    }
}
 
// MARK: - Capability check
//
// Useful for deciding layout, not just material — glass surfaces need
// slightly more breathing room than opaque ones.
 
extension DS {
    enum Capability {
        /// True when real Liquid Glass will render.
        @MainActor
        static var hasLiquidGlass: Bool {
            if #available(iOS 26, *) {
                return !UIAccessibility.isReduceTransparencyEnabled
            }
            return false
        }
    }
}
 
// MARK: - Sheet chrome
//
// Sheet backgrounds get glass; sheet CONTENT does not.
 
struct DSSheetChrome<Content: View>: View {
    var title: String?
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content
 
    var body: some View {
        VStack(spacing: 0) {
            DSSheetHandle()
 
            if title != nil || onClose != nil {
                HStack {
                    if let title {
                        Text(title)
                            .dsText(DS.Typography.title3)
                    }
                    Spacer(minLength: DS.Space.sm)
                    if let onClose {
                        DSIconButton(
                            icon: "xmark",
                            tint: DS.Colors.textSecondary,
                            background: .clear,
                            accessibilityTitle: "Close"
                        ) { onClose() }
                        .dsGlass(in: Circle(), interactive: true)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.vertical, DS.Space.md)
            }
 
            content()
        }
        .background(DS.Colors.background)
    }
}
