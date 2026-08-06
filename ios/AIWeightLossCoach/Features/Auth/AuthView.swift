import AuthenticationServices
import SwiftUI
 
struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
 
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var showReset = false
    /// Errors only appear once a field has been left, not while typing.
    @State private var didBlurEmail = false
    @State private var didBlurPassword = false
 
    enum Mode { case signIn, signUp }
 
    private var emailError: String? {
        guard didBlurEmail, !email.isEmpty, !email.contains("@") else { return nil }
        return "That doesn't look like an email address."
    }
 
    private var passwordError: String? {
        guard didBlurPassword, !password.isEmpty, password.count < 8 else { return nil }
        return "At least 8 characters."
    }
 
    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8 && (mode == .signIn || !fullName.isEmpty)
    }
 
    var body: some View {
        ZStack {
            background
 
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Space.xl) {
                    header
                    form
                    divider
                    appleButton
                    footer
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.bottom, DS.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showReset) { PasswordResetView(email: email) }
    }
 
    // MARK: Background
 
    private var background: some View {
        ZStack {
            DS.Colors.background
            // A soft wash rather than a full-bleed gradient — the form has
            // to stay readable, and text on saturated colour does not.
            RadialGradient(
                colors: [DS.Colors.brand.opacity(0.18), .clear],
                center: .init(x: 0.85, y: 0.05),
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [DS.Colors.ai.opacity(0.14), .clear],
                center: .init(x: 0.1, y: 0.22),
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
 
    // MARK: Header
 
    private var header: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.Colors.textOnBrand)
                .frame(width: 76, height: 76)
                .background(Circle().fill(DS.Colors.brandGradient))
                .dsShadow(.low)
 
            Text("AI Weight Loss Coach")
                .dsText(DS.Typography.title1)
                .multilineTextAlignment(.center)
 
            Text("Track what you eat and move, and get coaching that reads your actual numbers.")
                .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Space.xxl)
    }
 
    // MARK: Form
 
    private var form: some View {
        VStack(spacing: DS.Space.md) {
            if mode == .signUp {
                DSTextField(
                    placeholder: "Your name",
                    text: $fullName,
                    icon: "person",
                    contentType: .name,
                    autocapitalization: .words
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
 
            DSTextField(
                placeholder: "Email",
                text: $email,
                icon: "envelope",
                error: emailError,
                contentType: .emailAddress,
                keyboard: .emailAddress,
                autocapitalization: .never,
                disableAutocorrection: true
            )
            .onChange(of: email) { _, _ in didBlurEmail = true }
 
            DSTextField(
                placeholder: "Password",
                text: $password,
                icon: "lock",
                isSecure: true,
                error: passwordError,
                contentType: mode == .signIn ? .password : .newPassword
            )
            .onChange(of: password) { _, _ in didBlurPassword = true }
 
            if let message = session.errorMessage {
                DSBanner(kind: .error, message: message)
                    .transition(.opacity)
            }
 
            DSPrimaryButton(
                title: mode == .signIn ? "Sign in" : "Create account",
                isLoading: session.isWorking,
                isEnabled: canSubmit
            ) {
                Task {
                    if mode == .signIn {
                        await session.login(email: email, password: password)
                    } else {
                        await session.register(email: email, password: password, fullName: fullName)
                    }
                }
            }
            .padding(.top, DS.Space.xs)
        }
        .dsAnimation(DS.Motion.standard, value: mode)
        .dsAnimation(DS.Motion.gentle, value: session.errorMessage)
    }
 
    // MARK: Divider
 
    private var divider: some View {
        HStack(spacing: DS.Space.md) {
            Rectangle().fill(DS.Colors.separator).frame(height: 1)
            Text("or").dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
            Rectangle().fill(DS.Colors.separator).frame(height: 1)
        }
    }
 
    // MARK: Apple
 
    private var appleButton: some View {
        // Apple requires its own button here; styling it beyond the
        // supported options risks a review rejection.
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { await session.signInWithApple(result: result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: DS.Size.buttonHeight)
        .clipShape(Capsule())
    }
 
    // MARK: Footer
 
    private var footer: some View {
        VStack(spacing: DS.Space.md) {
            DSTextButton(
                title: mode == .signIn ? "Create an account" : "I already have an account"
            ) {
                withAnimation(DS.Motion.standard) {
                    mode = mode == .signIn ? .signUp : .signIn
                }
            }
 
            if mode == .signIn {
                DSTextButton(title: "Forgot your password?", tint: DS.Colors.textSecondary) {
                    showReset = true
                }
            }
 
            Text("By continuing you agree to our terms and privacy policy.")
                .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Space.sm)
        }
    }
}
 
// MARK: - Password reset
 
struct PasswordResetView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
 
    @State var email: String
    @State private var sent = false
    @State private var isSending = false
 
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.background.ignoresSafeArea()
 
                VStack(spacing: DS.Space.xl) {
                    if sent {
                        DSEmptyState(
                            icon: "envelope.badge",
                            title: "Check your inbox",
                            message: "If that email has an account, a reset link is on its way. It expires in 30 minutes.",
                            actionTitle: "Done",
                            action: { dismiss() }
                        )
                    } else {
                        Text("Enter the email you signed up with and we'll send a reset link.")
                            .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
 
                        DSTextField(
                            placeholder: "Email",
                            text: $email,
                            icon: "envelope",
                            contentType: .emailAddress,
                            keyboard: .emailAddress,
                            autocapitalization: .never,
                            disableAutocorrection: true
                        )
 
                        DSPrimaryButton(
                            title: "Send reset link",
                            isLoading: isSending,
                            isEnabled: email.contains("@")
                        ) {
                            Task {
                                isSending = true
                                sent = await session.requestPasswordReset(email: email)
                                isSending = false
                            }
                        }
 
                        Spacer()
                    }
                }
                .padding(DS.Space.xl)
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
