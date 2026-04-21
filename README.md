# 懶人剪輯 (LazyEditor)

專為 YouTuber / Vlogger 設計的 macOS 影片快剪工具。匯入影片、快速剪輯、一鍵匯出，省去繁瑣的專業剪輯流程。

## 功能

- **時間軸剪輯** — 拖曳排序、裁切分段、Delete / Backspace 快速刪除選取片段
- **靜音自動偵測** — 一鍵移除靜音段落，加速剪輯流程
- **音頻處理**
  - 5 頻段 EQ 等化器（即時預覽）
  - 10 種場景預設（Vlog 戶外/室內、Podcast、廣播人聲等）
  - 去雜音（高通 + 陷波濾波）
  - 音量平衡（動態壓縮）
  - 整體音量調整（即時預覽）
- **影片濾鏡** — 多種風格濾鏡，可調整強度
- **字卡系統** — 可自訂文字、字型、顏色、背景、動畫效果（淡入淡出），支援音效
- **雙語字幕** — 支援中/英字幕軌，可匯入 SRT
- **代理檔預覽** — 自動產生低解析度代理檔，流暢預覽
- **專案儲存/自動儲存** — `.lazyed` 專案格式，支援自動儲存
- **影片匯出** — 匯出 MP4（含濾鏡、字幕、字卡），另可獨立匯出音訊（M4A / WAV / MP3）

## 系統需求

- macOS 15.0 或以上
- Xcode 16.0 或以上（編譯用）

## 安裝

### 下載 DMG

前往 [GitHub Actions](https://github.com/scorpioliu0953/LazyEditor/actions) 頁面，點選最新的 Build DMG workflow run，下載 `LazyEditor-DMG` artifact。

### 從原始碼編譯

```bash
git clone https://github.com/scorpioliu0953/LazyEditor.git
cd LazyEditor/懶人剪輯
open 懶人剪輯.xcodeproj
```

在 Xcode 中選擇目標裝置，按 `Cmd+R` 執行。

## 技術架構

| 層級 | 技術 |
|------|------|
| UI | SwiftUI + @Observable |
| 播放 | AVPlayer + AVComposition |
| 即時 EQ | MTAudioProcessingTap + Biquad IIR |
| 離線音頻處理 | AVAudioEngine（EQ / 去雜音 / 音量平衡） |
| 影片匯出 | AVAssetReader + AVAssetWriter（逐幀 CIFilter 渲染） |
| 音訊匯出 | AVAssetExportSession |
| 濾鏡 | CIFilter + CIContext |
| 字幕渲染 | Core Graphics |
| 字卡渲染 | Core Graphics + Core Image |

## 授權

MIT License
