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
- **GitHub sign-in** via OAuth **Device Flow** (no client secret, no backend)
  with a **Personal Access Token** fallback.
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
app locally so Keychain, notifications, and the OAuth browser flow work.

### Requirements
- macOS 14+
- Xcode command line tools / Swift 5.9+ toolchain (`swift --version`)

---

## Authentication

### Option A — Personal Access Token (simplest, no setup)
1. Launch the app, click the menu bar icon.
2. Click **"Sign in another way"**, paste a token.
3. The token needs the **`notifications`** and **`repo`** scopes (the `repo`
   scope is what grants access to *private* repository notifications).
4. The token is stored in your **macOS Keychain**.

Create a token at: GitHub → Settings → Developer settings → Personal access
tokens.

### Option B — OAuth (GitHub Device Flow)
OAuth uses GitHub's **Device Flow**, which needs only the OAuth App's *client id*
(not secret). That means **no backend and nothing secret to distribute** — great
for teams.

**One-time setup (by whoever distributes the app):**
1. Create an OAuth App: GitHub → Settings → Developer settings → **OAuth Apps** →
   *New OAuth App*. Any name/homepage URL is fine; the callback URL is unused by
   Device Flow.
2. On the app's page, **check "Enable Device Flow"**.
3. Copy the **Client ID** and bake it into the build so teammates need nothing:
   set `bundledClientID` in `Sources/GitHubNotifier/Support/AppConfig.swift`.
   *(Alternatively, each person can drop a `~/Library/Application
   Support/GitHubNotifier/config.json` = `{ "clientID": "Iv1.xxxx" }`.)*

**Signing in:** click **"Sign in with GitHub"** → the app copies a short code and
opens `github.com/login/device` → paste the code and click **Authorize**. Done —
no client secret, no backend, no per-teammate setup.

---

## First run

1. Sign in (OAuth or token).
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
| 1 | Install → OAuth (Device Flow) → pick repos → first notifications | `make run`, `LoginView`, `RepoSelectionView`, `NotificationPoller` |
| 2 | Badge + dropdown list + type icons + unread + read-sync | `BadgeRenderer`, `DropdownView`, `NotificationRowView`, read-only poll |
| 3 | New item → system banner → click → browser | `SystemNotificationManager` |
| 4 | Network loss → silent retry → icon warning → auto-recover | `NotificationPoller` backoff + `ConnectionStatus` |
| 5 | PAT fallback sign-in | `LoginView` + `AuthManager.signInWithPAT` |
| 6 | Settings: badge toggle, subscriptions, launch-at-login, logout | `SettingsView`, `LoginItemManager` |

---

## Architecture

```
Sources/GitHubNotifier/
├── App/            main.swift, AppDelegate, AppState, StatusItemController, BadgeRenderer
├── Auth/           AuthManager, OAuthService (GitHub Device Flow)
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
GitHub accounts, App Store distribution, and any auth backend (Device Flow keeps
the app fully client-side).
