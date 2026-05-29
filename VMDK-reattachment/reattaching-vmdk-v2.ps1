param(
    [Parameter(Mandatory=$true)][string]$source,
    [Parameter(Mandatory=$true)][string]$target,
    [Parameter(Mandatory=$true)][string]$csvPath
)

#region Helper Functions

function New-ScsiControllerOnVM {
    param(
        $VM,
        [int]$BusNumber,
        [string]$ControllerType = "ParaVirtualSCSIController"
    )
    Write-Host "  Creating SCSI controller BusNumber=$BusNumber ($ControllerType) on $($VM.Name)..." -ForegroundColor Cyan

    $vmView = $VM | Get-View

    $ctrlSpec = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $ctrlSpec.Operation = [VMware.Vim.VirtualDeviceConfigSpecOperation]::add

    $ctrl = New-Object "VMware.Vim.$ControllerType"
    $ctrl.Key = -1
    $ctrl.BusNumber = $BusNumber
    $ctrl.SharedBus = [VMware.Vim.VirtualSCSISharing]::noSharing

    $ctrlSpec.Device = $ctrl

    $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $vmConfigSpec.DeviceChange = @($ctrlSpec)

    $task = $vmView.ReconfigVM_Task($vmConfigSpec)
    $null = Get-Task -Id ("Task-" + $task.Value) | Wait-Task
    Write-Host "    -> Done." -ForegroundColor Green
}

function Show-VMInfo {
    param([string]$VMName)

    $vmView = (Get-VM -Name $VMName) | Get-View

    Write-Host "`n  SCSI Controllers on $VMName`:" -ForegroundColor Yellow
    $controllers = $vmView.Config.Hardware.Device | Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] }
    if ($controllers) {
        $controllers |
            Select-Object @{N="Name";          E={ "SCSI controller $($_.BusNumber)" }},
                          @{N="Type";          E={ $_.GetType().Name }},
                          @{N="BusNumber";     E={ $_.BusNumber }},
                          @{N="ControllerKey"; E={ $_.Key }} |
            Sort-Object BusNumber |
            Format-Table -AutoSize
    } else {
        Write-Host "  (none)" -ForegroundColor Gray
    }

    Write-Host "  Attached Disks on $VMName`:" -ForegroundColor Yellow
    $disks = Get-HardDisk -VM (Get-VM -Name $VMName)
    if ($disks) {
        $disks |
            Select-Object Name, CapacityGB,
                @{N="SCSI Bus";     E={ $_.ExtensionData.ControllerKey - 1000 }},
                @{N="ControllerKey";E={ $_.ExtensionData.ControllerKey }},
                @{N="Unit";         E={ $_.ExtensionData.UnitNumber }},
                @{N="UUID";         E={ $_.ExtensionData.Backing.Uuid }},
                Filename |
            Sort-Object ControllerKey, Unit |
            Format-Table -AutoSize
    } else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
}

function Add-ExistingDiskToVM {
    param(
        $VM,
        [string]$DiskPath,
        [int]$ControllerKey,
        [int]$UnitNumber
    )
    $vmView = $VM | Get-View

    $backing = New-Object VMware.Vim.VirtualDiskFlatVer2BackingInfo
    $backing.FileName = $DiskPath
    $backing.DiskMode = "persistent"

    $disk = New-Object VMware.Vim.VirtualDisk
    $disk.Key = -1
    $disk.ControllerKey = $ControllerKey
    $disk.UnitNumber = $UnitNumber
    $disk.CapacityInKB = 0
    $disk.Backing = $backing

    $diskSpec = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $diskSpec.Operation = [VMware.Vim.VirtualDeviceConfigSpecOperation]::add
    $diskSpec.Device = $disk

    $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $vmConfigSpec.DeviceChange = @($diskSpec)

    $task = $vmView.ReconfigVM_Task($vmConfigSpec)
    $null = Get-Task -Id ("Task-" + $task.Value) | Wait-Task
}

#endregion

# Logging — capture all console output to /log/log_YYYYMMDD_HHmmss.log
$logDir = Join-Path $PSScriptRoot "log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Start-Transcript -Path $logFile -NoClobber
$startTime = Get-Date
Write-Host "Log  : $logFile" -ForegroundColor DarkGray

# Validate input
if (-not (Test-Path $csvPath)) {
    Write-Error "Input CSV not found: $csvPath"
    Stop-Transcript
    exit 1
}

# Resolve VMs
Write-Host "Resolving VMs..." -ForegroundColor Cyan
$sourceVM = Get-VM -Name $source -ErrorAction Stop
$targetVM = Get-VM -Name $target -ErrorAction Stop
Write-Host "  Source : $($sourceVM.Name)" -ForegroundColor Green
Write-Host "  Target : $($targetVM.Name)" -ForegroundColor Green

$config = Import-Csv -Path $csvPath

# Pre-run validation snapshot
Write-Host "`n=== Pre-run State ===" -ForegroundColor Magenta
foreach ($vmName in @($source, $target)) { Show-VMInfo -VMName $vmName }

