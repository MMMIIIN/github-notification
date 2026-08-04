import SwiftUI

/// Sign-in screen. The app authenticates with a GitHub Personal Access Token —
/// no OAuth App, client secret, or backend required.
struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @State private var tokenInput = ""

    private let createTokenURL =
        "https://github.com/settings/tokens/new?scopes=notifications,repo&description=GitHub%20Notifier"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.primary)

            VStack(spacing: 6) {
                Text("GitHub Notifier")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Review requests, comments, and mentions —\nright in your menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in with a GitHub token")
                    .font(.callout)
                    .fontWeight(.medium)

                SecureField("Personal Access Token", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button {
                    app.openInBrowser(createTokenURL)
                } label: {
                    Label("Create a token on GitHub", systemImage: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.link)

                Text("Needs the **notifications** and **repo** scopes (repo grants private-repo access). The token is stored in your macOS Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            if case .signingIn = app.auth.state {
                ProgressView().controlSize(.small)
            }

            if case let .error(message) = app.auth.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: submit) {
                Text("Sign in")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(tokenInput.isEmpty || isBusy)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
    }

    private var isBusy: Bool {
        if case .signingIn = app.auth.state { return true }
        return false
    }

    private func submit() {
        guard !tokenInput.isEmpty, !isBusy else { return }
        Task { await app.auth.signIn(withToken: tokenInput) }
    }
}
