#Wpisujemy liste hostów z którą chcemy sią połączyć
$esxihosts=(
    "esxi01.akademiadatacenter.pl",
	"esxi02.akademiadatacenter.pl",
	"esxi03.akademiadatacenter.pl",
	"esxi04.akademiadatacenter.pl"
			)

$esxihostuser="root"
#Do uzupelnienia (przy zalożeniu że ESXi mają takie same haslo)
$esxihostpasswd="HASLODOESXi"

#Pętla, lączenie się do hostów w kolejności z listy powyżej
foreach ($esxihost in $esxihosts) {

write-host "Start connection to ESXi host" $esxihost -foreground green
#Lączenie do ESXi
Connect-VIServer -Server $esxihost -user $esxihostuser -password $esxihostpasswd

write-host "Start backup ESXi host" $esxihost -foreground green
#Zapisanie na lokalnym dysku kopi zapasowaj z konkretnego hosta
Get-VMHostFirmware -VMHost $esxihost -BackupConfiguration -DestinationPath D:\

#Rozlączenie wszystkich polączeń
write-host "Disconnect" $esxihost -foreground green
Disconnect-VIServer * -confirm:$false
}