# source: http://www.enterprisedaddy.com/2018/04/how-to-execute-script-remotely-on-esxi-hosts/

$root = "root" 
$Passwd = Get-Content "C:\data\Security\1.txt"

#Pobiera liste ESXi
$esxlist=@(
"esxi1.akademiadatacenter.pl"
)

#Komendy jakie chcemy wykonać na ESXi
$cmd = "esxcli system wbem get | grep Enabled: && chkconfig --list | grep sfcbd-watchdog"
#$cmd = "esxcli system wbem set --enable false && chkconfig sfcbd-watchdog off"

$plink = "echo y | C:\data\APP\plink.exe"
$remoteCommand = '"' + $cmd + '"'

foreach ($esx in $esxlist) {
Write-Host -Object "Connecting to $esx" -foreground green
Connect-VIServer $esx -User  $root -Password $Passwd

#Weryfikacja czy SSH jest włączone
Write-Host -Object "starting ssh services on $esx"
$sshstatus= Get-VMHostService  -VMHost $esx| where {$psitem.key -eq "tsm-ssh"}
if ($sshstatus.Running -eq $False) {
Get-VMHostService | where {$psitem.key -eq "tsm-ssh"} | Start-VMHostService }

#Wysłanie komendy do ESXi
Write-Host -Object "Executing Command on $esx" -foreground green
$output = $plink + " " + "-ssh" + " " + $root + "@" + $esx + " " + "-pw" + " " + $Passwd + " " + $remoteCommand

$message = Invoke-Expression -command $output
$message
Disconnect-VIServer * -Confirm:$false
}
