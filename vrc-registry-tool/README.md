# VRChat 設定レジストリ管理ツール (vrc-registry-tool)

VRChat の設定レジストリ（`HKCU\Software\VRChat\vrchat`）を `.reg` 形式で素早くバックアップおよび復元・移行するための PowerShell スクリプト集です。

PC の移行時、OS クリーンインストール時、またはグラフィック設定・アバター表示設定・オーディオ設定の保存やトラブル時の復旧に役立ちます。

---

## 📁 収録ファイル一覧

| ファイル名 | 説明 |
| :--- | :--- |
| **`VRC設定エクスポート.ps1`** | `reg export` を実行し、現在の VRChat 設定をダウンロードフォルダへ `.reg` ファイルとして即座に書き出します。 |
| **`VRC設定インポート.ps1`** | 移行先 PC で既存設定を自動バックアップした上で、ダウンロードフォルダの `.reg` ファイルをレジストリへ安全に取り込みます。 |

---

## 🚀 使い方

### 1. 移行元 PC: 設定のエクスポート（バックアップ）

PowerShell で `VRC設定エクスポート.ps1` を実行します（右クリックして「PowerShell で実行」またはターミナルから実行）。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\VRC設定エクスポート.ps1
```

- **出力先**: `C:\Users\<ユーザー名>\Downloads\vrchat-settings.reg`
- この生成された `vrchat-settings.reg` を、USB メモリやクラウド等を経由して移行先 PC へコピーします。

---

### 2. 移行先 PC: 設定のインポート（復元）

1. エクスポートした `vrchat-settings.reg` を移行先 PC の **「ダウンロード」フォルダ**（`%USERPROFILE%\Downloads\`）に配置します。
2. PowerShell で `VRC設定インポート.ps1` を実行します。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\VRC設定インポート.ps1
```

- **二重の安全機能**:
  インポートを実行する直前に、移行先 PC に元々あった既存設定が自動的に `vrchat-settings-backup.reg` としてダウンロードフォルダへ退避保存されます。万が一元の状態に戻したくなった場合でも安心です。

---

## ⚙️ スクリプトの動作仕様

### `VRC設定エクスポート.ps1`
```powershell
reg export "HKCU\Software\VRChat\vrchat" "$env:USERPROFILE\Downloads\vrchat-settings.reg" /y
```
- OS 標準の `reg export` コマンドを呼び出し、VRChat の全設定キーを Windows 標準のレジストリファイルとして高速出力します。

### `VRC設定インポート.ps1`
```powershell
# 移行先：既存設定のバックアップ
reg export "HKCU\Software\VRChat\vrchat" "$env:USERPROFILE\Downloads\vrchat-settings-backup.reg" /y

# 移行先：移行元の設定を取り込み
reg import "$env:USERPROFILE\Downloads\vrchat-settings.reg"
```
- 既存のレジストリ状態を退避してから取り込みを行うため、設定が消失するリスクを未然に防ぎます。

---

## ⚠️ ご注意

> [!CAUTION]
> 書き出された `vrchat-settings.reg` には、ご使用の環境のユーザー識別子（`unity.cloud_userid` 等）やアカウント関連キーが含まれる場合があります。
> 第三者へ共有する際や GitHub 等の公開リポジトリへアップロードする際は、テキストエディタで中身を確認し、個人情報が含まれていないか事前にご確認ください。
