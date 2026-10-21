$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\DriveData.ps1"
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
foreach ($file in @(Get-ChildItem $root -Filter '*.ps1' -Recurse)) {
    $tokens = $null; $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert ($parseErrors.Count -eq 0) "Syntax: $($file.Name): $parseErrors"
}
Assert ($null -eq (Get-EnduranceRemaining $null)) 'Missing wear must stay null'
foreach ($pair in @(@(0,100), @(1,99), @(100,0), @(150,0))) {
    Assert ((Get-EnduranceRemaining $pair[0]) -eq $pair[1]) 'Endurance boundary'
}
$nvme = @'
{"device":{"name":"/dev/sdb","protocol":"NVMe"},"model_name":"Example NVMe","serial_number":"SYNTHETIC-1","nvme_smart_health_information_log":{"percentage_used":1,"power_on_hours":4090,"media_errors":0,"critical_warning":0},"temperature":{"current":54},"smart_status":{"passed":true},"smartctl":{"exit_status":8}}
'@ | ConvertFrom-Json
$reading = Convert-SmartReading $nvme
Assert ($reading.PowerOnHours -eq 4090 -and $reading.Remaining -eq 99) 'NVMe hours and remaining'
Assert ($reading.SmartHealth -eq 'Passed' -and $reading.MediaErrors -eq 0) 'SMART fields with nonzero status'
$nvme.nvme_smart_health_information_log.critical_warning = 1
Assert ((Convert-SmartReading $nvme).SmartHealth -eq 'WARNING') 'NVMe warning'
$ata = '{"device":{"protocol":"ATA"},"rotation_rate":0,"power_on_time":{"hours":123},"ata_smart_attributes":{"table":[{"id":231,"value":95,"raw":{"value":5}}]}}' | ConvertFrom-Json
$r = Convert-SmartReading $ata
Assert ($r.Type -eq 'SSD' -and $r.PowerOnHours -eq 123 -and $null -eq $r.Remaining) 'Do not guess ATA wear'
$ata | Add-Member endurance_used ([pscustomobject]@{current_percent=12})
Assert ((Convert-SmartReading $ata).Remaining -eq 88) 'Unified ATA wear'
$ata.rotation_rate = 7200
Assert ((Convert-SmartReading $ata).Type -eq 'HDD' -and $null -eq (Convert-SmartReading $ata).Remaining) 'HDD N/A'
$empty = Convert-SmartReading ('{"device":{"protocol":"SCSI"}}' | ConvertFrom-Json)
Assert ($null -eq $empty.PowerOnHours -and $null -eq $empty.Remaining) 'Missing SMART data'
function New-TestDrive($Serial) {
    [pscustomobject]@{Drive='Example NVMe';Serial=$Serial;Type='SSD';Bus='NVMe';PowerOnHours=$null;WearUsed=$null;Remaining=$null;Temperature=$null;SmartHealth='Unknown';SmartDevice=$null;SmartRaw=$null;MediaErrors=$null;Source='Windows';Note=''}
}
$matched = @(Merge-SmartSnapshot @((New-TestDrive 'SYNTHETIC-1')) @($reading))
Assert ($matched.Count -eq 1 -and $matched[0].PowerOnHours -eq 4090) 'Serial matching'
$ambiguous = @(Merge-SmartSnapshot @((New-TestDrive ''), (New-TestDrive '')) @($reading))
Assert ($ambiguous.Count -eq 3 -and $null -eq $ambiguous[0].Remaining) 'Do not guess duplicate models'
$differentSerial = @(Merge-SmartSnapshot @((New-TestDrive 'DIFFERENT-SERIAL')) @($reading))
Assert ($differentSerial.Count -eq 2 -and $null -eq $differentSerial[0].Remaining) 'Do not override a conflicting serial by model'
Assert ((Get-SmartWindowsDiskNumber '/dev/sda') -eq 0) 'Disk alias zero'
Assert ((Get-SmartWindowsDiskNumber '/dev/sdz') -eq 25) 'Disk alias z'
Assert ((Get-SmartWindowsDiskNumber '/dev/sdaa') -eq 26) 'Disk alias aa'
Assert ((Get-SmartWindowsDiskNumber '/dev/pd1') -eq 1) 'Explicit physical disk alias'
Assert ($null -eq (Get-SmartWindowsDiskNumber '/dev/csmi0,0')) 'Do not guess RAID disk mapping'
$namespaceDrive = New-TestDrive '0000_0000_0000_0001_0000_0000_0000_0001.'
$namespaceDrive | Add-Member WindowsDiskNumber 1
$mergedNamespace = @(Merge-SmartSnapshot @($namespaceDrive) @($reading))
Assert ($mergedNamespace.Count -eq 1 -and $mergedNamespace[0].PowerOnHours -eq 4090) 'NVMe namespace identifier must not duplicate controller serial'
function Get-Disk { [pscustomobject]@{Number=0;FriendlyName='Synthetic disk'} }
function Get-Partition {
    @([pscustomobject]@{PartitionNumber=1;DriveLetter='C';Size=100e9;Type='Basic';AccessPaths=@('C:\')},
      [pscustomobject]@{PartitionNumber=2;DriveLetter=$null;Size=1e9;Type='Recovery';AccessPaths=@()})
}
function Get-Volume {
    process {
        if ($_.PartitionNumber -eq 2) { throw 'No volume' }
        [pscustomobject]@{Size=100e9;SizeRemaining=25e9;FileSystemLabel='Example';FileSystemType='NTFS';HealthStatus='Healthy'}
    }
}
$parts = @(Get-PartitionSnapshot)
Assert ($parts.Count -eq 2 -and $parts[0].Letter -eq 'C:' -and $parts[0].UsedPercent -eq 75 -and $parts[0].FreeGB -eq 25) 'Partition capacity'
Assert ($parts[1].Letter -eq '(none)' -and $null -eq $parts[1].FreeGB) 'Hidden partition'
function Get-DriveSnapshot { throw 'Denied' }
function Get-SmartSnapshot { [pscustomobject]@{Readings=@($reading);Issues=@()} }
$snapshot = Get-StorageSnapshot
Assert ($snapshot.Partitions.Count -eq 2 -and $snapshot.Drives.Count -eq 1 -and $snapshot.Issues.Count -eq 1) 'Independent SMART/partition fallback'
$export = $snapshot | ConvertTo-Json -Depth 25 | ConvertFrom-Json
Assert ($export.Drives[0].SmartRaw.serial_number -eq 'SYNTHETIC-1') 'Raw SMART survives export'
Add-Type -AssemblyName PresentationFramework
$source = Get-Content "$root\SSD-Life.ps1" -Raw
$text = [regex]::Match($source, "(?s)\[xml\]\`$xaml = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
[xml]$xml = $text
$view = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
foreach ($name in @('Drives','Partitions','Admin','Notes','Refresh','Export')) { Assert ($null -ne $view.FindName($name)) "Missing UI control: $name" }
$view.Close()
Write-Output 'PASS: syntax, endurance boundaries, NVMe, ATA, HDD, absent data, identity mapping, partitions, partial access, export, WPF layout.'
