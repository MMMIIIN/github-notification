import SwiftUI

/// Top-level popover content. Routes between login, mandatory onboarding, and
/// the notifications list based on `AppState.screen`.
struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            switch app.screen {
            case .login:
                LoginView()
            case .onboarding:
                RepoSelectionView(mode: .onboarding)
            case .notifications:
                if showingSettings {
                    SettingsView(isPresented: $showingSettings)
                } else {
                    DropdownView(showingSettings: $showingSettings)
                }
            }
        }
        .frame(width: 380, height: 480)
        .background(.background)
    }
}
