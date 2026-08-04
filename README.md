# GitHub Notifier

A lightweight **macOS menu bar app** that surfaces the GitHub notifications that
matter to you — **review requests, review comments, and issue mentions** — from
the repositories you choose, including private ones. No more digging through
email.

- **Menu bar icon** (`NSStatusItem`) with an unread **number badge** or **dot**
  (your choice), and a warning state when something's wrong.
- **Dropdown panel** listing recent notifications with per-type icons/colors and
  unread emphasis. Click an item to open it in your browser.
- **System notification banners** for new items; click a banner to jump straight
  to the PR/issue/comment.
- **GitHub sign-in** with a **Personal Access Token** — no OAuth App, client
  secret, or backend.
- **Read-only**: it never changes anything on GitHub. Mark things read on
  github.com and it reflects on the next poll.
- Polls the GitHub Notifications API roughly every **60 seconds**, respecting the
  server's `X-Poll-Interval` and using `ETag` conditional requests to stay light.

Built with Swift / SwiftUI, targets **macOS 14 (Sonoma)+**.

---

## Install (git clone + one command)

```bash
git clone <this-repo-url> github_noti
cd github_noti
make run        # builds, assembles GitHubNotifier.app, and launches it
```

That's it — a menu bar bell icon appears. To keep it around:

```bash
make install    # copies GitHubNotifier.app to /Applications
```

No App Store, code signing, or notarization required. The build ad-hoc signs the
app locally so the Keychain and notifications work.

### Requirements
- macOS 14+
- Xcode command line tools / Swift 5.9+ toolchain (`swift --version`)

---

## Authentication — Personal Access Token

The app signs in with a **GitHub Personal Access Token**. No OAuth App, client
secret, or backend — each person just pastes their own token. Every teammate does
the same one-minute step; nothing is shared or hosted.

1. Create a token (classic): GitHub → Settings → Developer settings →
   **Personal access tokens (classic)** → *Generate new token*. The app's
   **"Create a token on GitHub"** link opens this page with the scopes
   preselected.
   - Scopes: **`notifications`** and **`repo`** (the `repo` scope grants access to
     *private* repository notifications).
   - Tip: use *classic* tokens — fine-grained tokens have limited notifications
     access. Set "No expiration" if you'd rather not regenerate later.
2. Launch the app, click the menu bar icon, paste the token, **Sign in**.
3. The token is stored in your **macOS Keychain** (never written to disk in the
   clear, never leaves your machine).

---

## First run

1. Sign in with your token.
2. **Choose repositories to watch** — this onboarding step is required; you only
   get notifications for the repos you pick.
3. Notifications appear in the dropdown within ~60s, and new ones raise a banner.

## Settings

Click the gear in the dropdown:
- **Menu bar badge**: unread count ↔ dot.
- **Subscribed repositories**: add/remove at any time.
- **Launch at login**: toggle (uses `SMAppService`).
- **Sign out**: clears the token from the Keychain.

---

## How it maps to the acceptance scenarios

| # | Scenario | Where |
|---|----------|-------|
| 1 | Install → token sign-in → pick repos → first notifications | `make run`, `LoginView`, `RepoSelectionView`, `NotificationPoller` |
| 2 | Badge + dropdown list + type icons + unread + read-sync | `BadgeRenderer`, `DropdownView`, `NotificationRowView`, read-only poll |
| 3 | New item → system banner → click → browser | `SystemNotificationManager` |
| 4 | Network loss → silent retry → icon warning → auto-recover | `NotificationPoller` backoff + `ConnectionStatus` |
| 5 | Token sign-in + validation + Keychain storage | `LoginView` + `AuthManager.signIn(withToken:)` |
| 6 | Settings: badge toggle, subscriptions, launch-at-login, logout | `SettingsView`, `LoginItemManager` |

---

## Architecture

```
Sources/GitHubNotifier/
├── App/            main.swift, AppDelegate, AppState, StatusItemController, BadgeRenderer
├── Auth/           AuthManager (Personal Access Token)
├── GitHub/         GitHubAPIClient (GET-only), NotificationPoller (~60s loop)
├── Models/         GitHubNotification + enums
├── Notifications/  SystemNotificationManager (UserNotifications)
├── Support/        KeychainStore, SettingsStore, LoginItemManager, AppConfig
└── UI/             RootView, LoginView, RepoSelectionView, DropdownView,
                    NotificationRowView, SettingsView
```

- **Storage**: `UserDefaults` (prefs, subscribed repos, ETag) + **Keychain**
  (token). No database.
- **Polling**: conditional `GET /notifications` (`If-None-Match` / `ETag`),
  filtered to your subscribed repos and the three notification types.

## Make targets

| Target | Does |
|--------|------|
| `make run` | build + assemble `.app` + launch |
| `make build` | compile the release binary |
| `make bundle` | assemble the ad-hoc-signed `.app` |
| `make install` | copy to `/Applications` |
| `make clean` | remove build artifacts |

## Out of scope (MVP)

CI/merge/release notifications, marking read from the app (write/PATCH), multiple
GitHub accounts, App Store distribution, and any auth backend (token auth keeps
the app fully client-side).
