Enter-Phase 13 "Export Modified Image (WIM / ESD / SWM)"

# 13. Export modified image
$finalWim = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.wim"
$finalEsd = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.esd"
$tempWim  = Join-Path -Path "$nano11Dir\sources" -ChildPath "install_export.wim"
$exportScratch = Join-Path -Path $workDir -ChildPath "dism_export_scratch"

# Clean up any leftover temporary/broken export files and scratch dir
Remove-Item -LiteralPath $finalEsd -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempWim -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $exportScratch) {
    Remove-Item -LiteralPath $exportScratch -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $exportScratch -ErrorAction SilentlyContinue | Out-Null

# Flush memory and release native file handles prior to export
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
Start-Sleep -Milliseconds 500

$exportSuccess = $false
$script:StreamIntegrityVerified = $false
$script:StreamIntegrityMethod = "NOT VERIFIED"
$dismExportLog = Join-Path -Path $workDir -ChildPath "dism_export.log"
$exportIntegrityReport = Join-Path -Path $workDir -ChildPath "dism_export_integrity_report.txt"
Remove-Item -LiteralPath $dismExportLog, $exportIntegrityReport -Force -ErrorAction SilentlyContinue

# A. Recovery ESD Export (if requested)
if ($exportESDMode) {
    Write-Host "Exporting modified image to recovery-compressed install.esd (LZMS)..." -ForegroundColor Green
    $exportOut = & dism.exe /English /Export-Image "/SourceImageFile:$destWim" "/SourceIndex:$index" "/DestinationImageFile:$finalEsd" /Compress:recovery "/ScratchDir:$exportScratch" /CheckIntegrity "/LogPath:$dismExportLog" 2>&1
    $exportExit = $LASTEXITCODE

    $integrityEntry = @(
        "=== Phase 13 ESD Export-Image with /CheckIntegrity ===",
        "Timestamp:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "ExitCode:     $exportExit",
        "Raw Output:",
        ($exportOut -join "`r`n"),
        "======================================================="
    ) -join "`r`n"
    [System.IO.File]::AppendAllText($exportIntegrityReport, "$integrityEntry`r`n", [System.Text.Encoding]::UTF8)

    if ($exportExit -eq 0 -and (Test-Path -LiteralPath $finalEsd) -and ((Get-Item -LiteralPath $finalEsd).Length -gt 1GB)) {
        Write-Host "install.esd successfully created with /CheckIntegrity ($([math]::Round((Get-Item -LiteralPath $finalEsd).Length / 1GB, 2)) GB). Removing temporary install.wim..." -ForegroundColor Green
        Remove-Item -LiteralPath $destWim -Force -ErrorAction SilentlyContinue
        $script:StreamIntegrityVerified = $true
        $script:StreamIntegrityMethod = "DISM /Export-Image /CheckIntegrity (ESD, ExitCode: 0)"
        $exportSuccess = $true
    } else {
        Write-Host "Notice: ESD export with /CheckIntegrity returned exit code $exportExit. Raw output: $(($exportOut | Select-Object -First 2) -join ' '). Retrying without /CheckIntegrity..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $finalEsd -Force -ErrorAction SilentlyContinue
        $exportRetryOut = & dism.exe /English /Export-Image "/SourceImageFile:$destWim" "/SourceIndex:$index" "/DestinationImageFile:$finalEsd" /Compress:recovery "/ScratchDir:$exportScratch" "/LogPath:$dismExportLog" 2>&1
        $exportRetryExit = $LASTEXITCODE

        $retryEntry = @(
            "=== Phase 13 ESD Export-Image without /CheckIntegrity (Fallback) ===",
            "Timestamp:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "ExitCode:     $exportRetryExit",
            "Raw Output:",
            ($exportRetryOut -join "`r`n"),
            "===================================================================="
        ) -join "`r`n"
        [System.IO.File]::AppendAllText($exportIntegrityReport, "$retryEntry`r`n", [System.Text.Encoding]::UTF8)

        if ($exportRetryExit -eq 0 -and (Test-Path -LiteralPath $finalEsd) -and ((Get-Item -LiteralPath $finalEsd).Length -gt 1GB)) {
            Write-Host "install.esd successfully created ($([math]::Round((Get-Item -LiteralPath $finalEsd).Length / 1GB, 2)) GB). Removing temporary install.wim..." -ForegroundColor Green
            Remove-Item -LiteralPath $destWim -Force -ErrorAction SilentlyContinue
            $script:StreamIntegrityVerified = $false
            $script:StreamIntegrityMethod = "Fallback ESD export without /CheckIntegrity (ExitCode: 0)"
            $exportSuccess = $true
        } else {
            Write-Host "Recovery export failed. Cleaning up incomplete ESD and falling back to install.wim..." -ForegroundColor Yellow
            Remove-Item -LiteralPath $finalEsd -Force -ErrorAction SilentlyContinue
        }
    }
}

# B. Standard WIM Export with Dual-Tier Resilient Compression (max -> fast)
if (-not $exportSuccess) {
    $compressModes = @()
    if ($fastExport) {
        $compressModes += "/Compress:fast"
    } else {
        $compressModes += "/Compress:max"
        $compressModes += "/Compress:fast" # Resilient fallback if max encounters memory exception
    }

    foreach ($compMode in $compressModes) {
        Write-Host "Exporting modified image to single-edition install.wim ($compMode)..." -ForegroundColor Green
        Remove-Item -LiteralPath $tempWim -Force -ErrorAction SilentlyContinue

        $exportOut = & dism.exe /English /Export-Image "/SourceImageFile:$destWim" "/SourceIndex:$index" "/DestinationImageFile:$tempWim" $compMode "/ScratchDir:$exportScratch" /CheckIntegrity "/LogPath:$dismExportLog" 2>&1
        $exportExit = $LASTEXITCODE

        $integrityEntry = @(
            "=== Phase 13 Export-Image with /CheckIntegrity ===",
            "Timestamp:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Mode:         $compMode",
            "ExitCode:     $exportExit",
            "Raw Output:",
            ($exportOut -join "`r`n"),
            "=================================================="
        ) -join "`r`n"
        [System.IO.File]::AppendAllText($exportIntegrityReport, "$integrityEntry`r`n", [System.Text.Encoding]::UTF8)

        if ($exportExit -eq 0 -and (Test-Path -LiteralPath $tempWim) -and ((Get-Item -LiteralPath $tempWim).Length -gt 1GB)) {
            $script:StreamIntegrityVerified = $true
            $script:StreamIntegrityMethod = "DISM /Export-Image /CheckIntegrity (ExitCode: 0)"
            Remove-Item -LiteralPath $destWim -Force -ErrorAction SilentlyContinue
            Rename-Item -LiteralPath $tempWim -NewName "install.wim" -Force
            $exportedWimSize = (Get-Item -LiteralPath $finalWim).Length
            Write-Host "install.wim successfully exported with /CheckIntegrity ($([math]::Round($exportedWimSize / 1GB, 2)) GB)." -ForegroundColor Green
            $exportSuccess = $true
            break
        } else {
            Write-Host "Notice: Export with /CheckIntegrity returned exit code $exportExit. Raw output: $(($exportOut | Select-Object -First 2) -join ' '). Retrying without /CheckIntegrity..." -ForegroundColor Yellow
            Remove-Item -LiteralPath $tempWim -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $exportRetryOut = & dism.exe /English /Export-Image "/SourceImageFile:$destWim" "/SourceIndex:$index" "/DestinationImageFile:$tempWim" $compMode "/ScratchDir:$exportScratch" "/LogPath:$dismExportLog" 2>&1
            $exportRetryExit = $LASTEXITCODE

            $retryEntry = @(
                "=== Phase 13 Export-Image without /CheckIntegrity (Fallback) ===",
                "Timestamp:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
                "Mode:         $compMode",
                "ExitCode:     $exportRetryExit",
                "Raw Output:",
                ($exportRetryOut -join "`r`n"),
                "================================================================"
            ) -join "`r`n"
            [System.IO.File]::AppendAllText($exportIntegrityReport, "$retryEntry`r`n", [System.Text.Encoding]::UTF8)

            if ($exportRetryExit -eq 0 -and (Test-Path -LiteralPath $tempWim) -and ((Get-Item -LiteralPath $tempWim).Length -gt 1GB)) {
                $script:StreamIntegrityVerified = $false
                $script:StreamIntegrityMethod = "Fallback export without /CheckIntegrity (ExitCode: 0)"
                Remove-Item -LiteralPath $destWim -Force -ErrorAction SilentlyContinue
                Rename-Item -LiteralPath $tempWim -NewName "install.wim" -Force
                $exportedWimSize = (Get-Item -LiteralPath $finalWim).Length
                Write-Host "install.wim successfully exported ($([math]::Round($exportedWimSize / 1GB, 2)) GB)." -ForegroundColor Green
                $exportSuccess = $true
                break
            } else {
                Write-Host "Export with $compMode did not complete successfully (Exit code: $exportRetryExit). Cleaning up incomplete file..." -ForegroundColor Yellow
                Remove-Item -LiteralPath $tempWim -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
        }
    }
}

# C. Ultimate Fallback: In-place index pruning if Export-Image failed
# Prunes all unmodified editions from original install.wim so that ONLY the modified target edition remains.
# This prevents Windows Setup from showing edition selection prompts and prevents clean/bloated editions from being installed.
if (-not $exportSuccess) {
    Write-Host "Notice: Direct export failed. Initiating automated in-place pruning of unmodified editions from install.wim to guarantee single-edition Pro deployment..." -ForegroundColor Yellow

    $maxPruneAttempts = 10
    $pruneAttempt = 0
    $failedPruneIndices = @()
    while ($pruneAttempt -lt $maxPruneAttempts) {
        $pruneAttempt++
        $currentInfo = & dism.exe /English /Get-WimInfo "/WimFile:$destWim"
        $entries = @()
        $cur = $null
        foreach ($line in ($currentInfo -split '\r?\n')) {
            if ($line -match '^\s*Index\s*:\s*(\d+)') {
                $cur = [PSCustomObject]@{ Index = [int]$matches[1]; Name = "" }
                $entries += $cur
            } elseif ($cur -and ($line -match '^\s*Name\s*:\s*(.+)')) {
                $cur.Name = $matches[1].Trim()
            }
        }

        if ($entries.Count -le 1) {
            Write-Host "install.wim now contains only a single edition ($($entries[0].Name)). Universal setup compliance guaranteed." -ForegroundColor Green
            break
        }

        # Select highest index among unmodified editions to prune safely (excluding previously failed ones)
        $toRemove = $entries | Where-Object {
            ($_.Index -notin $failedPruneIndices) -and (if ($targetEditionName) { $_.Name -ne $targetEditionName } else { $_.Index -ne [int]$index })
        } | Select-Object -Last 1

        if (-not $toRemove) {
            $toRemove = $entries | Where-Object { ($_.Index -notin $failedPruneIndices) -and ($_.Index -ne [int]$index) } | Select-Object -Last 1
        }

        if ($toRemove) {
            Write-Host "Pruning unmodified edition [Index $($toRemove.Index): $($toRemove.Name)] from install.wim..." -ForegroundColor Cyan
            # Do not specify /CheckIntegrity on in-place Delete-Image to prevent aborting on preexisting table mismatches
            & dism.exe /English /Delete-Image "/ImageFile:$destWim" "/Index:$($toRemove.Index)" "/ScratchDir:$exportScratch"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Warning: Failed to delete edition Index $($toRemove.Index) (Exit code: $LASTEXITCODE)." -ForegroundColor Yellow
                $failedPruneIndices += $toRemove.Index
            }
        } else {
            break
        }
    }

    if (Test-Path -LiteralPath $destWim) {
        $finalSize = (Get-Item -LiteralPath $destWim).Length
        Write-Host "Retained pruned install.wim ($([math]::Round($finalSize / 1GB, 2)) GB) as single-edition installation payload." -ForegroundColor Green
    }
}

# Clean up export scratch directory
Remove-Item -LiteralPath $exportScratch -Recurse -Force -ErrorAction SilentlyContinue

# Split-WIM (install.swm) for 100% FAT32 USB compatibility
if ($splitWIMMode -and (Test-Path -LiteralPath $finalWim)) {
    Write-Host "Splitting install.wim into <= 3800MB chunks for 100% FAT32 USB compatibility (install.swm)..." -ForegroundColor Cyan
    $swmTarget = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.swm"
    & dism.exe /English /Split-Image "/ImageFile:$finalWim" "/SWMFile:$swmTarget" /FileSize:3800
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $swmTarget)) {
        $swmParts = Get-ChildItem -Path "$nano11Dir\sources" -Filter "install*.swm"
        Write-Host "install.swm successfully generated ($($swmParts.Count) parts). Removing single install.wim..." -ForegroundColor Green
        Remove-Item -LiteralPath $finalWim -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Warning: Split-Image failed. Retaining single install.wim." -ForegroundColor Yellow
    }
}

