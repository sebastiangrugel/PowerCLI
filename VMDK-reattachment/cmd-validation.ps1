param(
    [Parameter(Mandatory=$false)][string]$vmA     = "VM-PROD01",
    [Parameter(Mandatory=$false)][string]$vmB     = "VM-DR01",
    [Parameter(Mandatory=$false)][string]$csvPath = ".\reattaching-vmdk-configuration.csv"
)

$CHK  = "[OK]"
$FAIL = "[!!]"
$WARN = "[??]"

function Write-Check {
    param([string]$Line, [string]$Status)
    switch ($Status) {
        $CHK  { Write-Host $Line -ForegroundColor Green  }
        $FAIL { Write-Host $Line -ForegroundColor Red    }
        $WARN { Write-Host $Line -ForegroundColor Yellow }
        default { Write-Host $Line }
    }
}

function Write-SectionHeader {
    param([string]$Title)
    $pad = "=" * (([Math]::Max(0, 90 - $Title.Length - 4)) / 2)
    Write-Host "`n$pad  $Title  $pad" -ForegroundColor Cyan
}

# ── Resolve VMs ──────────────────────────────────────────────────────────────
$vmObjA = Get-VM -Name $vmA -ErrorAction SilentlyContinue
$vmObjB = Get-VM -Name $vmB -ErrorAction SilentlyContinue

if (-not $vmObjA) { Write-Error "VM '$vmA' not found."; exit 1 }
if (-not $vmObjB) { Write-Error "VM '$vmB' not found."; exit 1 }

Write-Host "`nReference : $($vmObjA.Name)  |  Power: $($vmObjA.PowerState)" -ForegroundColor White
Write-Host "Check VM  : $($vmObjB.Name)  |  Power: $($vmObjB.PowerState)" -ForegroundColor White

# ── Fetch hardware ────────────────────────────────────────────────────────────
$viewA   = $vmObjA | Get-View
$viewB   = $vmObjB | Get-View
$disksA  = Get-HardDisk -VM $vmObjA
$disksB  = Get-HardDisk -VM $vmObjB

$ctrlA   = $viewA.Config.Hardware.Device | Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] }
$ctrlB   = $viewB.Config.Hardware.Device | Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] }

# Lookup tables
$ctrlMapA = @{}; $ctrlA | ForEach-Object { $ctrlMapA[$_.BusNumber] = $_ }
$ctrlMapB = @{}; $ctrlB | ForEach-Object { $ctrlMapB[$_.BusNumber] = $_ }

$diskMapA = @{}
$disksA | ForEach-Object {
    $key = "$($_.ExtensionData.ControllerKey):$($_.ExtensionData.UnitNumber)"
    $diskMapA[$key] = $_
}
$diskMapB = @{}
$disksB | ForEach-Object {
    $key = "$($_.ExtensionData.ControllerKey):$($_.ExtensionData.UnitNumber)"
    $diskMapB[$key] = $_
}

$uuidMapA = @{}; $disksA | Where-Object { $_.ExtensionData.Backing.Uuid } |
    ForEach-Object { $uuidMapA[$_.ExtensionData.Backing.Uuid] = $_ }
$uuidMapB = @{}; $disksB | Where-Object { $_.ExtensionData.Backing.Uuid } |
    ForEach-Object { $uuidMapB[$_.ExtensionData.Backing.Uuid] = $_ }

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — SCSI Controller Comparison
# ══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "SCSI Controller Comparison"

$hdr = "  {0,-6}  {1,-34}  {2,-34}  {3}" -f "BUS", "$vmA (Reference)", "$vmB (Check)", "Result"
Write-Host $hdr -ForegroundColor DarkGray
Write-Host ("  " + "-" * 86) -ForegroundColor DarkGray

$allBus = ($ctrlMapA.Keys + $ctrlMapB.Keys) | Sort-Object -Unique
$ctrlPass = 0; $ctrlFail = 0

foreach ($bus in $allBus) {
    $typeA = if ($ctrlMapA.ContainsKey($bus)) { $ctrlMapA[$bus].GetType().Name } else { "(missing)" }
    $typeB = if ($ctrlMapB.ContainsKey($bus)) { $ctrlMapB[$bus].GetType().Name } else { "(missing)" }

    if ($ctrlMapA.ContainsKey($bus) -and $ctrlMapB.ContainsKey($bus) -and ($typeA -eq $typeB)) {
        $status = $CHK;  $ctrlPass++
    } elseif ($ctrlMapA.ContainsKey($bus) -and $ctrlMapB.ContainsKey($bus) -and ($typeA -ne $typeB)) {
        $status = $WARN; $ctrlFail++
    } else {
        $status = $FAIL; $ctrlFail++
    }

    $line = "  SCSI{0,-2}  {1,-34}  {2,-34}  {3}" -f $bus, $typeA, $typeB, $status
    Write-Check -Line $line -Status $status
}

