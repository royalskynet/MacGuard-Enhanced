# MacGuard-Enhanced

![macOS](https://img.shields.io/badge/macOS-13.0%2B-brightgreen)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/github/license/royalskynet/MacGuard-Enhanced?color=green)

![MacGuard Featured Image](featured-image.png)

Anti-theft alarm app for macOS. Leave the laptop on the table in a café, and anyone who touches it gets a countdown, a spoken warning and then a very loud alarm — while you get photos and messages on your phone.

MacGuard-Enhanced continues [MacGuard](https://github.com/shenglong209/MacGuard): the same four-state alarm engine, plus remote notifications, photo evidence, a Wi-Fi trigger and an activity log.

**[English](#english) · [繁體中文](#繁體中文)**

---

## English

### Quick install

One line, everything taken from GitHub:

```bash
git clone https://github.com/royalskynet/MacGuard-Enhanced && cd MacGuard-Enhanced && swift build -c release && ./scripts/create-dmg.sh "$(grep -A1 CFBundleShortVersionString Info.plist | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')" && open dist/MacGuard.app
```

Needs macOS 13 Ventura or later and the Xcode Command Line Tools (install with `xcode-select --install` if `swift` is not found). The command clones the repository, builds the release binary with Swift Package Manager, runs `scripts/create-dmg.sh` to assemble and ad-hoc sign `dist/MacGuard.app` (Sparkle framework bundled, `dist/MacGuard-<version>.dmg` written next to it) and launches the app.

Two follow-ups after the first launch:

1. Grant the **Accessibility** permission in Settings → Permissions, otherwise input monitoring cannot start.
2. If you installed from a downloaded DMG instead of building it yourself, clear the quarantine flag once with `xattr -cr /Applications/MacGuard.app`.

Continuous integration (`.github/workflows/release.yml`) uploads `MacGuard-<version>.dmg` to [GitHub Releases](https://github.com/royalskynet/MacGuard-Enhanced/releases) whenever a pull request is merged into `main`, so a pre-built installer may already be waiting there.

### Features

**Detection and alarm**

- Menu bar app (SwiftUI) whose shield icon always shows the current state: idle, armed, triggered or alarming
- Input monitoring for keyboard, mouse and trackpad through a `CGEventTap`
- Lid-close alarm (uses `pmset disablesleep`, asks for an admin password) and power-cord disconnect detection
- Optional Wi-Fi disconnect trigger for when someone cuts the network
- Countdown of immediately, 3, 5, 10, 15 or 30 seconds behind a full-screen overlay

**Proximity (automatic arm and disarm)**

- Up to 10 trusted Bluetooth devices — BLE and Classic, Apple and non-Apple alike
- Auto-disarm when a trusted device comes back into range; auto-arm after every device has left, with a configurable grace period
- Detection distance presets Close / Medium / Far, or a custom signal-strength threshold

**Making noise**

- Alarm audio is forced to the Mac's built-in speakers, and the system volume is re-enforced every 0.3 seconds so it cannot be muted or turned down during the alarm
- 14 macOS system sounds, the bundled "Don't Touch My Mac", or any custom audio file, with a volume slider and preview button
- A spoken warning loop during the countdown so bystanders know the machine is protected
- Optional screen lock when arming, plus an immediate lock the moment a trigger fires

**Evidence and notifications**

- Camera keeps taking photos while the alarm is active (every 2, 5, 10 or 30 seconds), with an optional pre-alarm snapshot; when there is no camera or permission is denied it falls back to a screen capture
- Telegram bot notifications with an on-disk retry queue: failed sends are retried with back-off after the network returns, the bot token lives in the Keychain and only the chat ID is stored in preferences
- iMessage as a backup channel — off, backup only (when Telegram gives up) or always parallel
- Activity log with filtering, covering every arm, trigger, notification and disarm event

**Everyday conveniences**

- Touch ID plus a 4–8 digit PIN kept in the Keychain to disarm
- Launch at Login toggle and a Sparkle update check under Settings → About

### Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (only needed to build from source)
- Accessibility permission for input monitoring
- Bluetooth for proximity detection (optional)
- Camera permission for photo evidence, Messages Automation permission for the iMessage backup (both optional)

### Usage

1. **Grant permissions** — open Settings from the menu bar, press *Grant* next to Accessibility and enable MacGuard in System Settings → Privacy & Security → Accessibility.
2. **Configure trusted devices** (optional) — Settings → Trusted Devices → *Manage Devices*, add up to 10 Bluetooth devices, pick a detection distance, and switch on *Auto-arm when devices leave* if you want the alarm to arm itself once you walk away.
3. **Set a backup PIN** — Settings → Security → *Set PIN*, 4 to 8 digits.
4. **Choose behaviour** — lock screen when armed, countdown length, lid-close alarm (admin password required), alarm sound, volume and preview, and Launch at Login.
5. **Set up notifications** (optional) — Settings → Notifications: enter the Telegram chat ID and bot token (saved to the Keychain), then press *Send Telegram Test*; add an iMessage recipient and pick *Off*, *Backup only* or *Always parallel*. Under *Trigger & Camera* you can enable the Wi-Fi trigger, the pre-alarm snapshot, the instant screen lock, the spoken warning and the capture interval.
6. **Arm it** — *Arm MacGuard* from the menu bar. Any keyboard, mouse or trackpad activity starts the countdown; the alarm then plays at full volume and pushes photos to your phone.
7. **Disarm** — Touch ID, the PIN, or simply walking back with a trusted Bluetooth device nearby.

### How it works

```
┌─────────┐
│  IDLE   │  ← Disarmed, not monitoring
└────┬────┘
     │ arm
     ▼
┌─────────┐
│  ARMED  │  ← Monitoring input, lid, power, Wi-Fi, Bluetooth
└────┬────┘
     │ input detected
     ▼
┌─────────┐
│TRIGGERED│  ← Countdown, spoken warning, instant screen lock
└────┬────┘
     │ timeout
     ▼
┌─────────┐
│ALARMING │  ← Loud alarm, photos, Telegram / iMessage push
└─────────┘
```

### Project structure

```
MacGuard-Enhanced/
├── MacGuardApp.swift                 # Menu bar app entry point
├── Managers/
│   ├── AlarmStateManager.swift       # State machine (idle/armed/triggered/alarming)
│   ├── InputMonitor.swift            # CGEventTap keyboard/mouse/trackpad
│   ├── SleepMonitor.swift            # Lid close detection (IOKit)
│   ├── PowerMonitor.swift            # Power cord disconnect
│   ├── WiFiMonitor.swift             # Wi-Fi drop while armed
│   ├── BluetoothProximityManager.swift  # RSSI proximity, up to 10 devices
│   ├── AuthManager.swift             # Touch ID + Keychain PIN
│   ├── AlarmAudioManager.swift       # Built-in speaker forcing + anti-mute
│   ├── CameraCaptureManager.swift    # Evidence photos, screen-capture fallback
│   ├── SpeechWarner.swift            # Spoken countdown warning
│   ├── ScreenLockManager.swift       # Login session lock (CGSession -suspend)
│   ├── NotificationRouter.swift      # Telegram / iMessage routing
│   ├── TelegramNotifier.swift        # Bot API + on-disk retry queue
│   ├── iMessageNotifier.swift        # Messages backup via osascript
│   ├── ActivityLogManager.swift      # Event log
│   └── UpdateManager.swift           # Sparkle auto-update
├── Views/
│   ├── MenuBarView.swift             # Menu bar dropdown
│   ├── SettingsView.swift            # Settings window (permissions … about)
│   ├── CountdownOverlayView.swift    # Full-screen countdown overlay
│   ├── DeviceScannerView.swift       # Bluetooth scanner
│   ├── TrustedDevicesConfigView.swift  # Trusted device management
│   ├── PINEntryView.swift            # PIN pad
│   └── ActivityLogView.swift         # Filterable event log
├── Models/
│   ├── AlarmState.swift
│   ├── TrustedDevice.swift
│   ├── ActivityLog.swift
│   ├── PendingNotification.swift
│   └── AppSettings.swift             # User preferences
├── Theme/                            # Glass-morphism UI components
├── Utilities/                        # Notification self-test, resource bundle
├── Resources/                        # Icons and bundled alarm sounds
├── scripts/                          # DMG packaging and signing helpers
├── docs/                             # Architecture, deployment, checklists
└── .github/workflows/                # Release pipeline
```

### Permissions

| Permission | Purpose |
|------------|---------|
| Accessibility | Global input monitoring via `CGEventTap` |
| Bluetooth | Trusted device proximity detection |
| Administrator | Lid-close alarm (`pmset disablesleep`) |
| Camera | Intruder photo evidence (falls back to screen capture) |
| Automation (Messages) | iMessage backup channel through `osascript` |

### Documentation

More detail lives in the [`docs/`](docs/) directory:

- **[Project Overview & PDR](docs/project-overview-pdr.md)** — product vision, features, requirements
- **[Codebase Summary](docs/codebase-summary.md)** — technical overview, file structure, dependencies
- **[Code Standards](docs/code-standards.md)** — Swift patterns and naming conventions
- **[System Architecture](docs/system-architecture.md)** — state machine, data flow, component design
- **[Project Roadmap](docs/project-roadmap.md)** — completed milestones and known issues
- **[Deployment Guide](docs/deployment-guide.md)** — build, packaging, release process, CI
- **[MacBook Acceptance Checklist](docs/macbook-acceptance-checklist.md)** — what can only be verified on real hardware

### Known limitations

- Holding the power button forces a shutdown that no user-space app can stop. The realistic defence is evidence-first: photos and notifications are pushed during the countdown, before power is lost. Pair the app with FileVault and Find My.
- A closed lid makes camera shots black; only the frame captured the instant the lid shuts is useful, and it still proves when it happened.
- iMessage cannot bypass Do Not Disturb, needs Messages signed in and a one-time Automation approval, so it is a backup rather than the primary channel.
- The lid-close alarm keeps the Mac awake while armed, which is handy when going out but wasteful on a desk — leave it off at home.
- Bluetooth proximity depends on radio conditions; adjust the detection distance if you see false arm or disarm events.

### Built With

This project was developed with the assistance of:

- **[Claude Code](https://claude.ai/code)** — Anthropic's AI-powered coding assistant
- **[ClaudeKit](https://claudekit.cc/?ref=BPLLTRW2)** — Skills and workflows for Claude Code

### License

MIT — see [LICENSE](LICENSE). Copyright retained by shenglong209 (MacGuard) and royalskynet (MacGuard Enhanced).

### Contributing

Pull requests are welcome. For major changes, please open an issue first.

---

## 繁體中文

### 快速安裝

一行指令完成，全部從 GitHub 取得：

```bash
git clone https://github.com/royalskynet/MacGuard-Enhanced && cd MacGuard-Enhanced && swift build -c release && ./scripts/create-dmg.sh "$(grep -A1 CFBundleShortVersionString Info.plist | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')" && open dist/MacGuard.app
```

需要 macOS 13 Ventura 以上，以及 Xcode Command Line Tools（找不到 `swift` 時先執行 `xcode-select --install`）。這行指令會複製（clone）整個專案、用 Swift Package Manager 建置 release 版執行檔、執行 `scripts/create-dmg.sh` 組裝並以 ad-hoc 方式簽署 `dist/MacGuard.app`（內含 Sparkle 框架，同時產出 `dist/MacGuard-<版本>.dmg`），最後直接啟動程式。

第一次啟動後還有兩件事：

1. 到「設定 → 權限」授予**輔助使用（Accessibility）**權限，否則無法監控鍵盤與滑鼠輸入。
2. 如果你不是自己建置、而是下載 DMG 安裝，先執行一次 `xattr -cr /Applications/MacGuard.app` 清除 quarantine 限制。

CI（`.github/workflows/release.yml`）會在 pull request 合併進 `main` 時，把 `MacGuard-<版本>.dmg` 上傳到 [GitHub Releases](https://github.com/royalskynet/MacGuard-Enhanced/releases)，所以那裡可能已經有現成的安裝檔。

### 功能特色

**偵測與警報**

- 選單列程式（SwiftUI），盾牌圖示會即時反映目前狀態：待機、布防、觸發、警報中
- 以 `CGEventTap` 監控鍵盤、滑鼠與觸控板輸入
- 闔蓋警報（使用 `pmset disablesleep`，需管理員密碼）與電源線拔除偵測
- 可選的 Wi-Fi 斷線觸發，網路被切斷也算數
- 倒數可設為立即、3、5、10、15 或 30 秒，搭配全螢幕遮罩

**藍牙近距離（自動布防／解除）**

- 最多 10 可信任藍牙裝置，支援 BLE 與傳統藍牙，Apple 與非 Apple 裝置皆可
- 信任裝置回到附近即自動解除；全部離開後自動布防，並可設定緩衝時間
- 偵測距離內建近／中／遠三段，也可自行指定訊號強度門檻

**把聲音開到最大**

- 警報音強制輸出到內建喇叭，警報期間每 0.3 秒重新强制音量，靜音與調小音量都會被擋下
- 內建 14 種 macOS 系統音效、隨附的「Don't Touch My Mac」，或自訂音檔，附音量滑桿與試聽
- 倒數期間朗讀警告語，讓旁觀者也知道這台電腦有人顧
- 可選擇布防時鎖定螢幕，觸發瞬間更立刻上鎖

**留證與通知**

- 警報期間相機持續拍照（每 2、5、10 或 30 秒一張），可另開「布防前快照」；沒有相機或權限被拒時自動改為螢幕截圖
- Telegram 機器人推播搭配磁碟佇列：斷網時訊息先排队，網路恢復後自動重試；bot token 存在鑰匙圈，偏好設定裡只留下 chat ID
- iMessage 作為備援通道：關閉、只在 Telegram 放棄時補送，或永遠雙通道同時送
- 活動紀錄可篩選，完整記錄布防、觸發、推播與解除事件

**日常便利**

- Touch ID 加上存於鑰匙圈的 4–8 位數 PIN 解除布防
- 開機自動啟動開關，以及「設定 → 關於」中的更新檢查（Sparkle）

### 系統需求

- macOS 13 Ventura 以上
- 從原始碼建置時需安裝 Xcode Command Line Tools
- 輸入監控需授予輔助使用權限
- 近距離偵測需藍牙（非必要）
- 拍照需相機權限、iMessage 備援需「自動操作（Automation）」權限（兩者皆非必要）

### 使用方式

1. **授予權限** — 從選單列開啟設定，點「輔助使用」旁的*授予*，並在「系統設定 → 隱私權與安全性 → 輅助使用」啟用 MacGuard。
2. **設定信任裝置**（建議）— 設定 → 信任裝置 → *管理裝置*，最多加入 10 個藍牙裝置，選擇偵測距離；若希望離開後自動布防，開啟*裝置離開時自動布防*。
3. **設定備用 PIN** — 設定 → 安全性 → *設定 PIN*，4 到 8 位數。
4. **調整行為** — 布防時鎖螢幕、倒數秒數、闔蓋警報（需管理員密碼）、警報音效與音量試聽、開機自動啟動。
5. **設定通知**（建議）— 設定 → 通知：填入 Telegram chat ID 與 bot token（token 存入鑰匙圈），按*傳送 Telegram 測試*；填 iMessage 收件人並選擇*關閉*、*只作備援*或*永遠同時傳送*。同一區塊的「觸發與相機」可啟用 Wi-Fi 觸發、布防前快照、觸發立即鎖螢幕、倒數語音警告與拍照間隔。
6. **布防** — 在選單列點 *Arm MacGuard*。只要碰一下鍵盤、滑鼠或觸控板就進入倒數，接著警報全音量響起，照片與訊息推到你的手機。
7. **解除** — 用 Touch ID、輸入 PIN，或帶著信任裝置走回附近自動解除。

### 運作原理

```
┌─────────┐
│  IDLE   │  ← 待機：未布防、不監控
└────┬────┘
     │ 布防
     ▼
┌─────────┐
│  ARMED  │  ← 布防：監控輸入、闔蓋、電源、Wi-Fi、藍牙
└────┬────┘
     │ 偵測到異動
     ▼
┌─────────┐
│TRIGGERED│  ← 觸發：倒數、語音警告、立即鎖螢幕
└────┬────┘
     │ 倒數結束
     ▼
┌─────────┐
│ALARMING │  ← 警報：大聲警報、拍照、Telegram / iMessage 推播
└─────────┘
```

### 專案結構

```
MacGuard-Enhanced/
├── MacGuardApp.swift                 # 選單列程式進入點
├── Managers/
│   ├── AlarmStateManager.swift       # 狀態機（待機/布防/觸發/警報）
│   ├── InputMonitor.swift            # CGEventTap 鍵盤滑鼠監控
│   ├── SleepMonitor.swift            # 闔蓋偵測（IOKit）
│   ├── PowerMonitor.swift            # 電源線拔除
│   ├── WiFiMonitor.swift             # 布防中 Wi-Fi 斷線
│   ├── BluetoothProximityManager.swift  # RSSI 近距離偵測，最多 10 裝置
│   ├── AuthManager.swift             # Touch ID 與鑰匙圈 PIN
│   ├── AlarmAudioManager.swift       # 強制內建喇叭 + 反靜音
│   ├── CameraCaptureManager.swift    # 證據拍照，失敗改螢幕截圖
│   ├── SpeechWarner.swift            # 倒數語音警告
│   ├── ScreenLockManager.swift       # 登入階段鎖定（CGSession -suspend）
│   ├── NotificationRouter.swift      # Telegram / iMessage 路由
│   ├── TelegramNotifier.swift        # Bot API 與磁碟重試佇列
│   ├── iMessageNotifier.swift        # 以 osascript 備援推播
│   ├── ActivityLogManager.swift      # 活動紀錄
│   └── UpdateManager.swift           # Sparkle 自動更新
├── Views/
│   ├── MenuBarView.swift             # 選單列下拉選單
│   ├── SettingsView.swift            # 設定視窗（權限…關於）
│   ├── CountdownOverlayView.swift    # 全螢幕倒數遮罩
│   ├── DeviceScannerView.swift       # 藍牙掃描
│   ├── TrustedDevicesConfigView.swift  # 信任裝置管理
│   ├── PINEntryView.swift            # PIN 輸入盤
│   └── ActivityLogView.swift         # 可篩選的活動紀錄
├── Models/
│   ├── AlarmState.swift
│   ├── TrustedDevice.swift
│   ├── ActivityLog.swift
│   ├── PendingNotification.swift
│   └── AppSettings.swift             # 使用者偏好設定
├── Theme/                            # 玻璃質感 UI 元件
├── Utilities/                        # 通知自我測試、資源檔載入
├── Resources/                        # 圖示與隨附警報音
├── scripts/                          # DMG 打包與簽署腳本
├── docs/                             # 架構、部署、驗收文件
└── .github/workflows/                # 發布流程
```

### 權限

| 權限 | 用途 |
|------|------|
| 輔助使用（Accessibility） | 以 `CGEventTap` 全域監控輸入 |
| 藍牙 | 偵測信任裝置的遠近 |
| 管理員 | 闔蓋警報（`pmset disablesleep`） |
| 相機 | 拍下入侵者證據（失敗時改用螢幕截圖） |
| 自動操作（Automation / 訊息） | 以 `osascript` 備援傳送 iMessage |

### 文件

更多細節請見 [`docs/`](docs/) 目錄：

- **[專案總覽與 PDR](docs/project-overview-pdr.md)** — 產品願景、功能與需求
- **[程式碼總覽](docs/codebase-summary.md)** — 技術架構、檔案結構、相依套件
- **[程式碼規範](docs/code-standards.md)** — Swift 寫法與命名慣例
- **[系統架構](docs/system-architecture.md)** — 狀態機、資料流、元件設計
- **[專案路線圖](docs/project-roadmap.md)** — 已完成里程碑與已知問題
- **[部署指南](docs/deployment-guide.md)** — 建置、打包、發布與 CI
- **[MacBook 驗收清單](docs/macbook-acceptance-checklist.md)** — 只能在實機上驗證的項目

### 已知限制

- 長按電源鍵強制關機是任何使用者空間軟體都擋不住的。務實的防線是「先留證再談鎖死」：倒數期間就把照片與通知送出去，再搭配 FileVault 與「尋找」。
- 闔蓋瞬間搶拍的那張才有畫面，之後多半是黑圖，但黑圖仍能證明事發時間。
- iMessage 穿不透勿擾模式、必須登入訊息並授權一次自動操作，因此只當備援不當主管道。
- 闔蓋警報在布防時會禁止睡眠，外出時很好用，放在桌上則很耗電，平常建議關掉。
- 藍牙近距離受環境電波影響，若出現誤布防或誤解除，請調整偵測距離。

### 開發工具

本專案在下列工具協助下完成：

- **[Claude Code](https://claude.ai/code)** — Anthropic 的 AI 程式助理
- **[ClaudeKit](https://claudekit.cc/?ref=BPLLTRW2)** — Claude Code 的技能與工作流程

### 授權

採用 MIT 授權，詳見 [LICENSE](LICENSE)。著作權由 shenglong209（MacGuard）與 royalskynet（MacGuard Enhanced）共同保留。

### 參與貢獻

歡迎送出 pull request。若要大幅改動，請先開 issue 討論。