Enter-Phase 14 "Patch boot.wim (LabConfig & Bypasses)"

# 14. Shrink and modify boot.wim (Setup bypasses & dynamic index handling)
$bootWimPath = Join-Path -Path "$nano11Dir\sources" -ChildPath "boot.wim"
if (-not (Test-Path -LiteralPath $bootWimPath)) {
    $sourceBootWim = Join-Path -Path "$DriveLetter\sources" -ChildPath "boot.wim"
    if (Test-Path -LiteralPath $sourceBootWim) {
        Write-Host "Restoring boot.wim from source media..." -ForegroundColor Cyan
        Copy-Item -LiteralPath $sourceBootWim -Destination $bootWimPath -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path -LiteralPath $bootWimPath) {
    Write-Host "Processing boot.wim..." -ForegroundColor Green
    Set-ItemOwnershipAndAccess -Path $bootWimPath
    try { Set-ItemProperty -LiteralPath $bootWimPath -Name IsReadOnly -Value $false -ErrorAction Stop } catch {}

    # Inspect boot.wim indices (Setup image is usually Index 2, WinPE is Index 1)
    # We patch both indices in-place and preserve dual-index structure for 100% BCD and UEFI stability.
    $bootInfo = & dism.exe /English /Get-WimInfo "/WimFile:$bootWimPath"
    $hasIndex2 = ($bootInfo -split '\r?\n') -match 'Index\s*:\s*2'
    $indicesToPatch = if ($hasIndex2) { @(1, 2) } else { @(1) }

    foreach ($bIndex in $indicesToPatch) {
        Write-Host "  - Applying Setup & Hardware requirement bypasses to boot.wim Index $bIndex..." -ForegroundColor Cyan
        $bMountResult = Invoke-Nano11ImageMount -ImageFile $bootWimPath -ImageIndex $bIndex -Retries 3
        $scratchDir = $bMountResult.MountDir
        $script:DismMountDir = $scratchDir
        $script:MountOpened = $true

        try {
            & reg.exe query "HKLM\zSYSTEM" > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                [void](<Unmount-RegistryHiveWithRetry -Name 'zSYSTEM'>)
            }
            reg.exe load HKLM\zSYSTEM "$scratchDir\Windows\System32\config\SYSTEM" > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                $script:HivesLoaded = $true
            }
            foreach ($key in $labConfigKeys) {
                reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v $key /t REG_DWORD /d 1 /f > $null 2>&1
            }
            reg.exe add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassNRO" /t REG_DWORD /d 1 /f > $null 2>&1
            reg.exe add "HKLM\zSYSTEM\Setup\MoSetup" /v "AllowUpgradesWithUnsupportedTPMOrCPU" /t REG_DWORD /d 1 /f > $null 2>&1
            reg.exe add "HKLM\zSYSTEM\ControlSet001\Control\BitLocker" /v "PreventDeviceEncryption" /t REG_DWORD /d 1 /f > $null 2>&1
            # CurrentControlSet is dynamically linked by the Windows kernel at boot; leave hive untouched.
        } finally {
            [void](<Unmount-RegistryHiveWithRetry -Name 'zSYSTEM'>)
            $script:HivesLoaded = $false
        }

        Set-Location -LiteralPath $scriptDir
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()

        $bootUnmountSuccess = $false
        for ($bRetry = 1; $bRetry -le 3; $bRetry++) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Set-Location -LiteralPath $scriptDir
            Start-Sleep -Seconds 2
            & dism.exe /English /Unmount-Image "/MountDir:$scratchDir" /commit
            if ($LASTEXITCODE -eq 0) {
                $bootUnmountSuccess = $true
                break
            }
            Set-Location -LiteralPath $scriptDir
            Start-Sleep -Seconds (2 * $bRetry)
        }

        if (-not $bootUnmountSuccess) {
            Write-Host "Falling back to discard unmount for boot.wim index $bIndex..." -ForegroundColor Yellow
            & dism.exe /English /Unmount-Image "/MountDir:$scratchDir" /discard > $null 2>&1
            throw "Failed to commit changes to boot.wim Index $bIndex after multiple attempts. Aborting build."
        }

        # Verify unmount was completed and no lock remains
        Clear-DismMountConflicts -TargetMountDir $scratchDir -TargetWimFile $bootWimPath
        $script:MountOpened = $false
    }
}

