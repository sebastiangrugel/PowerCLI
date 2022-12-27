### Migration VMs
  Get-HCXMigration | select vm,name,percentage,BytesTransferred,starttime,endtime,state | Sort-Object endtime | Where-Object {$_.state -eq "MIGRATED"} | ft
  Get-HCXMigration | select vm,name,percentage,BytesTransferred,starttime,endtime,state | Sort-Object Percentage,state | Where-Object {$_.state -ne "MIGRATED"} | ft

  Get-HCXMigration | select vm,state,name,starttime,endtime | Sort-Object endtime | Where-Object {($_.state -eq "MIGRATED") -and ($_.endtime -like "23")} | ft
  
  Get-HCXMigration | select vm,state,name,endtime | Sort-Object endtime | Where-Object {($_.endtime -like "*12/23/2022*")} | ft


### HCX NETWORK EXTENSION STATUS

Get-HCXNetworkExtension | select Network,GatewayIp,Netmask,Destination,DestinationGateway,DestinationNetwork,EgressOptimization,ProximityRouting,status,source,appliance | ft
Get-HCXNetworkExtension | select Network


###
Get-HCXMobilityGroup -Name XXXXXXXXXXX | Get-HCXMigration

### No output
Get-HCXReplication



### VM controllers and RDM discovery + not supported capacity
$vm = "XXXXXXXXX"

### How to find iSCSI with physical mode
get-vm $vm | Get-HardDisk | Get-ScsiController | select parent,name,type,BusSharingMode

### How to find RDM disk + wrong capacity
get-vm $vm | Get-HardDisk | select parent,name,Filename,DiskType,Persistence,StorageFormat,Devicename,ScsiCanonicalName,CapacityGB | ft


#############################################################################################################################################


