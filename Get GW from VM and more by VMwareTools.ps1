
$vm = Get-VM -Name 'XXXXXXX'

$subnetmask = @()

$row = "" | Select Name,Host,OS,NicType,VLAN,IP,Gateway,Subnetmask,DNS

$row.Name = $vm.Name

$row.Host = $vm.VMHost.Name

$row.OS = $vm.Guest.OSFullName

$row.NicType = [string]::Join(',',(Get-NetworkAdapter -Vm $vm | Select -ExpandProperty Type))

$row.VLAN = [string]::Join(',',((Get-VirtualPortGroup -VM $vm ).Name))

$row.IP = [string]::Join(',',$vm.Guest.IPAddress)

$row.Gateway = $vm.ExtensionData.Guest.IpStack.IpRouteConfig.IpRoute.Gateway.IpAddress | where {$_ -ne $null}

foreach ($iproute in $vm.ExtensionData.Guest.IpStack.IpRouteConfig.IpRoute) {

    if (($vm.Guest.IPAddress -replace "[0-9]$|[1-9][0-9]$|1[0-9][0-9]$|2[0-4][0-9]$|25[0-5]$", "0" | select -uniq) -contains $iproute.Network) {

        $subnetmask += $iproute.Network + "/" + $iproute.PrefixLength

    }

}

$row.Subnetmask = [string]::Join(',',($subnetmask))

$row.DNS = [string]::Join(',',($vm.ExtensionData.Guest.IpStack.DnsConfig.IpAddress))

$row