Enter-Phase 15 "Verify Final Installation Payload"

# 15. Verify final installation payload
$esdCheck = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.esd"
$wimCheck = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.wim"
$swmCheck = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.swm"

$validEsd = (Test-Path -LiteralPath $esdCheck) -and ((Get-Item -LiteralPath $esdCheck).Length -gt 1GB)
$validWim = (Test-Path -LiteralPath $wimCheck) -and ((Get-Item -LiteralPath $wimCheck).Length -gt 1GB)
$validSwm = (Test-Path -LiteralPath $swmCheck) -and ((Get-Item -LiteralPath $swmCheck).Length -gt 500MB)

# Remove any corrupt stub files or invalid partial files (< 1GB / < 500MB)
if (-not $validEsd -and (Test-Path -LiteralPath $esdCheck)) {
    Write-Host "Warning: Corrupt or incomplete install.esd detected ($((Get-Item -LiteralPath $esdCheck).Length) bytes). Removing..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $esdCheck -Force -ErrorAction SilentlyContinue
    $validEsd = $false
}
if (-not $validWim -and (Test-Path -LiteralPath $wimCheck) -and (-not $validSwm)) {
    Write-Host "Warning: Corrupt or incomplete install.wim detected ($((Get-Item -LiteralPath $wimCheck).Length) bytes). Removing..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $wimCheck -Force -ErrorAction SilentlyContinue
    $validWim = $false
}

