# sharp-hopper: Windows & VR Productivity Tools

日常の PC 操作や VR（SteamVR / VRChat 等）体験を快適・最適化するために作成された、軽量かつ高機能な自作 Windows ユーティリティ集です。

---

## 📦 収録ツール一覧

### 1. 🥽 [SteamVR Display Optimizer](./steamvr-display-optimizer/)
SteamVR の起動・終了を OS カーネルレベルの同期イベント待機（`WaitForExit`）で検知し、自動的にマルチディスプレイ構成を最適化・復元する超低負荷バックグラウンド常駐ツールです。

- **VR モード時**: メインモニターを低解像度（800×600）に自動縮小し、サブモニターを完全無効化（GPU 描画負荷・VRAM 消費を最小化）。
- **通常モード時**: SteamVR 終了後、瞬時にデュアルモニター通常構成（1920×1080 @ 180Hz / 75Hz）へ完全復旧。
- **CPU 使用率 0.00%**: ゲームプレイ中のフレームレート低下を一切引き起こしません。
- **自己修復機能**: ディスプレイ不整合の自動検知・再適用、二重起動防止、Windows 通知対応。
- 詳細および使い方は [steamvr-display-optimizer/README.md](./steamvr-display-optimizer/README.md) をご覧ください。

---

### 2. 🪟 [Window Resizer](./window-resizer/)
アクティブウィンドウの**限界極小化（1×1 ピクセル・OS リージョンクリッピング）**、**強制フルスクリーン化**、および**元の状態へのスマート復元**を行う、AutoHotkey v2 製の超低負荷常駐ユーティリティです。

- **`Ctrl + Shift + M`**: ウィンドウの枠線を排除し、画面左上に 1×1 ピクセルで極小化。背面のウィンドウへ自動でフォーカスをスマート委譲。
- **`Ctrl + Shift + F`**: アクティブウィンドウを作業領域いっぱいに枠線なし全画面化。
- **`Ctrl + Shift + R`**: LIFO（後入れ先出し）スタックにより、直近に変更したウィンドウを新しい順に 1 つずつ元のサイズ・座標へ完全復元。
- **Per-Monitor DPI v2 対応**: 異なる拡大率のマルチモニター環境でもピクセルずれなく正確に復元。
- **タスクバー非表示（ステルスモード）**・音響フィードバック・外部設定ファイル（`WindowResizer.ini`）による柔軟なカスタマイズに対応。
- 詳細および使い方は [window-resizer/README.md](./window-resizer/README.md) をご覧ください。

---

## 🛠️ 動作要件

- **OS**: Windows 10 / Windows 11 (64-bit)
- **PowerShell**: 5.1 以降（Windows 標準搭載）
- **AutoHotkey**: v2（Window Resizer をソースから改変・ビルドする場合のみ必要。ビルド済み `WindowResizer.exe` はそのまま動作します）

---

## 📄 ライセンス

本リポジトリのコードは [MIT License](./LICENSE) のもとで公開されています。
ご自身の環境に合わせてご自由にお使い・改変いただけます。
