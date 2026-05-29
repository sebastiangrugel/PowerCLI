param(
    [Parameter(Mandatory=$true)][string]$vmName,
    [Parameter(Mandatory=$true)][string]$datastore,
    [Parameter(Mandatory=$false)][int]$diskCount    = 15,
    [Parameter(Mandatory=$false)][float]$diskSizeGB = 1,
    [Parameter(Mandatory=$false)][string]$outputCsvPath = ".\reattaching-vmdk-configuration.csv"
)

# Resolve VM and existing controllers
$vm = Get-VM -Name $vmName -ErrorAction Stop
$controllers = $vm | Get-ScsiController
if (-not $controllers) {
    Write-Error "No SCSI controllers found on $vmName"
    exit 1
}

Write-Host "`nVM        : $($vm.Name)" -ForegroundColor Cyan
Write-Host "Datastore : $datastore" -ForegroundColor Cyan
Write-Host "Disks     : $diskCount x $diskSizeGB GB" -ForegroundColor Cyan

Write-Host "`nAvailable SCSI controllers:" -ForegroundColor Yellow
$controllers | Select-Object Name, Type,
    @{N="BusNumber"; E={ $_.ExtensionData.BusNumber }} |
    Format-Table -AutoSize

# Build a per-controller map of already-used unit numbers (unit 7 is always reserved)
$usedUnits = @{}
foreach ($ctrl in $controllers) {
    $usedUnits[$ctrl.ExtensionData.Key] = @(7)
}
Get-HardDisk -VM $vm | ForEach-Object {
    $key = $_.ExtensionData.ControllerKey
    if ($usedUnits.ContainsKey($key)) {
        $usedUnits[$key] += $_.ExtensionData.UnitNumber
    }
}

$csvRows    = [System.Collections.Generic.List[PSCustomObject]]::new()
$ctrlArray  = @($controllers)
$created    = 0

Write-Host "Creating $diskCount disks with random controller assignment..." -ForegroundColor Cyan

for ($i = 1; $i -le $diskCount; $i++) {
    # Shuffle controllers and pick the first one that still has a free slot
    $picked = $null
    $unit   = $null

    foreach ($ctrl in ($ctrlArray | Sort-Object { Get-Random })) {
        $available = (0..15) | Where-Object { $_ -notin $usedUnits[$ctrl.ExtensionData.Key] }
        if ($available.Count -gt 0) {
            $picked = $ctrl
            $unit   = $available | Get-Random
            break
        }
    }

    if (-not $picked) {
        Write-Warning "  All controllers are full — only $created of $diskCount disks created."
        break
    }

    $busNum = $picked.ExtensionData.BusNumber
    Write-Host "  Disk $i  ->  SCSI$busNum`:$unit" -ForegroundColor Yellow

    # Mark unit as reserved before creating (avoids collision if two picks land on same slot)
    $usedUnits[$picked.ExtensionData.Key] += $unit

    # Refresh VM object and create disk on the chosen controller
    $vm      = Get-VM -Name $vmName
    $newDisk = New-HardDisk -VM $vm -CapacityGB $diskSizeGB -Datastore $datastore `
                   -Controller (Get-VM -Name $vmName | Get-ScsiController |
                       Where-Object { $_.ExtensionData.BusNumber -eq $busNum }) `
                   -ErrorAction Stop

    $actualUnit = $newDisk.ExtensionData.UnitNumber
    $actualBus  = $newDisk.ExtensionData.ControllerKey - 1000

    Write-Host "    Created: SCSI$actualBus`:$actualUnit  |  $($newDisk.Filename)" -ForegroundColor Green

    $csvRows.Add([PSCustomObject]@{
        'Source VM vSphere Controller' = $actualBus
        'Source VM vSphere UNIT'       = $actualUnit
        'Target VM vSphere Controller' = $actualBus
        'Target VM vSphere UNIT'       = $actualUnit
    })
    $created++
}

# Summary table
Write-Host "`n=== Created Disks ===" -ForegroundColor Magenta
Get-HardDisk -VM (Get-VM -Name $vmName) |
    Select-Object Name, CapacityGB,
        @{N="SCSI Bus";     E={ $_.ExtensionData.ControllerKey - 1000 }},
        @{N="ControllerKey";E={ $_.ExtensionData.ControllerKey }},
        @{N="Unit";         E={ $_.ExtensionData.UnitNumber }},
        @{N="UUID";         E={ $_.ExtensionData.Backing.Uuid }},
        Filename |
    Sort-Object ControllerKey, Unit |
    Format-Table -AutoSize

# Export CSV for use with reattaching-vmdk-v2.ps1
$csvRows | Export-Csv -Path $outputCsvPath -NoTypeInformation
Write-Host "CSV written to : $outputCsvPath  ($created rows)" -ForegroundColor Cyan
Write-Host "Use with       : .\reattaching-vmdk-v2.ps1 -source $vmName -target <targetVM> -csvPath $outputCsvPath" -ForegroundColor Gray
