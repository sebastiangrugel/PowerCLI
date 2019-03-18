# Skrypt do Tworzenie dowolnej liczby maszyn wirtualnych i testowaniu vMotion pomiedzy hostami z góry w dół.

#Before start this script connect direct to vCenter by PowerCLI

#Nazwy hostow uzywane przy testach migracji
$esxihosts= Get-cluster *NAZWAKLASTRA* | Get-vmhost
#Liczba maszyn do stworzenia
$vm_count = "10"
# Nazwa klastra uzywana przy tworzeniu maszyn
$Cluster = "NAZWAKLASTRA"
# Nazwa prefixy maszyny
$VM_prefix = "SG-vMotionTest-"
# Array initialization
$VM_array= @()

########################################################################
# ETAP pierwszy to tworzenie maszyn wirtualnych


1..$vm_count | foreach {
$y="{0:D1}" -f + $_
$VM_name= $VM_prefix + $y
$ESXi=Get-Cluster $Cluster | Get-VMHost -state connected | Get-Random
write-host "Creation of VM $VM_name initiated"  -foreground green
New-VM -name $VM_name -VMHost $ESXi -numcpu 1 -MemoryMB 256 -DiskMB 256 -DiskStorageFormat Thin -Datastore 3PAR_CLOUD_01_GOLD
#New-VM -Name $VM_Name -VMHost $ESXi -numcpu $numcpu -MemoryMB $MBram -DiskMB $MBguestdisk -DiskStorageFormat $Typeguestdisk -Datastore $ds -GuestId $guestOS
$VM_array += $VM_name

write-host "Power On of the  VM $VM_name initiated"  -foreground green
Start-VM -VM $VM_name -confirm:$false -RunAsync
}
write-host "Stworzono" $VM_array -foreground green
write-host "Oczekiwano 15s na start VMek" $VM_array -foreground green
start-sleep -seconds 15

#########################################################################
# ETAP gdzie stworzone wczesniej maszyny wirtualne przenoszone są pomiedzy hostami od góry do dołu

write-host ————-
write-host Starting the vMotion process of VM $vm -ForegroundColor Green
foreach ($esxihost in (get-vmhost $esxihosts | ? { $_.ConnectionState -eq “Connected”} |sort))
{ 
    write-host "vMotion starting to "$esxihost -ForegroundColor Green
    foreach ($vm in $vm_array)
    {    
    write-host vMotion $vm starting to $esxihost -ForegroundColor Green
    Get-VM -Name $vm | Move-VM -Destination $esxihost | out-null
    }  
    
}
write-host "Oczekuje 15s na zakonczenie wszystkich vMotion"  -foreground yellow
start-sleep -seconds 15
write-host ————-
write-host The vMotion process is complete -foreground Green
write-host ————-
