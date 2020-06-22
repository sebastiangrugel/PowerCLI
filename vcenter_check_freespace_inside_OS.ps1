  Get-VM GwiazdaSmierci2-SG | ForEach-Object {
    $VM = $_
      $_.Guest.Disks | ForEach-Object {
        $Report = "" | Select-Object -Property VM,Path,Capacity,FreeSpace,PercentageFreeSpace
        $Report.VM = $VM.Name
        $Report.Path = $_.Path
        $Report.Capacity = $_.Capacity
        $Report.FreeSpace = $_.FreeSpace
        if ($_.Capacity) {$Report.PercentageFreeSpace = [math]::Round(100*($_.FreeSpace/$_.Capacity))}
        $Report | fl
      }
    }