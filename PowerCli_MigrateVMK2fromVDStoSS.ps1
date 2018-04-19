#source: https://www.virtuallyghetto.com/2013/11/automate-reverse-migrating-from-vsphere.html

# ESXi hosts to migrate from VSS-&gt;VDS
$vmhost_array = @("esxi1.local","esxi2.local",)
 
# VDS to migrate from
$vds_name = "DVswitch01-A"
$vds = Get-VDSwitch -Name $vds_name
 
# VSS to migrate to
$vss_name = "vSwitch0"
 
# Name of portgroups to create on VSS
$vmotion_name = "vMotion Network"
 
foreach ($vmhost in $vmhost_array) {
Write-Host "`nProcessing" $vmhost
 
# pNICs to migrate to VSS
Write-Host "Retrieving pNIC info for vmnic0,vmnic1,vmnic2,vmnic3"
$vmnic0 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic0"
$vmnic1 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic1"
$vmnic2 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic2"
$vmnic3 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic3"
 
# Array of pNICs to migrate to VSS
Write-Host "Creating pNIC array"
$pnic_array = @($vmnic0,$vmnic1,$vmnic2,$vmnic3)
 
# vSwitch to migrate to
$vss = Get-VMHost -Name $vmhost | Get-VirtualSwitch -Name $vss_name
 
# Create destination portgroups
Write-Host "`Creating" $vmotion_name "portrgroup on" $vss_name
$vmotion_pg = New-VirtualPortGroup -VirtualSwitch $vss -Name $vmotion_name
 
# Array of portgroups to map VMkernel interfaces (order matters!)
Write-Host "Creating portgroup array"
$pg_array = @($vmotion_pg)
 
# VMkernel interfaces to migrate to VSS
Write-Host "`Retrieving VMkernel interface details for vmk2"
$vmotion_vmk = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmk2"
 
# Array of VMkernel interfaces to migrate to VSS (order matters!)
Write-Host "Creating VMkernel interface array"
$vmk_array = @($vmotion_vmk)
 
# Perform the migration
Write-Host "Migrating from" $vds_name "to" $vss_name"`n"
Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $vss -VMHostPhysicalNic $pnic_array -VMHostVirtualNic $vmk_array -VirtualNicPortgroup $pg_array  -Confirm:$false
}
 
Write-Host "`nRemoving" $vmhost_array "from" $vds_name
$vds | Remove-VDSwitchVMHost -VMHost $vmhost_array -Confirm:$false
 
Disconnect-VIServer -Server $global:DefaultVIServers -Force -Confirm:$false