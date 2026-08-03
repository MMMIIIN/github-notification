import SwiftUI

/// Sign-in screen. OAuth is primary; a Personal Access Token is the secondary
/// "sign in another way" path.
struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @State private var showingPAT = false
    @State private var patInput = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("GitHub Notifier")
                    .font(.title2).bold()
                Text("Review requests, comments, and mentions —\nright in your menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if case .signingIn = app.auth.state {
                ProgressView().padding(.top, 4)
            }

            if case let .error(message) = app.auth.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await app.auth.signInWithOAuth() }
                } label: {
                    Label("Sign in with GitHub", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!app.auth.isOAuthAvailable || isBusy)

                if !app.auth.isOAuthAvailable {
                    Text("OAuth isn't configured — sign in with a token below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Sign in another way") {
                    showingPAT.toggle()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.horizontal, 24)

            if showingPAT {
                patEntry
            }

            Spacer()
        }
        .padding()
    }

    private var isBusy: Bool {
        if case .signingIn = app.auth.state { return true }
        return false
    }

    private var patEntry: some View {
        VStack(spacing: 8) {
            SecureField("Personal Access Token", text: $patInput)
                .textFieldStyle(.roundedBorder)
            Text("Needs `notifications` and `repo` scopes.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Sign in with token") {
                Task { await app.auth.signInWithPAT(patInput) }
            }
            .buttonStyle(.bordered)
            .disabled(patInput.isEmpty || isBusy)
        }
        .padding(.horizontal, 24)
        .transition(.opacity)
    }
}
