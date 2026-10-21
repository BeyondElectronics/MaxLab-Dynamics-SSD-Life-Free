. "$PSScriptRoot\SmartData.ps1"

function Get-EnduranceRemaining($Wear) {
    if ($null -eq $Wear) { return $null }
    return [Math]::Max(0, 100 - [double]$Wear)
}

function Get-PartitionSnapshot {
    foreach ($disk in @(Get-Disk -ErrorAction Stop)) {
        foreach ($partition in @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop)) {
            $volume = $null
            try { $volume = $partition | Get-Volume -ErrorAction Stop } catch { }
            $size = $partition.Size
            $free = $null; $used = $null
            if ($volume -and $volume.Size -gt 0) {
                $size = $volume.Size
                $free = [math]::Round($volume.SizeRemaining / 1e9, 2)
                $used = [math]::Round(100 * (1 - $volume.SizeRemaining / $volume.Size), 1)
            }
            [pscustomobject]@{
                Letter = $(if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { '(none)' })
                Label = $(if ($volume) { $volume.FileSystemLabel } else { '' })
                Disk = "$($disk.Number) - $($disk.FriendlyName)"
                Partition = $partition.PartitionNumber
                Type = [string]$partition.Type
                FileSystem = $(if ($volume) { [string]$volume.FileSystemType } else { 'Unknown' })
                CapacityGB = [math]::Round($size / 1e9, 2)
                FreeGB = $free
                UsedPercent = $used
                FreeText = $(if ($null -eq $free) { 'Unknown' } else { [string]$free })
                UsedText = $(if ($null -eq $used) { 'Unknown' } else { "$used%" })
                Health = $(if ($volume) { [string]$volume.HealthStatus } else { 'Unknown' })
                AccessPaths = @($partition.AccessPaths)
            }
        }
    }
}

function Get-StorageSnapshot {
    $drives = @(); $partitions = @(); $issues = @()
    try { $drives = @(Get-DriveSnapshot) } catch { $issues += 'Physical drives: ' + $_.Exception.Message }
    try { $partitions = @(Get-PartitionSnapshot) } catch { $issues += 'Partitions: ' + $_.Exception.Message }
    try {
        $smart = Get-SmartSnapshot
        $drives = @(Merge-SmartSnapshot $drives @($smart.Readings))
        $issues += @($smart.Issues)
    } catch { $issues += 'SMART: ' + $_.Exception.Message }
    [pscustomobject]@{ Drives=$drives; Partitions=$partitions; Issues=$issues }
}

function Get-DriveSnapshot {
    $drives = @(Get-PhysicalDisk -ErrorAction Stop)
    if ($drives.Count -eq 0) { throw 'Windows returned no physical drives.' }
    $windowsDisks = @()
    try { $windowsDisks = @(Get-Disk -ErrorAction Stop) } catch { }
    foreach ($disk in $drives) {
        $windowsDiskNumber = $null
        # PhysicalDisk.DeviceId is not assumed to equal Get-Disk.Number.
        $diskMatches = @($windowsDisks | Where-Object {
            $_.SerialNumber -and $disk.SerialNumber -and
            $_.SerialNumber.Trim() -eq $disk.SerialNumber.Trim() -and
            $_.FriendlyName -eq $disk.FriendlyName
        })
        if ($diskMatches.Count -eq 1) { $windowsDiskNumber = [int]$diskMatches[0].Number }
        $counter = $null
        $note = ''
        try { $counter = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop }
        catch { $note = 'Counters unavailable. Try running as administrator. Some USB/RAID controllers do not expose wear data. ' + $_.Exception.Message }
        $wear = if ($null -ne $counter) { $counter.Wear } else { $null }
        $remaining = if ([string]$disk.MediaType -eq 'SSD') { Get-EnduranceRemaining $wear } else { $null }
        if ([string]$disk.MediaType -eq 'Unspecified') { $note += ' Drive type is unspecified; endurance estimate withheld.' }
        if ($null -eq $wear -and -not $note) { $note = 'This drive or controller does not report wear.' }
        [pscustomobject]@{
            Drive = $disk.FriendlyName
            Serial = [string]$disk.SerialNumber
            WindowsDiskNumber = $windowsDiskNumber
            Bus = [string]$disk.BusType
            SmartHealth = 'Unknown'
            SmartDevice = $null
            SmartRaw = $null
            MediaErrors = $null
            Source = 'Windows Storage'
            Id = [string]$disk.DeviceId
            Type = [string]$disk.MediaType
            CapacityGB = [math]::Round($disk.Size / 1e9, 1)
            Health = [string]$disk.HealthStatus
            Operation = ($disk.OperationalStatus -join ', ')
            Remaining = $remaining
            WearUsed = $wear
            Temperature = $(if ($counter -and $counter.Temperature -gt 0) { $counter.Temperature } else { $null })
            PowerOnHours = $(if ($counter) { $counter.PowerOnHours } else { $null })
            UncorrectedReads = $(if ($counter) { $counter.ReadErrorsUncorrected } else { $null })
            UncorrectedWrites = $(if ($counter) { $counter.WriteErrorsUncorrected } else { $null })
            Note = $note
        }
    }
}
