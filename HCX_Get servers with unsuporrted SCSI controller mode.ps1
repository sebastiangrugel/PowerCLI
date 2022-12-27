"vm1",
"vm2"
)

Write-Host "Liczba serwerów" $migrationGroup.count


#foreach ($server in $migrationGroup) {
#get-vm $server | Get-HardDisk | select parent,name,capacityGB 
#}

$vms=foreach ($server in get-vm $migrationGroup ) {$server| Get-HardDisk | Get-ScsiController | select parent,name,type,BusSharingMode } ; 
#$vms  | ft -a >> vms_scsi_all_v1.csv
$vms  | ft -a
