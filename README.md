# vrc-tools: Windows & VR Productivity Tools

日常の PC 操作や VR（SteamVR / VRChat 等）体験を快適・最適化するために作成された、軽量かつ高機能な自作 Windows ユーティリティ＆設定集です。

---

## 📦 収録ツール・設定一覧

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

### 3. 🔄 [VRChat 設定レジストリ管理ツール](./vrc-registry-tool/)
VRChat の設定レジストリ（`HKCU\Software\VRChat\vrchat`）を `.reg` 形式で素早くエクスポート（バックアップ）およびインポート（復元）するための PowerShell スクリプト集です。

- **`VRC設定エクスポート.ps1`**:
  - `reg export` コマンドにより、現在の設定をダウンロードフォルダ（`%USERPROFILE%\Downloads\vrchat-settings.reg`）へ即座に書き出し。
- **`VRC設定インポート.ps1`**:
  - 移行先 PC の既存設定を自動バックアップ（`vrchat-settings-backup.reg`）した上で、設定を安全にレジストリへ取り込み。
- 詳細および使い方は [vrc-registry-tool/README.md](./vrc-registry-tool/README.md) をご覧ください。

---

### 4. ⚙️ [VRChat ＆ 周辺デバイス各種設定・プリセット集](./vrc-settings/)
VRChat 環境の最適化、周辺コントローラー、モーショントラッキング用の設定・プロファイル集です。

- **`config.json`**:
  - VRChat 本体のキャッシュ保存先や写真出力先を別ドライブ（`E:\windows\VRC-Cache`）へリダイレクトし、C ドライブの枯渇を防ぐ最適化設定。
- **`repositories.txt`**:
  - lilToon, Modular Avatar, AAO, LLC 等、アバター制作・改変で必須となる主要 VPM リポジトリ URL 一覧。
- **`rebo.rebo_setting`**:
  - ReBones（AI モーショントラッキング / VMC 連携 / IK 補正）のプロファイル設定。
- **AddCon コントローラー設定 (`VRChat.json`, `汎用.json`, `addcon_settings_20260902.json`)**:
  - 左手・右手デバイス「AddCon」向けの OSC 操作（移動・ジャンプ・マイク）、カメラ制御（ズーム・露出・自撮り・フライング）、デスクトップ操作、アバターパラメータ（LightLimitChanger, PCSS, 視線高さ）割り当てプリセット。
- 詳細および各設定の反映方法は [vrc-settings/README.md](./vrc-settings/README.md) をご覧ください。

---

## 🛠️ 動作要件

- **OS**: Windows 10 / Windows 11 (64-bit)
- **PowerShell**: 5.1 以降（Windows 標準搭載）
- **AutoHotkey**: v2（Window Resizer をソースから改変・ビルドする場合のみ必要。ビルド済み `WindowResizer.exe` はそのまま動作します）

---

## 📄 ライセンス

本リポジトリのコードは [MIT License](./LICENSE) のもとで公開されています。
ご自身の環境に合わせてご自由にお使い・改変いただけます。
