# 移行先：既存設定のバックアップ
reg export "HKCU\Software\VRChat\vrchat" "$env:USERPROFILE\Downloads\vrchat-settings-backup.reg" /y

# 移行先：移行元の設定を取り込み
reg import "$env:USERPROFILE\Downloads\vrchat-settings.reg"