Write-Host ("  " + "-" * 86) -ForegroundColor DarkGray
$ctrlSummary = "  Controllers: $ctrlPass passed, $ctrlFail failed"
if ($ctrlFail -eq 0) { Write-Host $ctrlSummary -ForegroundColor Green }
else                 { Write-Host $ctrlSummary -ForegroundColor Red   }

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — CSV Disk Mapping Validation
# ══════════════════════════════════════════════════════════════════════════════
if (-not (Test-Path $csvPath)) {
    Write-Host "`n  No CSV found at '$csvPath' — skipping disk mapping validation." -ForegroundColor DarkYellow
} else {
    $csvRows = Import-Csv -Path $csvPath
    Write-SectionHeader "Disk Mapping Validation  (CSV: $([System.IO.Path]::GetFileName($csvPath)))"

    $hdr = "  {0,-4}  {1,-10}  {2,-10}  {3,-38}  {4,-10}  {5,-10}  {6,-38}  {7}  {8}" -f `
        "#", "Src Pos", "Tgt Pos", "UUID @ Src ($vmA)", "Ctrl $CHK", "Disk $CHK", "UUID @ Tgt ($vmB)", "UUID", "Result"
    Write-Host $hdr -ForegroundColor DarkGray
    Write-Host ("  " + "-" * 148) -ForegroundColor DarkGray

    $diskPass = 0; $diskFail = 0
    $rowNum = 0

    foreach ($row in $csvRows) {
        $rowNum++
        $srcBus  = [int]$row.'Source VM vSphere Controller'
        $srcUnit = [int]$row.'Source VM vSphere UNIT'
        $tgtBus  = [int]$row.'Target VM vSphere Controller'
        $tgtUnit = [int]$row.'Target VM vSphere UNIT'

        $srcCtrlKey = 1000 + $srcBus
        $tgtCtrlKey = 1000 + $tgtBus
        $srcMapKey  = "${srcCtrlKey}:${srcUnit}"
        $tgtMapKey  = "${tgtCtrlKey}:${tgtUnit}"

        $diskOnA = $diskMapA[$srcMapKey]
        $diskOnB = $diskMapB[$tgtMapKey]

        $uuidA = if ($diskOnA) { $diskOnA.ExtensionData.Backing.Uuid } else { "(no disk at src)" }
        $uuidB = if ($diskOnB) { $diskOnB.ExtensionData.Backing.Uuid } else { "(no disk at tgt)" }

        $ctrlOk  = if ($ctrlMapB.ContainsKey($tgtBus)) { $CHK  } else { $FAIL }
        $diskOk  = if ($diskOnB)                        { $CHK  } else { $FAIL }
        $uuidOk  = if ($diskOnB -and $uuidA -ne "(no disk at src)" -and $uuidA -eq $uuidB) { $CHK }
                   elseif ($diskOnB -and $uuidA -eq "(no disk at src)")                    { $WARN }
                   else                                                                     { $FAIL }

        # Overall row result
        if ($ctrlOk -eq $CHK -and $diskOk -eq $CHK -and $uuidOk -ne $FAIL) {
            $overall = $CHK;  $diskPass++
        } else {
            $overall = $FAIL; $diskFail++
        }

        $srcPos  = "SCSI${srcBus}:${srcUnit}"
        $tgtPos  = "SCSI${tgtBus}:${tgtUnit}"
        $uuidAsh = if ($uuidA -match "^[0-9a-f]") { $uuidA.Substring(0,18) + "~" } else { $uuidA }
        $uuidBsh = if ($uuidB -match "^[0-9a-f]") { $uuidB.Substring(0,18) + "~" } else { $uuidB }

        $line = "  {0,-4}  {1,-10}  {2,-10}  {3,-38}  {4,-10}  {5,-10}  {6,-38}  {7,-6}  {8}" -f `
            $rowNum, $srcPos, $tgtPos, $uuidAsh, $ctrlOk, $diskOk, $uuidBsh, $uuidOk, $overall

        Write-Check -Line $line -Status $overall
    }

    Write-Host ("  " + "-" * 148) -ForegroundColor DarkGray
    $diskSummary = "  Disk mappings: $diskPass passed, $diskFail failed"
    if ($diskFail -eq 0) { Write-Host $diskSummary -ForegroundColor Green }
    else                 { Write-Host $diskSummary -ForegroundColor Red   }
}

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — UUID Cross-Reference (all disks on both VMs)
# ══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "UUID Cross-Reference"

$hdr = "  {0,-38}  {1,-12}  {2,-12}  {3,-40}  {4}" -f `
    "UUID", "$vmA Pos", "$vmB Pos", "Filename", "Location"
Write-Host $hdr -ForegroundColor DarkGray
Write-Host ("  " + "-" * 110) -ForegroundColor DarkGray

$allUUIDs = ($uuidMapA.Keys + $uuidMapB.Keys) | Sort-Object -Unique

foreach ($uuid in $allUUIDs) {
    $dA = $uuidMapA[$uuid]
    $dB = $uuidMapB[$uuid]

    $posA   = if ($dA) { "SCSI$($dA.ExtensionData.ControllerKey - 1000):$($dA.ExtensionData.UnitNumber)" } else { "-" }
    $posB   = if ($dB) { "SCSI$($dB.ExtensionData.ControllerKey - 1000):$($dB.ExtensionData.UnitNumber)" } else { "-" }
    $fname  = if ($dA) { [System.IO.Path]::GetFileName($dA.Filename) }
              elseif ($dB) { [System.IO.Path]::GetFileName($dB.Filename) }
              else { "-" }

    if ($dA -and $dB) {
        $loc    = "$WARN  Both VMs"
        $color  = "Yellow"
    } elseif ($dA) {
        $loc    = "  $vmA only"
        $color  = "White"
    } else {
        $loc    = "  $vmB only"
        $color  = "White"
    }

    $line = "  {0,-38}  {1,-12}  {2,-12}  {3,-40}  {4}" -f $uuid, $posA, $posB, $fname, $loc
    Write-Host $line -ForegroundColor $color
}

# ══════════════════════════════════════════════════════════════════════════════
# LEGEND
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n  Legend:  " -NoNewline
Write-Host "[OK] Pass  " -ForegroundColor Green -NoNewline
Write-Host "[!!] Fail  " -ForegroundColor Red -NoNewline
Write-Host "[??] Warning / check manually" -ForegroundColor Yellow
Write-Host ""
