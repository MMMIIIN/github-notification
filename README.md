# GitHub Notifier

GitHub Notifier는 중요한 GitHub 알림을 메뉴 막대에서 바로 확인할 수 있는
가벼운 macOS 앱입니다. 토큰을 연결하면 GitHub가 내 계정에 생성한
**리뷰 요청, 리뷰 댓글, 멘션**을 자동으로 모아서 보여주며 비공개 저장소도 지원합니다.

알림은 저장소별로 묶여 표시됩니다. 제목뿐 아니라 댓글·PR 본문 미리보기와
작성자도 함께 확인할 수 있고, 항목을 누르면 브라우저에서 해당 PR의 리뷰
화면이나 정확한 댓글 위치로 이동합니다.

## 주요 기능

- 메뉴 막대에서 읽지 않은 알림 개수 또는 점 표시
- 계정 전체의 리뷰 요청, 리뷰 댓글, 멘션 자동 수집
- 저장소별 알림 그룹 및 읽지 않은 알림 수 표시
- 댓글·PR 내용 미리보기와 작성자 표시
- 알림 클릭 시 PR의 Files changed 화면 또는 정확한 댓글 위치로 이동
- 새 알림 도착 시 macOS 시스템 알림 표시
- 읽은 알림을 앱 목록에서 개별 삭제
- 네트워크 오류 시 자동 재시도 및 메뉴 막대 경고 표시
- 로그인 시 자동 실행 설정
- Personal Access Token을 macOS Keychain에 안전하게 저장

GitHub Notifier는 알림을 열거나 읽음 버튼을 누를 때 해당 GitHub 알림 thread를
읽음으로 표시합니다. PR, 이슈, 댓글 등의 콘텐츠는 수정하지 않습니다. 앱에서
읽은 알림을 삭제해도 GitHub의 원본 알림은 삭제되지 않고, 이 Mac의 목록에서만
숨겨집니다.

## 요구 사항

- macOS 14 Sonoma 이상
- Xcode Command Line Tools
- Swift 5.9 이상

Swift 설치 여부는 다음 명령으로 확인할 수 있습니다.

```bash
swift --version
```

## 설치 및 실행

저장소를 내려받고 `make run`을 실행합니다.

```bash
git clone https://github.com/MMMIIIN/github-notification.git
cd github-notification
make run
```

빌드가 끝나면 메뉴 막대에 종 모양 아이콘이 나타납니다. 앱을
`/Applications`에 설치하려면 다음 명령을 사용합니다.

```bash
make install
```

App Store 배포 앱이 아니므로 로컬에서 ad-hoc 서명합니다. 이 서명은 Keychain과
macOS 알림 기능을 안정적으로 사용하기 위한 것입니다.

## GitHub 토큰 설정

앱은 별도 서버나 OAuth App 없이 GitHub Personal Access Token으로 로그인합니다.
토큰은 GitHub API 요청에만 사용되며 macOS Keychain에 저장됩니다.

1. GitHub의 **Settings → Developer settings → Personal access tokens → Tokens
   (classic)**으로 이동합니다.
2. `Generate new token (classic)`을 선택합니다.
3. 다음 scope를 선택합니다.
   - `notifications`: 알림 조회
   - `repo`: 비공개 저장소와 해당 알림 조회
4. 생성된 토큰을 복사합니다. 토큰은 GitHub에서 다시 표시되지 않으므로 생성 직후
   저장해야 합니다.
5. 메뉴 막대의 GitHub Notifier를 열고 토큰을 붙여 넣은 뒤 **Sign in**을 누릅니다.

앱 로그인 화면의 **Create a token on GitHub** 링크를 사용하면 필요한 scope가
미리 선택된 토큰 생성 페이지를 열 수 있습니다. 알림 API 지원 범위 때문에
fine-grained token보다 classic token 사용을 권장합니다.

## 사용법

### 처음 시작하기

1. Personal Access Token으로 로그인합니다.
2. 초기 조회가 끝나면 메뉴 막대 아이콘과 드롭다운에 알림이 표시됩니다.

앱은 약 60초마다 GitHub Notifications API를 확인합니다. GitHub가 제공하는
`X-Poll-Interval`과 `ETag`를 사용하므로 변경이 없을 때는 응답 데이터를 다시
받지 않습니다.

### 알림 확인하기

