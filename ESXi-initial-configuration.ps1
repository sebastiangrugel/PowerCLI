# Konfiguracja podstawowych parametrów 
$esx="ESXI.FQDN"
Add-VmHostNtpServer -VMHost $esx -NtpServer IP.IP.IP.IP
Get-VmHostService -VMHost $esx | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
Get-VmHostService -VMHost $esx | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "automatic"

Get-AdvancedSetting -Entity (Get-VMHost $esx) -Name Syslog.global.logDir | Set-AdvancedSetting -Value "[DATASTORENAME] LOGS"
Get-AdvancedSetting -Entity (Get-VMHost $esx) -Name Syslog.global.logHost | Set-AdvancedSetting -Value "udp://vrli:514"
Get-AdvancedSetting -Entity (Get-VMHost $esx)-Name Syslog.global.logDirUnique | Set-AdvancedSetting -Value $True -Confirm:$False



#Tworzenie VMkerneli (wczesniej przynajmniej trzeba dodac recznie albo innym skryptem do vDSa i ewentualnie zmigrowac vmk0 na MGMT)
$lastOctet = "3"
$myVMHost = Get-VMHost -Name "ESXI.FQDN"
$myVDSwitch = Get-VDSwitch -Name "DSwitch_AKADEMIADATACENTERPL"
$tmpIp = "10.91.6." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "AKADEMIADATACENTERPL_Management_Network_02" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true
$tmpIp = "192.168.11." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "AKADEMIADATACENTERPL_vMotion_01" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.252.0 -VMotionEnabled $true
$tmpIp = "192.168.21." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "AKADEMIADATACENTERPL_vMotion_02" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.252.0 -VMotionEnabled $true
$tmpIp = "192.168.31." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "AKADEMIADATACENTERPL_FT_01" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.255.0 -FaultToleranceLoggingEnabled $true
$tmpIp = "10.91.17." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "AKADEMIADATACENTERPL_Storage_nfs" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.255.0

$myVDSwitch = Get-VDSwitch -Name "DSwitch_iSCSI"
$tmpIp = "10.41.166." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "DPortGroup_iSCSI_1" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.254.0 -Mtu 9000
$tmpIp = "10.41.167." + $lastOctet
New-VMHostNetworkAdapter -VMHost $myVMHost -PortGroup "DPortGroup_iSCSI_2" -VirtualSwitch $myVDSwitch -IP $tmpIp -SubnetMask 255.255.254.0 -Mtu 9000