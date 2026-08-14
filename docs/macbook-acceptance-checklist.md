# MacGuard-Enhanced · MacBook 驗收 Checklist

本文件的驗收項目無法在無頭（headless）mini 完成，需在實機 MacBook 上由使用者手動執行。每個項目「宣告≠生效」：貼實際輸出/現象才算通過。

配套：[系統架構](system-architecture.md) · [部署指南](deployment-guide.md)

---

## 0. 建置與部署（實機先跑）

```bash
cd /Users/51mini/dev/MacGuard
swift build -c release
./scripts/create-dmg.sh 2.0.8           # 產出 dist/MacGuard.app（ad-hoc 簽名）
xattr -cr dist/MacGuard.app             # 首啟清除 quarantine（本地未公證）
open dist/MacGuard.app
```

> 固定簽名與 TCC：目前以 ad-hoc（`-`）簽名。**重簽名會重置 TCC 授權**（相機／Automation／Accessibility 需重新授權）。若需跨更新保留授權，請讓 `scripts/setup-certificate.sh` 產生正式憑證後再簽。

### 通知參數預置（不入 repo，runtime 讀取）
- **Bot token**：寫入 Keychain。
  `security add-generic-password -s com.shenglong.macguard -a telegramBotToken -w '<TOKEN>'`
- **Chat ID**：`defaults write com.shenglong.macguard telegramChatID 7852197786`
- 亦可直接在 App 內 **Settings → Notifications** 區輸入並點「測試」。

---

## 1. mini 無法覆驗 → 需實機的機器驗收

| # | 項目 | 判定標準（貼輸出/現象） |
|---|---|---|
| 1.1 | **佇列排水淨空** | status 列印 of `~/Library/Application Support/MacGuard/queue/`：塞錯 token 觸發 → 佇列累積>0；改回正確 token → **佇列檔數歸 0**（補推成功） |
| 1.2 | **狀態機全轉移 log** | 依 AlarmStateManager 觸發途徑（信任裝置 BT 離開／WiFi 斷線／RSSI 出界／Settings 測試鈕）進入 trigger → 鎖屏被呼叫(log) → 語音 → 倒數歸零 → alarming(警笛+紅閃) → PIN 解除。**各階段推播實際到達手機** |
| 1.3 | **反靜音** | alarming 中 `osascript -e 'set volume output volume 0'` → **1 秒內被強制恢復**（`osascript -e 'get volume settings'` 顯示非 0） |
| 1.4 | **相機 TCC 首授** | Settings 測試拍照鈕 → 系統跳出相機授權 → 允許 → 照片存入 captures/ 且可於手機收到 |
| 1.5 | **iMessage 備援** | Settings 將 `iMessage` 模式設 fallback → 斷開 Telegram 或停用 → 觸發後手機收到 iMessage 文字(+附件) |
| 1.6 | **WiFi 斷網觸發** | 武裝後關 Wi-Fi → Activity log 出現 `.wifi` 事件 → 若為觸發源則走 alarming 流程 |

## 2. 實體裝置手動驗（依 plan §92-97）

| # | 劇本 | 預期 |
|---|---|---|
| 2.1 | 相機授權後 alarming 實際連拍 | 手機收到多張證據照片 |
| 2.2 | Touch ID 解除；觸發瞬間即鎖屏 | 拔除信任裝置後 ARMED，TRIGGERED 瞬間螢幕鎖住、桌面不可操作 |
| 2.3 | 闔蓋觸發 + `pmset disablesleep` | 闔蓋仍響警報（不致副睡眠）；mini 無電池，**AC 狀態不受影響** |
| 2.4 | RSSI 地實地調參 | iPhone+Watch 離開/回歸的 arm/disarm 時間與誤報率記錄 |
| 2.5 | 端到端劇本 | 武裝→離開→「賊」動鍵盤→鎖屏+語音→警笛紅閃→手機收照片→Touch ID 解除，全程貼 log |

## 3. 誠實風險與物理極限（交付前須知）

- **長按電源鍵強制關機無解**（任何用戶態軟體皆然）。緩解鏈：TRIGGERED 期**先拍先推**（關機前照片已推出去）→ FileVault → Find My 關機仍可定位。本工具定位＝**嚇阻＋留證**，非鎖死。
- **闔蓋拍全黑**：闔蓋瞬間搶拍一張，之後黑圖仍證明事發時間。
- `swift run` 裸執行檔**拿不到 TCC**：相機／Automation／Accessibility 一律用打包 `.app` + 固定簽名測試；重簽名會失效授權。
- `SACLockScreenImmediate` 為**私有 API**：macOS 升級可能失效，已留 `CGSession -suspend` fallback，啟動時自檢可用性。
- **iMessage 限制**：無法穿透 DND、Messages 必須登入、Automation 需一次授權 → 只當備援不當主管道。
- `disablesleep` 副作用：插電完全不休眠，**建議僅外出情境開啟**。
- **Telegram 斷網**：佇列落盤補推；「賊關 Wi-Fi」本身即觸發源。

## 4. 發布狀態

- 掃描結果：工作樹 + `git log --all -p` 對 `bot[0-9]+:|api\.telegram\.org/bot[0-9]+` 均 **0 命中**。
- Public repo：`https://github.com/royalskynet/MacGuard-Enhanced`
- 授權：MIT（補 LICENSE 檔，保留 shenglong209 attribution + 本 fork copyright）。
- 注意：`dist/`、`captures/`、`queue/`、`.env`、`*.p12` 均已 `.gitignore`，不入庫。