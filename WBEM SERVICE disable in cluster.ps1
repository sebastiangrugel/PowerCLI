# source: https://communities.vmware.com/thread/617936
# https://kb.vmware.com/s/article/74607

param (  
  [string]$clustername = $( Read-Host "Enter clustername" )  
  )  
  
$cluster = Get-Cluster -Name $clustername  
  
Get-VMHost -Location $cluster | %{  
  $esxcli = Get-EsxCli -VMHost $_ -V2  
  $esxcli.system.wbem.get.Invoke()          
  $esxcli.system.wbem.set.CreateArgs()  
  $esxcli.system.wbem.set.Invoke(@{enable=$false})  
  } 