Write-Host "  Planned mappings from CSV:" -ForegroundColor Yellow
$config |
    Select-Object `
        @{N="Source Controller"; E={ $_.'Source VM vSphere Controller' }},
        @{N="Source Unit";       E={ $_.'Source VM vSphere UNIT' }},
        @{N="Target Controller"; E={ $_.'Target VM vSphere Controller' }},
        @{N="Target Unit";       E={ $_.'Target VM vSphere UNIT' }} |
    Format-Table -AutoSize

$confirm = Read-Host "Proceed with disk migration? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Aborted by user." -ForegroundColor Red
    Stop-Transcript
    exit 0
}

# Snapshot source controller types before any changes — needed to recreate them after vSphere auto-removes empty controllers
$sourceControllerMap = @{}
(Get-VM -Name $source | Get-View).Config.Hardware.Device |
    Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] } |
    ForEach-Object { $sourceControllerMap[$_.BusNumber] = $_.GetType().Name }

# Determine unique SCSI controllers required on target
$requiredBusNumbers = $config |
    ForEach-Object { [int]$_.'Target VM vSphere Controller' } |
    Sort-Object -Unique

Write-Host "`nRequired SCSI controllers on target: $($requiredBusNumbers -join ', ')" -ForegroundColor Cyan

# Create missing SCSI controllers on target
foreach ($busNum in $requiredBusNumbers) {
    $targetVM = Get-VM -Name $target
    $vmView = $targetVM | Get-View
    $existing = $vmView.Config.Hardware.Device |
        Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] -and $_.BusNumber -eq $busNum }

    if ($existing) {
        Write-Host "  SCSI controller BusNumber=$busNum already present on $target." -ForegroundColor Yellow
    } else {
        New-ScsiControllerOnVM -VM $targetVM -BusNumber $busNum
    }
}

# Process each disk mapping row
Write-Host "`nProcessing disk mappings..." -ForegroundColor Cyan

foreach ($row in $config) {
    $srcBus  = [int]$row.'Source VM vSphere Controller'
    $srcUnit = [int]$row.'Source VM vSphere UNIT'
    $tgtBus  = [int]$row.'Target VM vSphere Controller'
    $tgtUnit = [int]$row.'Target VM vSphere UNIT'

    $srcCtrlKey = 1000 + $srcBus
    $tgtCtrlKey = 1000 + $tgtBus

    Write-Host "  [$source SCSI$srcBus`:$srcUnit] -> [$target SCSI$tgtBus`:$tgtUnit]" -ForegroundColor Yellow

    # Locate disk on source
    $sourceVM = Get-VM -Name $source
    $disk = Get-HardDisk -VM $sourceVM |
        Where-Object { $_.ExtensionData.UnitNumber -eq $srcUnit -and $_.ExtensionData.ControllerKey -eq $srcCtrlKey }

    if (-not $disk) {
        Write-Warning "    Disk not found at SCSI$srcBus`:$srcUnit on $source — skipping."
        continue
    }

    $diskPath = $disk.Filename
    Write-Host "    Path : $diskPath ($([math]::Round($disk.CapacityGB,1)) GB)" -ForegroundColor Gray

    # Detach from source (non-destructive)
    Write-Host "    Detaching from $source..." -ForegroundColor Gray
    $disk | Remove-HardDisk -DeletePermanently:$false -Confirm:$false

    # Attach to target at specified controller and unit
    Write-Host "    Attaching to $target at SCSI$tgtBus`:$tgtUnit..." -ForegroundColor Gray
    $targetVM = Get-VM -Name $target
    Add-ExistingDiskToVM -VM $targetVM -DiskPath $diskPath -ControllerKey $tgtCtrlKey -UnitNumber $tgtUnit
    Write-Host "    OK." -ForegroundColor Green
}

# Restore SCSI controllers on source that vSphere auto-removed when their last disk was detached
Write-Host "`nRestoring vacated SCSI controllers on source ($source)..." -ForegroundColor Cyan

$sourceBusNumbers = $config |
    ForEach-Object { [int]$_.'Source VM vSphere Controller' } |
    Sort-Object -Unique

foreach ($busNum in $sourceBusNumbers) {
    $sourceVM = Get-VM -Name $source
    $vmView = $sourceVM | Get-View
    $existing = $vmView.Config.Hardware.Device |
        Where-Object { $_ -is [VMware.Vim.VirtualSCSIController] -and $_.BusNumber -eq $busNum }

    if ($existing) {
        Write-Host "  SCSI controller BusNumber=$busNum still present on $source." -ForegroundColor Yellow
    } else {
        $ctrlType = if ($sourceControllerMap.ContainsKey($busNum)) { $sourceControllerMap[$busNum] } else { "ParaVirtualSCSIController" }
        Write-Host "  BusNumber=$busNum was auto-removed — recreating as $ctrlType..." -ForegroundColor Yellow
        New-ScsiControllerOnVM -VM $sourceVM -BusNumber $busNum -ControllerType $ctrlType
    }
}

# Post-run validation summary
Write-Host "`n=== Post-run State ===" -ForegroundColor Magenta
foreach ($vmName in @($source, $target)) { Show-VMInfo -VMName $vmName }

$elapsed = (Get-Date) - $startTime
Write-Host ("`nCompleted in {0} min {1} sec." -f $elapsed.Minutes, $elapsed.Seconds) -ForegroundColor Cyan

Stop-Transcript
