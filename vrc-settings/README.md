# VRChat ＆ 関連周辺設定・プロファイル集 (vrc-settings)

VRChat 環境の最適化、コントローラー・トラッキングデバイスの設定、および VPM パッケージ管理に必要な設定ファイル群です。

---

## 📁 収録ファイル一覧

| ファイル名 | 種別 | 説明 |
| :--- | :--- | :--- |
| **`VRC設定エクスポート.ps1`** | PowerShell | `reg export` を用いて VRChat の全レジストリ設定をダウンロードフォルダへ即座にバックアップ |
| **`VRC設定インポート.ps1`** | PowerShell | 既存設定の自動バックアップを取りつつ、エクスポートした設定を安全にレジストリへ復元 |
| **`config.json`** | JSON | VRChat 公式クライアント設定（キャッシュ保存先・容量・写真保存先変更） |
| **`repositories.txt`** | テキスト | VPM (VRChat Package Manager) の主要リポジトリ URL リスト |
| **`rebo.rebo_setting`** | 設定ファイル | ReBones（モーショントラッキング・IK・VMC連携）のプロファイル設定 |
| **`addcon_settings_20260902.json`** | JSON | AddCon コントローラーの全プリセット統合バックアップ |
| **`VRChat.json`** | JSON | AddCon: VRChat 用 OSC・カメラ・移動操作プロファイル |
| **`汎用.json`** | JSON | AddCon: デスクトップ操作（Alt+Tab・極小化）＆アバター操作（LLC/PCSS/視線高さ）プロファイル |

---

## 🛠️ 各ファイルの詳細と使い方

### 1. VRChat レジストリ移行スクリプト
- **`VRC設定エクスポート.ps1`**:
  - 実行すると、`HKCU\Software\VRChat\vrchat` の内容を `%USERPROFILE%\Downloads\vrchat-settings.reg` へ出力します。
- **`VRC設定インポート.ps1`**:
  - 実行すると、現在の設定を `%USERPROFILE%\Downloads\vrchat-settings-backup.reg` に退避した上で、`vrchat-settings.reg` の設定をレジストリへ取り込みます。

### 2. VRChat クライアント設定 (`config.json`)
VRChat 公式クライアントの詳細動作を制御する設定ファイルです。

- **配置場所**: `%LOCALAPPDATA%Low\VRChat\VRChat\config.json`
- **設定内容**:
  ```json
  {
      "picture_output_folder": "E:\\windows\\VRC-Cache",
      "picture_output_split_by_date": true,
      "cache_directory": "E:\\windows\\VRC-Cache",
      "cache_size": 100,
      "cache_expiry_delay": 60
  }
  ```
  - C ドライブの圧迫を防ぐため、VRChat のアバター・ワールドキャッシュおよびスクリーンショット保存先を別ドライブ（`E:\windows\VRC-Cache`）へリダイレクトします。
  - キャッシュ最大容量を 100GB に設定し、キャッシュ保持期間を最適化しています。

### 3. VPM リポジトリリスト (`repositories.txt`)
VRChat アバター・ワールド改変で必須となる主要ツールの VPM リポジトリ一覧です。

- **収録リポジトリ**:
  - `vpmm` (VPM Package Manager)
  - `lilToon` (定番アバターシェーダー)
  - `Modular Avatar` (非破壊アバター改変ツール)
  - `AAO` (Anatawa12's Avatar Optimizer: アバター最適化・軽量化)
  - `LightLimitChanger (LLC)` (ライティング明暗調整ギミック)
  - `Lighfu`, `RamType0`, `StudioRaming`, `Hakari-Lab` 各リポジトリ
- **追加方法**:
  `vrc-get` または ALCOM / VCC のリポジトリ追加欄に URL を貼り付けて登録します。

### 4. ReBones トラッキング設定 (`rebo.rebo_setting`)
AI モーショントラッキング / 骨格トラッキング支援ツール「ReBones」の設定バイナリ（pickle 形式）です。
- VMC プロトコル出力、IK 補正（大腿・肩・脊椎の角度・スライド連動）、VR 空間内でのトラッカー配置座標などがキャリブレーションされています。

### 5. AddCon コントローラー設定 (`VRChat.json`, `汎用.json`, `addcon_settings_20260902.json`)
左手・右手デバイス「AddCon」向けの割り当てプロファイルです。

- **`VRChat.json`**:
  - **左手**: OSC 移動（前後左右）、ジャンプ、ダッシュ、マイク Voice トグル、カメラ露出（ホイール）
  - **右手**: カメラ操作（オートレベル Pitch/Roll、カメラ UI 表示、自撮り LookAtMe、ドローン Flying、撮影シャッター、撮影遅延タイマー、ズームホイール）
- **`汎用.json`**:
  - **左手**: キーボード操作（Alt+Tab、WindowResizer 極小化 `Ctrl+Shift+M`、`Ctrl+Shift+X`、`Ctrl+Shift+Z`）、アバター視線高さ調整 `/avatar/eyeheight`（ホイール）
  - **右手**: アバター制御 OSC（LocomotionLock、APS 制御、LightLimitChanger 明るさ調整、PCSS 影トグル、カメラシャッター・ズーム）
- **`addcon_settings_20260902.json`**:
  - 上記プリセットがすべて統合された AddCon の完全インポート用バックアップファイル。
