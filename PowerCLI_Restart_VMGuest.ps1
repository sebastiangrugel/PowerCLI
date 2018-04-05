$servers = Get-Content d:\a545632\vmr2.txt
foreach ($s in $servers) {
Write-Host Initiating Reboot for $s
Restart-VMGuest $s -Confirm:$False
Get-VIEvent -Entity $s -MaxSamples 1 | select FullFormattedMessage, CreatedTime


}