if ($validWim) {
    $wimSizeGB = [math]::Round((Get-Item -LiteralPath $wimCheck).Length / 1GB, 2)
    Write-Host "Final installation image confirmed: install.wim ($wimSizeGB GB)" -ForegroundColor Green
    if (Test-Path -LiteralPath $esdCheck) {
        Remove-Item -LiteralPath $esdCheck -Force -ErrorAction SilentlyContinue
    }

    # 1. Metadata Verification via DISM /Get-WimInfo (Strictly metadata query only, no /CheckIntegrity)
    Write-Host "Verifying install.wim metadata structure via DISM..." -ForegroundColor Cyan
    $dismMetaOut = & dism.exe /English /Get-WimInfo "/WimFile:$wimCheck" 2>&1
    $dismMetaExit = $LASTEXITCODE
    $metadataValid = ($dismMetaExit -eq 0) -and ($dismMetaOut -match 'Index\s*:\s*\d+')
    $metadataStatus = if ($metadataValid) { "PASS" } else { "FAIL" }

    if ($metadataStatus -eq "FAIL") {
        Write-Host "CRITICAL ERROR: install.wim failed metadata verification via DISM /Get-WimInfo (ExitCode: $dismMetaExit)!" -ForegroundColor Red
        $dismMetaOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        throw "install.wim failed metadata verification (ExitCode: $dismMetaExit). Aborting ISO creation."
    }

    # 2. Stream Integrity Verification (Decoupled from metadata query)
    $streamIntegrityStatus = "NOT VERIFIED"
    $streamIntegrityDetails = "No stream integrity verification performed"

    $sevenZipCandidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    $szTool = $sevenZipCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($szTool) {
        Write-Host "Performing stream integrity test via 7-Zip..." -ForegroundColor Cyan
        $szOut = & "$szTool" t "$wimCheck" 2>&1
        $szExit = $LASTEXITCODE
        $hasDataError = ($szExit -ne 0) -or ($szOut -match 'Data Error|ERROR:|Sub items Errors')

        if ($hasDataError) {
            $streamIntegrityStatus = "FAIL"
            $streamIntegrityDetails = "7-Zip reported stream or data errors (ExitCode: $szExit)"
            Write-Host "CRITICAL ERROR: Stream integrity test detected corrupted streams in install.wim!" -ForegroundColor Red
            $szOut | Where-Object { $_ -match 'Data Error|ERROR:|Sub items' } | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            throw "install.wim failed stream integrity verification via 7-Zip. Aborting ISO creation to prevent corrupted media."
        } else {
            $streamIntegrityStatus = "PASS"
            $streamIntegrityDetails = "7-Zip stream test completed successfully (ExitCode: 0)"
        }
    } elseif ($script:StreamIntegrityVerified) {
        $streamIntegrityStatus = "PASS"
        $streamIntegrityDetails = "Verified during Phase 13: $script:StreamIntegrityMethod"
    } else {
        $streamIntegrityStatus = "NOT VERIFIED"
        $streamIntegrityDetails = "7-Zip is not available and Phase 13 export did not produce a verified integrity table ($script:StreamIntegrityMethod)"
    }

    # Output verification summary
    Write-Host "Payload Verification Summary:" -ForegroundColor Cyan
    Write-Host "  - Metadata Status:         $metadataStatus" -ForegroundColor $(if ($metadataStatus -eq "PASS") { "Green" } else { "Red" })
    Write-Host "  - Stream Integrity Status: $streamIntegrityStatus ($streamIntegrityDetails)" -ForegroundColor $(if ($streamIntegrityStatus -eq "PASS") { "Green" } elseif ($streamIntegrityStatus -eq "NOT VERIFIED") { "Yellow" } else { "Red" })

    # Save summary report to sources
    $wimSummaryPath = Join-Path -Path "$nano11Dir\sources" -ChildPath "wim-verification-summary.txt"
    $wimSummaryLines = @(
        "=== Final Payload Verification Summary ===",
        "Timestamp:               $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Target Image:            $wimCheck",
        "Image Size:              $wimSizeGB GB",
        "Metadata Status:         $metadataStatus",
        "Stream Integrity Status: $streamIntegrityStatus",
        "Stream Details:          $streamIntegrityDetails",
        "=========================================="
    )
    [System.IO.File]::WriteAllLines($wimSummaryPath, $wimSummaryLines, [System.Text.Encoding]::UTF8)
} elseif ($validSwm) {
    $swmParts = Get-ChildItem -Path "$nano11Dir\sources" -Filter "install*.swm"
    Write-Host "Final installation image confirmed: install.swm (Split-WIM: $($swmParts.Count) parts for FAT32 USB support)" -ForegroundColor Green
    if (Test-Path -LiteralPath $wimCheck) {
        Remove-Item -LiteralPath $wimCheck -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $esdCheck) {
        Remove-Item -LiteralPath $esdCheck -Force -ErrorAction SilentlyContinue
    }
} elseif ($validEsd) {
    $esdSizeGB = [math]::Round((Get-Item -LiteralPath $esdCheck).Length / 1GB, 2)
    Write-Host "Final installation image confirmed: install.esd ($esdSizeGB GB)" -ForegroundColor Green
    if (Test-Path -LiteralPath $wimCheck) {
        Remove-Item -LiteralPath $wimCheck -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Verifying install.esd metadata structure via DISM..." -ForegroundColor Cyan
    $dismMetaOut = & dism.exe /English /Get-WimInfo "/WimFile:$esdCheck" 2>&1
    $dismMetaExit = $LASTEXITCODE
    $metadataValid = ($dismMetaExit -eq 0) -and ($dismMetaOut -match 'Index\s*:\s*\d+')
    $metadataStatus = if ($metadataValid) { "PASS" } else { "FAIL" }

    if ($metadataStatus -eq "FAIL") {
        Write-Host "CRITICAL ERROR: install.esd failed metadata verification via DISM /Get-WimInfo (ExitCode: $dismMetaExit)!" -ForegroundColor Red
        $dismMetaOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        throw "install.esd failed metadata verification (ExitCode: $dismMetaExit). Aborting ISO creation."
    }

    $streamIntegrityStatus = if ($script:StreamIntegrityVerified) { "PASS" } else { "NOT VERIFIED" }
    $streamIntegrityDetails = if ($script:StreamIntegrityVerified) { "Verified during Phase 13: $script:StreamIntegrityMethod" } else { "Phase 13 export did not produce a verified integrity table ($script:StreamIntegrityMethod)" }

    Write-Host "Payload Verification Summary:" -ForegroundColor Cyan
    Write-Host "  - Metadata Status:         $metadataStatus" -ForegroundColor $(if ($metadataStatus -eq "PASS") { "Green" } else { "Red" })
    Write-Host "  - Stream Integrity Status: $streamIntegrityStatus ($streamIntegrityDetails)" -ForegroundColor $(if ($streamIntegrityStatus -eq "PASS") { "Green" } elseif ($streamIntegrityStatus -eq "NOT VERIFIED") { "Yellow" } else { "Red" })

    $esdSummaryPath = Join-Path -Path "$nano11Dir\sources" -ChildPath "wim-verification-summary.txt"
    $esdSummaryLines = @(
        "=== Final Payload Verification Summary ===",
        "Timestamp:               $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Target Image:            $esdCheck",
        "Image Size:              $esdSizeGB GB",
        "Metadata Status:         $metadataStatus",
        "Stream Integrity Status: $streamIntegrityStatus",
        "Stream Details:          $streamIntegrityDetails",
        "=========================================="
    )
    [System.IO.File]::WriteAllLines($esdSummaryPath, $esdSummaryLines, [System.Text.Encoding]::UTF8)
} else {
    Write-Host "CRITICAL ERROR: No valid installation payload (install.wim, install.esd, or install.swm) found in $nano11Dir\sources!" -ForegroundColor Red
    Write-Host "Aborting ISO creation to prevent producing an unbootable or corrupt image." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Enter-Phase 16 "ISO Root Cleanup & Traceability Embedding"

# 16. Final cleanup of ISO root and sources
Write-Host "Performing final cleanup of ISO root..." -ForegroundColor Cyan
$keepList = @("boot", "efi", "sources", "bootmgr", "bootmgr.efi", "bootmgfw.efi", "setup.exe", "autounattend.xml", "nano11-build-info.json")
Get-ChildItem -Path $nano11Dir | Where-Object { $_.Name -notin $keepList } | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# Clean leftover build diagnostics and setup logs inside sources
$sourcesDir = Join-Path -Path $nano11Dir -ChildPath "sources"
if (Test-Path -LiteralPath $sourcesDir) {
    Remove-Item -Path "$sourcesDir\setupcore.log" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$sourcesDir\*.diagerr" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$sourcesDir\*.diagxml" -Force -ErrorAction SilentlyContinue
    # Remove any broken or empty OEM folders that cause 0x80070002 during Setup file expansion
    $brokenOem = Join-Path -Path $sourcesDir -ChildPath "`$OEM`$"
    if ((Test-Path -LiteralPath $brokenOem) -and ((Get-ChildItem -Path $brokenOem -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -LiteralPath $brokenOem -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Enter-Phase 17 "Locate or Verify oscdimg.exe"

# 17. Locate or download oscdimg.exe (checks local dirs, PATH, ADK, and multi-mirror fallback)
$oscdimgCandidates = @(
    (Join-Path -Path $scriptDir -ChildPath "oscdimg.exe"),
    (Join-Path -Path (Get-Location).Path -ChildPath "oscdimg.exe"),
    (Join-Path -Path "$env:USERPROFILE\Downloads\nano11-main" -ChildPath "oscdimg.exe"),
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\arm64\Oscdimg\oscdimg.exe",
    "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\arm64\Oscdimg\oscdimg.exe"
)

# Also check if oscdimg is available in PATH
$pathOscd = Get-Command "oscdimg.exe" -ErrorAction SilentlyContinue
if ($pathOscd -and $pathOscd.Source) {
    $oscdimgCandidates += $pathOscd.Source
}

$oscdimgExe = $null
foreach ($candidate in $oscdimgCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
        if (Test-OscdimgIntegrity -OscdimgPath $candidate) {
            $oscdimgExe = $candidate
            Write-Host "Found verified local oscdimg.exe: $oscdimgExe" -ForegroundColor Green
            break
        } else {
            Write-Warning "Candidate oscdimg binary at '$candidate' failed Authenticode and hash verification! Skipping."
        }
    }
}

if (-not $oscdimgExe) {
    $targetOscdPath = Join-Path -Path $scriptDir -ChildPath "oscdimg.exe"
    Write-Host "Downloading oscdimg.exe..." -ForegroundColor Cyan
    
    $mirrors = @(
        "https://raw.githubusercontent.com/gh459/nano11/main/oscdimg.exe",
        "https://github.com/gh459/nano11/raw/main/oscdimg.exe",
        "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    )
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    if ([Enum]::IsDefined([Net.SecurityProtocolType], 'Tls13')) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]'Tls13'
    }
} catch {}
    
    foreach ($url in $mirrors) {
        try {
            Write-Host "  - Attempting download from: $url" -ForegroundColor Gray
            Invoke-WebRequest -Uri $url -OutFile $targetOscdPath -UseBasicParsing -TimeoutSec 15
            if ((Test-Path -LiteralPath $targetOscdPath) -and (Test-OscdimgIntegrity -OscdimgPath $targetOscdPath)) {
                $oscdimgExe = $targetOscdPath
                Write-Host "  - oscdimg.exe downloaded and integrity verified successfully!" -ForegroundColor Green
                break
            } else {
                if (Test-Path -LiteralPath $targetOscdPath) { Remove-Item -LiteralPath $targetOscdPath -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-Host "  - Mirror failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # If still not found (e.g. system DNS failed to resolve hostnames), try public DNS resolution fallback
    if (-not $oscdimgExe) {
        try {
            Write-Host "  - Attempting public DNS fallback resolution (8.8.8.8)..." -ForegroundColor Gray
            $dnsEntry = Resolve-DnsName -Name "raw.githubusercontent.com" -Server 8.8.8.8 -ErrorAction SilentlyContinue | Where-Object { $_.IP4Address } | Select-Object -First 1
            if ($dnsEntry -and $dnsEntry.IP4Address) {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("Host", "raw.githubusercontent.com")
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile("https://$($dnsEntry.IP4Address)/gh459/nano11/main/oscdimg.exe", $targetOscdPath)
                if ((Test-Path -LiteralPath $targetOscdPath) -and ((Get-Item -LiteralPath $targetOscdPath).Length -gt 50KB)) {
                    $oscdimgExe = $targetOscdPath
                    Write-Host "  - oscdimg.exe downloaded successfully via public DNS fallback!" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "  - Public DNS fallback download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Enter-Phase 18 "Create Bootable ISO Image"

# 18. Create bootable ISO (oscdimg) with Architecture-aware bootdata and Volume Label
Write-Host "Creating bootable ISO image..." -ForegroundColor Green
$profSlug = if ($selectedProfile) { ($selectedProfile -replace '[^\w\-]', '_').Trim('_') } else { "custom" }
$isoTimestamp = (Get-Date).ToString("yyyyMMdd_HHmm")

# Determine output ISO filename (single output, no duplicate copies)
if ($OutputIsoName) {
    $isoFileName = if ($OutputIsoName.EndsWith('.iso', [System.StringComparison]::OrdinalIgnoreCase)) { $OutputIsoName } else { "$OutputIsoName.iso" }
} elseif ($TimestampIso) {
    $isoFileName = "nano11_${profSlug}_${isoTimestamp}.iso"
} else {
    $isoFileName = "nano11.iso"
}
$outputIso = Join-Path -Path $scriptDir -ChildPath $isoFileName

# Dismount and remove any existing output ISO to prevent file locks/collisions
try {
    $mounted = Get-DiskImage -ImagePath $outputIso -ErrorAction SilentlyContinue
    if ($mounted) {
        Write-Host "Dismounting previously mounted output ISO: $outputIso..." -ForegroundColor Yellow
        Dismount-DiskImage -ImagePath $outputIso -ErrorAction SilentlyContinue | Out-Null
    }
} catch {}
if (Test-Path -LiteralPath $outputIso) {
    Remove-Item -LiteralPath $outputIso -Force -ErrorAction SilentlyContinue
}

# Resolve etfsboot.com (BIOS boot sector)
$etfsBootCandidates = @(
    (Join-Path -Path "$nano11Dir\boot" -ChildPath "etfsboot.com"),
    (Join-Path -Path "$DriveLetter\boot" -ChildPath "etfsboot.com")
)
$etfsBoot = $null
foreach ($c in $etfsBootCandidates) {
    if (Test-Path -LiteralPath $c) {
        $localEtfs = Join-Path -Path "$nano11Dir\boot" -ChildPath "etfsboot.com"
        if (-not (Test-Path -LiteralPath $localEtfs)) {
            New-Item -ItemType Directory -Force -Path "$nano11Dir\boot" -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -LiteralPath $c -Destination $localEtfs -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $localEtfs) {
            $etfsBoot = $localEtfs
            break
        }
    }
}

# Resolve efisys.bin (UEFI boot sector) across candidate paths
$efiSysCandidates = @(
    (Join-Path -Path "$nano11Dir\efi\microsoft\boot" -ChildPath "efisys.bin"),
    (Join-Path -Path "$nano11Dir\efi\microsoft\boot" -ChildPath "efisys_noprompt.bin"),
    (Join-Path -Path "$DriveLetter\efi\microsoft\boot" -ChildPath "efisys.bin"),
    (Join-Path -Path "$DriveLetter\efi\microsoft\boot" -ChildPath "efisys_noprompt.bin"),
    (Join-Path -Path "$nano11Dir\efi\boot" -ChildPath "efisys.bin"),
    (Join-Path -Path "$DriveLetter\efi\boot" -ChildPath "efisys.bin")
)
$efiSys = $null
foreach ($c in $efiSysCandidates) {
    if (Test-Path -LiteralPath $c) {
        $localEfiSys = Join-Path -Path "$nano11Dir\efi\microsoft\boot" -ChildPath "efisys.bin"
        if (-not (Test-Path -LiteralPath $localEfiSys)) {
            New-Item -ItemType Directory -Force -Path "$nano11Dir\efi\microsoft\boot" -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -LiteralPath $c -Destination $localEfiSys -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $localEfiSys) {
            $efiSys = $localEfiSys
            break
        }
    }
}

# Determine bootdata parameters based on discovered boot sector files
$bootData = $null
if ($uefiOnly -and $efiSys) {
    # Force UEFI-only bootdata (no BIOS boot sector)
    $bootData = "1#pEF,e,b$efiSys"
    Write-Host "Configured UEFI-Only Boot (-UefiOnly):" -ForegroundColor Green
    Write-Host "  - UEFI Boot Sector: $efiSys" -ForegroundColor Gray
} elseif ($efiSys -and $etfsBoot -and ($architecture -ne 'arm64')) {
    # Dual boot: BIOS (etfsboot.com) + UEFI (efisys.bin)
    $bootData = "2#p0,e,b$etfsBoot#pEF,e,b$efiSys"
    Write-Host "Configured Dual Boot (BIOS + UEFI):" -ForegroundColor Green
    Write-Host "  - BIOS Boot Sector: $etfsBoot" -ForegroundColor Gray
    Write-Host "  - UEFI Boot Sector: $efiSys" -ForegroundColor Gray
} elseif ($efiSys) {
    # UEFI-only (ARM64 or systems without BIOS bootloader)
    $bootData = "1#pEF,e,b$efiSys"
    Write-Host "Configured UEFI Boot:" -ForegroundColor Green
    Write-Host "  - UEFI Boot Sector: $efiSys" -ForegroundColor Gray
} elseif ($etfsBoot) {
    # BIOS-only
    $bootData = "1#p0,e,b$etfsBoot"
    Write-Host "Configured BIOS Boot:" -ForegroundColor Green
    Write-Host "  - BIOS Boot Sector: $etfsBoot" -ForegroundColor Gray
} else {
    Write-Host "Warning: Neither BIOS nor UEFI boot sector files were found. Output ISO will not be bootable." -ForegroundColor Yellow
}

$isoCreatedSuccessfully = $false
if ($oscdimgExe -and (Test-Path -LiteralPath $oscdimgExe)) {
    $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-l`"nano11`"")
    if ($bootData) {
        $oscdimgArgs += "-bootdata:$bootData"
    }
    $oscdimgArgs += $nano11Dir
    $oscdimgArgs += $outputIso

    Write-Host "Executing oscdimg..." -ForegroundColor Cyan
    & "$oscdimgExe" @oscdimgArgs
    
    if ((Test-Path -LiteralPath $outputIso) -and ((Get-Item -LiteralPath $outputIso).Length -gt 1.5GB)) {
        $isoCreatedSuccessfully = $true
        $isoItem = Get-Item -LiteralPath $outputIso
        $isoSizeMB = [math]::Round($isoItem.Length / 1MB, 2)
        Write-Host "Calculating SHA256 checksum..." -ForegroundColor Cyan
        $sha256 = (Get-FileHash -LiteralPath $outputIso -Algorithm SHA256).Hash
        
        Write-Host ""
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host "   Creation complete! Your ISO is named $isoFileName" -ForegroundColor Green
        Write-Host "   Path:   $outputIso ($isoSizeMB MB)" -ForegroundColor Green
        Write-Host "   SHA256: $sha256" -ForegroundColor Green
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host ""

        # 3-Generation Retention Rotation for ISOs matching this profile (when TimestampIso is used)
        if ($TimestampIso) {
            try {
                $existingProfileIsos = Get-ChildItem -Path $scriptDir -Filter "nano11_${profSlug}_*.iso" -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending
                if ($existingProfileIsos.Count -gt 3) {
                    $isosToRemove = $existingProfileIsos | Select-Object -Skip 3
                    foreach ($oldIso in $isosToRemove) {
                        Write-Host "Rotating out older generation ISO: $($oldIso.Name)" -ForegroundColor DarkGray
                        Remove-Item -LiteralPath $oldIso.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {}
        }

        # Generate Visual HTML Build Report
        try {
            $reportOutputDir = Split-Path -Path $outputIso -Parent
            if (-not $reportOutputDir) { $reportOutputDir = $PSScriptRoot }
            $reportPath = Join-Path -Path $reportOutputDir -ChildPath "nano11_report.html"
            $reportData = @{
                Title             = "nano11 Master Build Report - $selectedProfile"
                Timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                Profile           = $selectedProfile
                Architecture      = $architecture
                SourceDrive       = $DriveLetter
                OutputIso         = $outputIso
                PayloadFormat     = if ($SplitWIM) { "install.swm" } elseif ($exportESDMode) { "install.esd" } else { "install.wim" }
                OriginalSizeBytes = if ($sourceWimSize -gt 0) { $sourceWimSize } else { 0 }
                FinalSizeBytes    = $isoItem.Length
                IsoSha256         = $sha256
                RegSuccessCount   = $script:regSuccessCount
                Settings          = $resolvedConfig
            }
            $reportData['RemovedPackagesCount'] = if ($script:RemovedPackages) { $script:RemovedPackages.Count } else { 0 }
            $reportData['WinSxSSavedMB']        = if ($script:WinSxSSavedMB) { $script:WinSxSSavedMB } else { 0 }
            $reportData['WinSxSBeforeMB']       = if ($script:WinSxsBeforeMB) { $script:WinSxsBeforeMB } else { 0 }
            $reportData['WinSxSAfterMB']        = if ($script:WinSxsAfterMB) { $script:WinSxsAfterMB } else { 0 }
            Export-Nano11HtmlReport -OutputPath $reportPath -BuildInfo $reportData
            Write-Host "Visual Build Report generated: $reportPath" -ForegroundColor Cyan

            # Post-build hook execution (tools\post-build.ps1)
            $postBuildScript = Join-Path -Path $scriptDir -ChildPath "tools\post-build.ps1"
            if (Test-Path -LiteralPath $postBuildScript) {
                Write-Host "Executing post-build hook: $postBuildScript..." -ForegroundColor Cyan
                try {
                    $isoSha256 = (Get-FileHash -LiteralPath $outputIso -Algorithm SHA256).Hash
                    & $postBuildScript -IsoPath $outputIso -IsoHash $isoSha256 -Profile $selectedProfile -LogDir $logDir
                } catch {
                    Write-Warning "Post-build hook exited with warning: $_"
                }
            }

            # GUI completion dialog
            if ($GUI -and $isoCreatedSuccessfully -and (Test-Path -LiteralPath $outputIso)) {
                $isoLenGB = [math]::Round((Get-Item -LiteralPath $outputIso).Length / 1GB, 2)
                $isoHashVal = (Get-FileHash -LiteralPath $outputIso -Algorithm SHA256).Hash
                $elapsedStr = if ($elapsedSec) { "$elapsedSec 秒" } else { "完了" }
                $dialogMsg = "nano11 ISO ビルドが正常に完了しました！`n`n" +
                             "■ 出力先: $outputIso`n" +
                             "■ サイズ: $isoLenGB GB`n" +
                             "■ SHA256: $isoHashVal`n" +
                             "■ 所要時間: $elapsedStr`n`n" +
                             "ISO が保存されたフォルダーを開きますか？"
                $res = [System.Windows.Forms.MessageBox]::Show($dialogMsg, "nano11 ビルド完了", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
                if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Invoke-Item -LiteralPath (Split-Path -Path $outputIso -Parent)
                }
            }
        } catch {
            Write-Warning "Could not export visual build report: $_"
        }
        if ($validSwm) {
            Write-Host "[100% FAT32 USB COMPATIBLE]" -ForegroundColor Green
            Write-Host "- The image was split into install.swm parts (each <= 3800MB)." -ForegroundColor Green
            Write-Host "- You can copy the contents of nano11.iso directly into any FAT32 USB drive!" -ForegroundColor Green
            Write-Host "- Standard UEFI systems will boot seamlessly without needing NTFS or Rufus." -ForegroundColor Green
            Write-Host ""
        } elseif ((Test-Path -LiteralPath (Join-Path -Path "$nano11Dir\sources" -ChildPath "install.wim")) -and ((Get-Item (Join-Path -Path "$nano11Dir\sources" -ChildPath "install.wim")).Length -gt 4000000000)) {
            Write-Host "[IMPORTANT NOTE FOR BOOTABLE USB CREATION]" -ForegroundColor Cyan
            Write-Host "- install.wim is larger than 4GB. FAT32 cannot store files > 4GB." -ForegroundColor Yellow
            Write-Host "- When creating a bootable USB with Rufus, select 'NTFS' filesystem." -ForegroundColor Yellow
            Write-Host "- Or copy nano11.iso directly into a Ventoy USB drive (recommended)." -ForegroundColor Yellow
            Write-Host "- Tip: Run with -SplitWIM to automatically split into FAT32-compatible parts." -ForegroundColor Cyan
            Write-Host ""
        }
    } else {
        Write-Host ""
        Write-Host "=========================================================" -ForegroundColor Red
        Write-Host "   ERROR: Failed to create valid bootable ISO!           " -ForegroundColor Red
        if (Test-Path -LiteralPath $outputIso) {
            Write-Host "   Generated ISO size ($([math]::Round((Get-Item -LiteralPath $outputIso).Length / 1MB, 2)) MB) is abnormally small (< 1.5 GB). Likely missing OS payload." -ForegroundColor Red
        } else {
            Write-Host "   oscdimg exited with code $LASTEXITCODE. The ISO file was not generated." -ForegroundColor Red
        }
        Write-Host "   Working directory preserved for inspection: $nano11Dir" -ForegroundColor Yellow
        Write-Host "=========================================================" -ForegroundColor Red
    }
} else {
    Write-Host "oscdimg.exe not found. You can manually package the ISO from: $nano11Dir" -ForegroundColor Yellow
}

if ($Validate) {
    $validateWim = Join-Path -Path "$nano11Dir\sources" -ChildPath "install.wim"
    if (Test-Path -LiteralPath $validateWim) {
        Write-Host "Running post-export image validation (-Validate)..." -ForegroundColor Cyan
        $valMountResult = $null
        try {
            $valMountResult = Invoke-Nano11ImageMount -ImageFile $validateWim -ImageIndex "1" -ReadOnly -Retries 3
            $verifyMount = $valMountResult.MountDir
            & dism.exe /English /Get-WimInfo "/WimFile:$validateWim" | Out-File (Join-Path -Path $baseWorkDir -ChildPath "verify-wiminfo.txt") -Encoding utf8
            $keyFiles = @(
                'Windows\System32\osk.exe',
                'Windows\System32\ctfmon.exe',
                'Windows\System32\Sysprep\sysprep.exe',
                'Windows\System32\cmd.exe'
            )
            $valLog = @()
            foreach ($kf in $keyFiles) {
                $exists = Test-Path -LiteralPath (Join-Path -Path $verifyMount -ChildPath $kf)
                $status = "{0} : {1}" -f $kf, $exists
                $valLog += $status
                Write-Host "  - Verification: $status" -ForegroundColor (if ($exists) { 'Green' } else { 'Yellow' })
            }
            $valLog | Out-File (Join-Path -Path $baseWorkDir -ChildPath "verify-paths.txt") -Encoding utf8
        } catch {
            Write-Warning "Post-export validation mount failed: $_"
        } finally {
            if ($valMountResult -and $valMountResult.MountDir) {
                $vDir = $valMountResult.MountDir
                & dism.exe /English /Unmount-Image "/MountDir:$vDir" /discard > $null 2>&1
                Clear-DismMountConflicts -TargetMountDir $vDir -TargetWimFile $validateWim
                Reset-DirectoryWithRobocopy -Path $vDir
                Remove-Item -LiteralPath $vDir -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
} catch {
    Write-Host ""
    Write-Host "Build failed with unhandled exception: $_" -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host "Exception location: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    }
    if ($_.ScriptStackTrace) {
        Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
    }
    throw
} finally {
    Write-Host ""
    Write-Host "Running cleanup and finalizing build lifecycle..." -ForegroundColor Cyan

    Set-Location -LiteralPath $scriptDir
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    # 1. Unload lingering offline registry hives
    if ($script:HivesLoaded) {
        Write-Host "Cleaning up lingering registry hives..." -ForegroundColor Yellow
        @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM') | ForEach-Object {
            try { [void](<Unmount-RegistryHiveWithRetry -Name $_>) } catch {}
        }
        $script:HivesLoaded = $false
    }

    # 2. Re-query and resolve any lingering DISM mounts across all allocated mount directories
    $canSafelyClean = $true
    $allTargetMounts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($script:AllocatedMountDirs) {
        foreach ($d in $script:AllocatedMountDirs) { [void]$allTargetMounts.Add($d) }
    }
    if ($scratchDir) {
        try { [void]$allTargetMounts.Add((ConvertTo-Nano11NormalizedPath -Path $scratchDir)) } catch {}
    }
    if ($vhdxMountDir -and (-not $script:IsVhdxMounted)) {
        try { [void]$allTargetMounts.Add((ConvertTo-Nano11NormalizedPath -Path $vhdxMountDir)) } catch {}
    }

    foreach ($mPath in $allTargetMounts) {
        if ($script:PreservedMountDirs -and $script:PreservedMountDirs.Contains($mPath)) {
            Write-Warning "Mount directory '$mPath' is marked as Preserved. Skipping cleanup."
            $canSafelyClean = $false
            continue
        }

        try {
            $activeMounts = @(Get-Nano11MountedImages)
            $lingeringMount = $activeMounts | Where-Object {
                $p = if ($_.Path) { try { ConvertTo-Nano11NormalizedPath -Path $_.Path } catch { $null } } else { $null }
                $p -and ($p -ieq $mPath)
            }
            if ($lingeringMount -or $script:MountOpened) {
                Write-Host "Discarding lingering DISM mount on '$mPath'..." -ForegroundColor Yellow
                Clear-DismMountConflicts -TargetMountDir $mPath
                $postQuery = @(Get-Nano11MountedImages)
                $stillActive = $postQuery | Where-Object {
                    $p = if ($_.Path) { try { ConvertTo-Nano11NormalizedPath -Path $_.Path } catch { $null } } else { $null }
                    $p -and ($p -ieq $mPath)
                }
                if ($stillActive) {
                    Write-Warning "Could not confirm unmount of '$mPath'. Marking as Preserved for safety."
                    [void]$script:PreservedMountDirs.Add($mPath)
                    $canSafelyClean = $false
                }
            }

            # Safely unload any offline hives
            $unmountedOk = Unmount-DismOfflineHives -TargetMountDir $mPath -BestEffort
            if (-not $unmountedOk) {
                Write-Warning "Lingering offline registry hives detected under '$mPath'. Marking as Preserved."
                [void]$script:PreservedMountDirs.Add($mPath)
                $canSafelyClean = $false
            }
        } catch {
            Write-Warning "Could not query or clean mount status for '$mPath': $_"
            $canSafelyClean = $false
        }
    }

    # 3. Clean working directories only if DISM mounts are confirmed clear
    if (-not $NonInteractive -and -not $isoCreatedSuccessfully -and -not $DryRun) {
        try { Read-Host "Press Enter to finalize cleanup." } catch {}
    }

    if ($canSafelyClean) {
        if ($isoCreatedSuccessfully) {
            if ($nano11Dir -and (Test-Path -LiteralPath $nano11Dir)) {
                try {
                    Reset-DirectoryWithRobocopy -Path $nano11Dir
                    Remove-Item -LiteralPath $nano11Dir -Force -ErrorAction SilentlyContinue
                } catch {}
            }
            foreach ($mPath in $allTargetMounts) {
                if (Test-Path -LiteralPath $mPath) {
                    try {
                        Reset-DirectoryWithRobocopy -Path $mPath
                        Remove-Item -LiteralPath $mPath -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
            }
        } else {
            if ($nano11Dir -and (Test-Path -LiteralPath $nano11Dir)) {
                Write-Host "Preserving $nano11Dir for inspection." -ForegroundColor Yellow
            }
            Write-Host "Preserving workspace mount directories for inspection." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Preserving workspace directories due to unresolved mount state." -ForegroundColor Yellow
    }

    # 4. Detach and remove VHDX scratch disk if initialized
    if ($canSafelyClean -and ($script:IsVhdxMounted -or ($vhdxPath -and (Test-Path -LiteralPath $vhdxPath)))) {
        try {
            Write-Host "Detaching VHDX scratch disk..." -ForegroundColor Cyan
            $dpDetachScript = "select vdisk file=`"$vhdxPath`"`r`ndetach vdisk`r`n"
            $dpDetachFile = Join-Path -Path $env:TEMP -ChildPath "nano11_dp_detach_$([System.IO.Path]::GetRandomFileName()).txt"
            $dpDetachScript | Set-Content -LiteralPath $dpDetachFile -Encoding ascii
            & diskpart.exe /s $dpDetachFile > $null 2>&1
            Remove-Item -LiteralPath $dpDetachFile -Force -ErrorAction SilentlyContinue

            $vhdxDetached = $true
            try {
                $diskImg = Get-DiskImage -ImagePath $vhdxPath -ErrorAction Stop
                if ($diskImg.Attached) { $vhdxDetached = $false }
            } catch {}

            if ($vhdxDetached) {
                if ($vhdxMountDir -and (Test-Path -LiteralPath $vhdxMountDir)) {
                    $rpCheck = Get-Item -LiteralPath $vhdxMountDir -Force -ErrorAction SilentlyContinue
                    if ($rpCheck -and ($rpCheck.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        try { & mountvol.exe "$vhdxMountDir" /D > $null 2>&1 } catch {}
                        try {
                            [System.IO.Directory]::Delete($vhdxMountDir, $false)
                        } catch {
                            try { $rpCheck.Delete() } catch {}
                        }
                    } else {
                        Reset-DirectoryWithRobocopy -Path $vhdxMountDir
                        Remove-Item -LiteralPath $vhdxMountDir -Force -ErrorAction SilentlyContinue
                    }
                }
                Remove-Item -LiteralPath $vhdxPath -Force -ErrorAction SilentlyContinue
                $script:IsVhdxMounted = $false
            } else {
                Write-Warning "Could not confirm VHDX detachment for '$vhdxPath'. Preserving VHDX and mount directory for safety."
            }
        } catch {
            Write-Warning "VHDX detachment encountered error: $_"
        }
    } elseif (-not $canSafelyClean -and ($script:IsVhdxMounted -or ($vhdxPath -and (Test-Path -LiteralPath $vhdxPath)))) {
        Write-Warning "Preserving VHDX scratch disk ('$vhdxPath') due to unresolved mount or registry hive locks."
    }

    # 5. Dismount source ISO if mounted by nano11
    if ($script:MountedIso) {
        Write-Host "Dismounting source Windows 11 ISO..." -ForegroundColor Cyan
        try {
            Dismount-DiskImage -ImagePath $script:MountedIso.ImagePath -ErrorAction SilentlyContinue > $null
            $script:MountedIso = $null
        } catch {}
    }

    # 6. Remove Windows Defender temporary workspace exclusion
    if ($script:DefenderExclusionAdded -and $baseWorkDir) {
        try {
            Remove-MpPreference -ExclusionPath $baseWorkDir -ErrorAction SilentlyContinue
            $script:DefenderExclusionAdded = $false
        } catch {}
    }

    # 7. Build elapsed time and policy stats
    if ($script:buildStopwatch) {
        $script:buildStopwatch.Stop()
        $elapsedSec = [math]::Round($script:buildStopwatch.Elapsed.TotalSeconds, 1)
        Write-Host "Build lifecycle completed in $elapsedSec seconds." -ForegroundColor Cyan
    }
    if ($script:AppliedPolicies) {
        Write-Host "Offline registry policies applied: $($script:AppliedPolicies.Count)" -ForegroundColor Cyan
    }

    if ($transcriptPath) {
        Stop-Transcript
    }

    # 8. Release global mutex guard
    if ($script:BuildMutex) {
        try {
            $script:BuildMutex.ReleaseMutex()
            $script:BuildMutex.Dispose()
            $script:BuildMutex = $null
        } catch {}
    }

    if ($isoCreatedSuccessfully) {
        Write-Host "Done! nano11.iso is ready." -ForegroundColor Green
    } else {
        $statusMsg = if ($LASTEXITCODE -ne 0) { "with errors" } else { "cleanly" }
        $statusColor = if ($LASTEXITCODE -ne 0) { "Red" } else { "Yellow" }
        Write-Host "Process ended $statusMsg. Please check the logs in $transcriptPath" -ForegroundColor $statusColor
    }
}
