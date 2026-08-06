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

    enum Mode { case signIn, signUp }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8 && (mode == .signIn || !fullName.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 12) {
                    if mode == .signUp {
                        TextField("Your name", text: $fullName)
                            .textContentType(.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .textFieldStyle(.roundedBorder)

                    if mode == .signUp {
                        Text("At least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let message = session.errorMessage {
                    ErrorBanner(message: message)
                }

                Button {
                    Task {
                        if mode == .signIn {
                            await session.login(email: email, password: password)
                        } else {
                            await session.register(email: email, password: password, fullName: fullName)
                        }
                    }
                } label: {
                    if session.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(mode == .signIn ? "Sign in" : "Create account").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Palette.pine)
                .disabled(!canSubmit || session.isWorking)

                HStack {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await session.signInWithApple(result: result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 10) {
                    Button(mode == .signIn ? "Create an account" : "I already have an account") {
                        withAnimation { mode = mode == .signIn ? .signUp : .signIn }
                    }
                    .font(.subheadline)

                    if mode == .signIn {
                        Button("Forgot your password?") { showReset = true }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                Text("By continuing you agree to our terms and privacy policy.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showReset) { PasswordResetView(email: email) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.pine)
            Text("AI Weight Loss Coach")
                .font(.title2.weight(.bold))
            Text("Track what you eat and move, and get coaching that reads your actual numbers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
}

struct PasswordResetView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if sent {
                    EmptyStateView(
                        systemImage: "envelope.badge",
                        title: "Check your inbox",
                        message: "If that email has an account, a reset link is on its way. It expires in 30 minutes.",
                        actionTitle: "Done",
                        action: { dismiss() }
                    )
                } else {
                    Text("Enter the email you signed up with and we'll send a reset link.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    Button("Send reset link") {
                        Task { sent = await session.requestPasswordReset(email: email) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Palette.pine)
                    .disabled(!email.contains("@"))

                    Spacer()
                }
            }
            .padding(24)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
