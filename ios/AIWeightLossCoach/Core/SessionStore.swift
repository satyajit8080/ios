import AuthenticationServices
import Foundation
import Observation
 
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case loading
        case signedOut
        case onboarding
        case signedIn
    }
 
    var phase: Phase = .loading
    var user: AppUser?
    var errorMessage: String?
    var isWorking = false
 
    private let api = APIClient.shared
 
    func bootstrap() async {
        if await api.isSignedIn {
            do {
                user = try await api.get("auth/me")
                phase = (user?.onboarded ?? false) ? .signedIn : .onboarding
                return
            } catch {
                await api.clearTokens()
            }
        }
        phase = .signedOut
    }
 
    func register(email: String, password: String, fullName: String) async {
        await run {
            let body = ["email": email, "password": password, "full_name": fullName]
            let response: AuthResponse = try await self.api.post("auth/register", body: body)
            await self.adopt(response)
        }
    }
 
    func login(email: String, password: String) async {
        await run {
            let response: AuthResponse = try await self.api.post(
                "auth/login", body: ["email": email, "password": password]
            )
            await self.adopt(response)
        }
    }
 
    func signInWithApple(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign-in didn't complete. Try again."
            }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple didn't return a usable token."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
 
            await run {
                var body: [String: String] = ["identity_token": identityToken]
                if !name.isEmpty { body["full_name"] = name }
                let response: AuthResponse = try await self.api.post("auth/apple", body: body)
                await self.adopt(response)
            }
        }
    }
 
    func requestPasswordReset(email: String) async -> Bool {
        do {
            _ = try await api.postVoid("auth/forgot-password", body: ["email": email])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
 
    func refreshUser() async {
        guard phase != .signedOut else { return }
        do {
            user = try await api.get("auth/me")
        } catch APIError.unauthorized {
            await signOut()
        } catch {
            // A failed refresh should not knock the person out of the app.
        }
    }
 
    func updateProfile(_ fields: [String: AnyEncodable]) async {
        await run {
            let updated: AppUser = try await self.api.patch("users/me", body: fields)
            self.user = updated
            if updated.onboarded { self.phase = .signedIn }
        }
    }
 
    func completeOnboarding() {
        phase = .signedIn
    }
 
    func signOut() async {
        if let refresh = await api.currentRefreshToken() {
            _ = try? await api.postVoid("auth/logout", body: ["refresh_token": refresh])
        }
        await api.clearTokens()
        user = nil
        phase = .signedOut
    }
 
    func deleteAccount() async {
        await run {
            _ = try await self.api.delete("users/me")
            await self.api.clearTokens()
            self.user = nil
            self.phase = .signedOut
        }
    }
 
    private func adopt(_ response: AuthResponse) async {
        await api.setTokens(access: response.tokens.accessToken, refresh: response.tokens.refreshToken)
        user = response.user
        phase = response.user.onboarded ? .signedIn : .onboarding
    }
 
    private func run(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
 
/// Type-erased encodable so profile patches can mix strings, numbers and dates.
/// Type-erased `Encodable` for building heterogeneous JSON bodies.
///
/// `Sendable` because the wrapped value is captured immutably and only ever
/// read during encoding. Without this, passing a `[String: AnyEncodable]` to the
/// `APIClient` actor is rejected under Swift 6 as a possible data race.
struct AnyEncodable: Encodable, Sendable {
    private let encodeAction: @Sendable (Encoder) throws -> Void
 
    init<T: Encodable & Sendable>(_ value: T) {
        encodeAction = { encoder in try value.encode(to: encoder) }
    }
 
    func encode(to encoder: Encoder) throws {
        try encodeAction(encoder)
    }
}
