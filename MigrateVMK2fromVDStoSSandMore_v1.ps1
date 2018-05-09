# Original script: https://www.virtuallyghetto.com/2013/11/automate-reverse-migrating-from-vsphere.html
# This version performing bellow actions:
# - create standard switch
# - create specific portgroups and specific VLANs
# - migrate specific physical nics
# - migrate specific vmk2 from vDS to standard switch
# - remove host from vDS
# - modified by: Sebastian Grugel

# ESXi hosts to migrate from VSS-&gt;VDS
$vmhost_array = @(
"esxhos01.alsdpc.local",
"esxhost02.alsdpc.local"
)
 
# VDS to migrate from
$vds_name = "vDS1"
$vds = Get-VDSwitch -Name $vds_name
 
# VSS to migrate to
$vss_name = "vSwitch1"
 
# Name of portgroups to create on VSS
$vmotion_name = "vMotion117"
$nondpcnetwork_name = "Client721"
 
foreach ($vmhost in $vmhost_array) {
Write-Host "`nProcessing" $vmhost
 
# pNICs to migrate to VSS (NICs which dont have # are moved to vSS)
Write-Host "Retrieving pNIC info for vmnic0,vmnic1,vmnic2,vmnic3"
#$vmnic0 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic0"
#$vmnic1 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic1"
$vmnic2 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic2"
$vmnic3 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name "vmnic3"
 
# Array of pNICs to migrate to VSS
Write-Host "Creating pNIC array"
$pnic_array = @($vmnic3,$vmnic2)

#Create Standard Switch
New-VirtualSwitch -VMHost $vmhost -Name $vss_name
 
# vSwitch to migrate to
$vss = Get-VMHost -Name $vmhost | Get-VirtualSwitch -Name $vss_name
 
# Create destination portgroups
Write-Host "`Creating" $vmotion_name "portrgroup on" $vss_name
$vmotion_pg = Get-VMHost $vmhost | Get-VirtualSwitch -name $vss_name | New-VirtualPortGroup -Name $vmotion_name -VLanId "117"
Write-Host "`Creating" $nondpcnetwork_name "portrgroup on" $vss_name
Get-VMHost $vmhost | Get-VirtualSwitch -name $vss_name | New-VirtualPortGroup -Name $nondpcnetwork_name -VLanId "721"
 
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

# Removing HOST from vDS 
Write-Host "`nRemoving" $vmhost_array "from" $vds_name
$vds | Remove-VDSwitchVMHost -VMHost $vmhost_array -Confirm:$false
 
# Disconnect-VIServer -Server $global:DefaultVIServers -Force -Confirm:$false
