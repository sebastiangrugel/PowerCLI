##################################################################
#
# Script monitoring NSX Manager and sending information about edges which dont have
# GREEN status in PowerCLI query
# Created by: Sebastian Grugel
# Created on: 11.03.2019
# Contact: sebastian.grugel@gmail.com
##################################################################


Connect-NsxServer -vcenterServer $env:vc -User $env:ciuser -Password $env:cipassword

#Dane do maila
$from = "no-reply@example.com"
$to = 'admin@exea.pl'
$smtpserver = "mail.example.com"
$smtpport = "587"

# create Credential object
$noreply = ConvertTo-SecureString -String $env:mailpassword -AsPlainText -Force 
$Credential_mail = New-Object System.Management.Automation.PSCredential ("$env:mailuser", $noreply)

<# Funkcja chwilowo nie uzywana
Function Send-Email
{
  param(
        $subject,
        $body
       )
  Process {
       Send-MailMessage -To $to -From $from -Subject $subject `
      -BodyAsHtml $bodyno -Encoding ([System.Text.Encoding]::UTF8) -SmtpServer $smtpserver -Credential $Credential_mail `
      -Port $smtpport -UseSsl
    }
}
#>

#Deklaracja array
$edge_issue = @()
#Pobranie informacji o edgach
$alledge = Get-NsxEdge | select name,id,@{n="STATUS"; e={$_.edgeSummary.edgeStatus }}

foreach($1edge in $alledge)
{
    #Write-Host "Sprawdzam $1edge" "jej status to" $1edge.STATUS
    if ($1edge.STATUS -eq "GREEN")
        { 
            Write-Host -ForegroundColor GREEN "NSX EDGE o ID:" $1edge.id "i nazwie" $1edge.name "ma status" $1edge.status 
        } else 
        {
            #NSX edge mające status inny niz GREEN"
            #$edge_issue += $1edge
            $edge_issue += $1edge
            Write-Host  "NSX EDGE o ID:" $1edge.id "i nazwie" $1edge.name "ma status" -ForegroundColor RED $1edge.status

        } 

    }
$edge_issue

#Jesli w tablicy $edge_issue znajdzie jakies obiekty podejmuje decyzje o tresci maila
if (-not $edge_issue) {
#Zliczanie liczby obiektow w tablicy $edge_issue aby pozniej uzyc tego w polu -Subject
$liczedgy = $alledge.count   

# Z uwagi na to iż jest problem z parametrem -Encoding ([System.Text.Encoding]::UTF8) któy nie jest tutaj rozpoznawany odpowiednio pomijam go i temat jest po angielsku.
#Send-MailMessage -to $to -from $from -subject "NSX EDGE Report.Wszystkie $liczedgy EDGE działają OK" -Encoding ([System.Text.Encoding]::UTF8) -SmtpServer $smtpserver -Credential $credential_mail -port $smtpport -UseSsl -BodyAsHtml -body "Jest OK"

Send-MailMessage -to $to -from $from -subject "NSX Monitoring ==> All $liczedgy EDGEs working fine" -SmtpServer $smtpserver -Credential $credential_mail -port $smtpport -UseSsl -BodyAsHtml -body "Used script: https://bitbucket.exea.pl/projects/SEB/repos/powercli/browse/NSX-EDGE_Monitoring_Jenkins.ps1 "

        }
    else {
#Jesli znajdzie jakies linie w tablicy $edge_issue wykonuje ta czesc kody informujac o problemie
$bodyno = $edge_issue | ConvertTo-Html
$liczedgy = $edge_issue.count

#Metodą ponizej nie chce mi wysylac listy edgy w polu body. Zostawiam tak do czasu rozwiązania problemu.
#Send-Email -subject "NSX EDGE Report ALERT. Liczba wykrytych EDGE bez statusu GREEN $liczedgy"
#Send-MailMessage -to $to -from $from -subject "NSX EDGE Report ALERT. Liczba wykrytych EDGE bez statusu GREEN $liczedgy" -SmtpServer $smtpserver -Credential $credential_mail -port $smtpport -UseSsl -BodyAsHtml -body "$bodyno" -Encoding ([System.Text.Encoding]::UTF8) -Priority High

Send-MailMessage -to $to -from $from -subject "[DEV] NSX Monitoring ==> $liczedgy EDGEs working without GREEN status.Check them!!" -SmtpServer $smtpserver -Credential $credential_mail -port $smtpport -UseSsl -BodyAsHtml -body "$bodyno" -Encoding ([System.Text.Encoding]::UTF8) -Priority High

        }