- 메뉴 막대의 종 아이콘을 클릭하면 알림 목록이 열립니다.
- 알림은 저장소별로 묶이고 각 그룹 안에서는 최신순으로 정렬됩니다.
- 각 항목에서 알림 유형, 제목, 내용 미리보기, 작성자, 시간을 확인할 수 있습니다.
- 리뷰 요청을 누르면 PR의 **Files changed** 화면이 열립니다.
- 댓글이나 멘션을 누르면 가능한 경우 해당 댓글 앵커로 바로 이동합니다.
- 상단 새로고침 버튼을 누르면 다음 주기를 기다리지 않고 즉시 다시 조회합니다.

정확한 댓글 링크와 미리보기는 최근 알림부터 백그라운드에서 미리 조회하여
메모리에 캐시합니다. 아직 준비되지 않은 항목을 누르면 행에 로딩 표시가 나타난
뒤 브라우저가 열립니다. 비공개 저장소의 본문과 작성자는 디스크에 저장하지
않습니다.

### 읽은 알림 삭제하기

알림을 클릭하면 브라우저를 여는 동시에 GitHub에서도 읽음으로 표시됩니다.
브라우저를 열지 않고 읽음 처리만 하려면 unread 항목에 마우스를 올린 뒤
봉투 열기 버튼을 누릅니다. 읽은 항목에는 휴지통 버튼이 나타납니다.

휴지통 버튼은 해당 항목을 이 Mac의 GitHub Notifier 목록에서만 숨깁니다. GitHub
서버의 알림이나 PR·이슈·댓글은 변경하지 않습니다. 읽지 않은 알림은 실수로
숨기지 않도록 삭제할 수 없습니다.

### 시스템 알림

앱 실행 후 새 읽지 않은 알림이 도착하면 macOS 배너와 소리로 알려줍니다. 배너를
클릭해도 앱 목록에서 클릭한 것과 동일하게 정확한 리뷰·댓글 위치를 찾습니다.

### 설정

드롭다운 아래쪽의 **Settings**에서 다음 항목을 변경할 수 있습니다.

- **Menu bar badge**: 읽지 않은 개수 또는 점
- **Launch at login**: macOS 로그인 시 자동 실행
- **Sign out**: Keychain 토큰과 로컬 알림 캐시 초기화

## 업데이트

설치된 앱을 최신 코드로 업데이트하고 다시 실행합니다.

```bash
make update
```

이 명령은 `git pull --ff-only` 후 release 앱을 다시 빌드하여
`/Applications/GitHubNotifier.app`에 설치합니다.

## 개발

프로젝트는 Swift Package Manager 기반이며 외부 패키지 의존성이 없습니다.

```bash
swift build       # debug 빌드
swift test        # 단위 테스트
make run          # release 앱 번들 빌드 및 실행
```

### 프로젝트 구조

```text
Sources/GitHubNotifier/
├── App/            앱 생명주기, 상태, 메뉴 막대 아이콘
├── Auth/           PAT 인증
├── GitHub/         REST API 클라이언트와 알림 폴러
├── Models/         알림 및 설정 모델
├── Notifications/  macOS 시스템 알림
├── Support/        Keychain, UserDefaults, 로그인 항목
└── UI/             로그인, 알림 목록, 설정 화면
```

로컬 데이터는 다음과 같이 나뉩니다.

- **Keychain**: GitHub Personal Access Token
- **UserDefaults**: 배지 설정, ETag, 로컬에서 숨긴 알림 ID
- **메모리 전용**: 댓글·PR 미리보기, 작성자, 해석된 딥링크

### Make 명령

| 명령 | 설명 |
|---|---|
| `make build` | release 실행 파일 빌드 |
| `make bundle` | `.build/GitHubNotifier.app` 생성 및 ad-hoc 서명 |
| `make run` | 앱 번들을 빌드하고 기존 프로세스를 종료한 뒤 실행 |
| `make install` | 앱을 `/Applications`에 설치하고 실행 |
| `make update` | 원격 변경을 받은 뒤 다시 설치 |
| `make clean` | SwiftPM 및 앱 번들 빌드 결과 삭제 |

## 현재 지원하지 않는 기능

- CI, merge, release 등 모든 GitHub 알림 유형 표시
- 여러 GitHub 계정 동시 사용
- App Store 배포 및 notarization
- PR, 이슈, 댓글 등 GitHub 콘텐츠를 수정하는 기능
