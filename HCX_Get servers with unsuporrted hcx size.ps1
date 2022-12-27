$migrationGroup=@(
"vm1",
"vm1"
)

Write-Host "Liczba serwerów" $migrationGroup.count


#foreach ($server in $migrationGroup) {
#get-vm $server | Get-HardDisk | select parent,name,capacityGB 
#}

$vms=foreach ($server in get-vm $migrationGroup ) {$server| Get-HardDisk | select parent,name,capacityGB } ; 
#$vms  | ft -a >> vms_disk1_all_v1.csv
$vms  | ft -a
