while ($true) {
  #Get-HCXMigration | select vm,state,name,percentage,BytesTransferred,starttime,endtime | Sort-Object endtime | Where-Object {$_.state -eq "MIGRATED"} | ft
  #Get-HCXMigration | select vm,state,name,percentage,BytesTransferred,starttime,endtime | Sort-Object Percentage,state | Where-Object {$_.state -ne "MIGRATED"} | ft
  
  #Get-HCXMigration | select vm,state,name,starttime,endtime | Sort-Object endtime | Where-Object {$_.state -eq "MIGRATED"} | ft
  #Get-HCXMigration | select vm,state,name,starttime,endtime | Sort-Object state | Where-Object {$_.state -ne "MIGRATED"} | ft

   
  Write-host "##### Virtual Machines waiting for SWITCHOVER"
  Get-HCXMigration | select vm,state,name,endtime | Sort-Object vm | Where-Object {$_.state -eq "parked"} | ft

  Write-host "##### Virtual Machines during SWITCHOVER"
  Get-HCXMigration | select vm,state,name,endtime | Where-Object {$_.state -eq "switchover_started"} | ft
  
  Write-Host "#### Virtual Machines MIGRATED today"
  Get-HCXMigration | select vm,state,name,endtime | Sort-Object endtime | Where-Object {($_.endtime -like "*12/23/2022*")} | ft
  
  Write-host "##### Virtual Machines with ERRORS not only today"
  Get-HCXMigration | select vm,state,name,endtime | Sort-Object state | Where-Object {$_.state -eq "ERROR"} | ft

  Start-Sleep -Seconds 60
  #clear
}
