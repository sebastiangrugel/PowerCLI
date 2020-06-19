# Sebastian Grugel
# Skrypt do sprawdzania nazwy maszyny wirtualnej z vCD i wskazywania jej w punktu widzenia vCentra.
# W wersji Flashowej klienta można było to sprawdzac w GUI. Na tą chwilę 19.06.2020 nie widzę tej opcji w tenan cliencie.
# Musimy przez byc zalogowani przez powercli jednoczesnie do vCD i vCenter
# 

# Pole do wprowadzenia nazwy maszyny z vCD
$vcd_vmname = "MGMT Server"

# Poniżej nic nie edytować
$vcd_vm_id = (get-civm $vcd_vmname ).ExtensionData.environment.anyattr | findstr vm
$vcd_vm_id
$vc_vm = (get-vm -ID VirtualMachine-$vcd_vm_id).name
$vc_vm
