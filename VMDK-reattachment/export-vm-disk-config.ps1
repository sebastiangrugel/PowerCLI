param(
    [Parameter(Mandatory=$true)] [string]$vmName,
    [Parameter(Mandatory=$false)][string]$outputCsvPath    = ".\reattaching-vmdk-configuration.csv",
    [Parameter(Mandatory=$false)][bool]  $excludeBootDisk  = $true
)

# Resolve output path: \filename.csv (root-relative, no drive letter) is treated
# by PowerShell as E:\filename.csv — reanchor it to the current working directory.
if ($outputCsvPath -match '^[/\\][^/\\]') {
    $outputCsvPath = Join-Path (Get-Location).Path $outputCsvPath.TrimStart('/\')
}

# Resolve VM
$vm = Get-VM -Name $vmName -ErrorAction Stop
Write-Host "`nVM        : $($vm.Name)  |  Power: $($vm.PowerState)" -ForegroundColor Cyan
Write-Host "Output    : $outputCsvPath" -ForegroundColor Cyan
Write-Host "Boot disk : $(if ($excludeBootDisk) { 'excluded (SCSI0:0)' } else { 'included' })" -ForegroundColor Cyan

# Fetch all disks and sort by controller then unit
$disks = Get-HardDisk -VM $vm |
    Sort-Object { $_.ExtensionData.ControllerKey }, { $_.ExtensionData.UnitNumber }

if (-not $disks) {
    Write-Warning "No disks found on $vmName."
    exit 0
}

# Preview table
Write-Host "`n  Disk inventory on $($vm.Name):" -ForegroundColor Yellow
$disks | Select-Object Name, CapacityGB,
    @{N="SCSI Bus"; E={ $_.ExtensionData.ControllerKey - 1000 }},
    @{N="Unit";     E={ $_.ExtensionData.UnitNumber }},
    @{N="Include";  E={
        $bus  = $_.ExtensionData.ControllerKey - 1000
        $unit = $_.ExtensionData.UnitNumber
        if ($excludeBootDisk -and $bus -eq 0 -and $unit -eq 0) { "SKIP (boot)" } else { "YES" }
    }},
    @{N="UUID";     E={ $_.ExtensionData.Backing.Uuid }},
    Filename |
    Format-Table -AutoSize

# Build CSV rows
$rows    = [System.Collections.Generic.List[PSCustomObject]]::new()
$skipped = 0

foreach ($disk in $disks) {
    $bus  = $disk.ExtensionData.ControllerKey - 1000
    $unit = $disk.ExtensionData.UnitNumber

    if ($excludeBootDisk -and $bus -eq 0 -and $unit -eq 0) {
        $skipped++
        continue
    }

    $rows.Add([PSCustomObject]@{
        'Source VM vSphere Controller' = $bus
        'Source VM vSphere UNIT'       = $unit
        'Target VM vSphere Controller' = $bus
        'Target VM vSphere UNIT'       = $unit
    })
}

if ($rows.Count -eq 0) {
    Write-Warning "No disks to export after applying exclusions."
    exit 0
}

# Write CSV
$rows | Export-Csv -Path $outputCsvPath -NoTypeInformation -Force

Write-Host "  Exported : $($rows.Count) disk(s)" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "  Skipped  : $skipped disk(s) (boot disk excluded)" -ForegroundColor DarkGray
}
$resolvedCsvPath = (Resolve-Path $outputCsvPath).Path
Write-Host "  CSV path : $resolvedCsvPath" -ForegroundColor Green

Write-Host "`n  Use with:" -ForegroundColor DarkGray
Write-Host "    .\reattaching-vmdk-v2.ps1 -source $vmName -target <targetVM> -csvPath `"$resolvedCsvPath`"" -ForegroundColor DarkGray
Write-Host ""
