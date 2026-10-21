# smartctl is a separate GPL-licensed executable; only read-only commands are used.
function Invoke-SmartctlJson {
    param([string]$Executable, [string[]]$Arguments)
    foreach ($argument in $Arguments) {
        if ($argument -notmatch '^[a-zA-Z0-9/.,_:+=\-]+$') { throw 'Invalid SMART argument.' }
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'SMART query timed out after 30 seconds.' }
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if (-not $text.Trim()) { throw "SMART returned no data. $errorText" }
        # Exit status is a bitmask. Nonzero can carry useful health/error data.
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } finally { $process.Dispose() }
}

function Get-SmartWindowsDiskNumber([string]$Device) {
    # Documented smartctl Windows aliases, not discovery ordering.
    # /dev/sda = PhysicalDrive0; /dev/sdz = 25; /dev/sdaa = 26.
    if ($Device -match '^/dev/pd([0-9]+)$') { return [int]$Matches[1] }
    if ($Device -match '^/dev/sd([a-z]{1,2})$') {
        $number = 0
        foreach ($letter in $Matches[1].ToCharArray()) {
            $number = $number * 26 + ([int]$letter - [int][char]'a' + 1)
        }
        return $number - 1
    }
    return $null
}

function Convert-SmartReading {
    param($Data)
    $nvme = $Data.nvme_smart_health_information_log
    $type = 'Unspecified'
    if ($Data.device.protocol -eq 'NVMe' -or $Data.rotation_rate -eq 0) { $type = 'SSD' }
    elseif ($Data.rotation_rate -gt 0) { $type = 'HDD' }
    $hours = $Data.power_on_time.hours
    if ($null -eq $hours -and $nvme) { $hours = $nvme.power_on_hours }
    $wear = $Data.endurance_used.current_percent
    if ($null -eq $wear -and $nvme) { $wear = $nvme.percentage_used }
    # Do not guess vendor-specific ATA percentages from attribute IDs.
    $remaining = $null
    if ($type -ne 'HDD' -and $null -ne $wear) {
        $type = 'SSD'
        $remaining = Get-EnduranceRemaining $wear
    }
    $notes = @()
    if ($Data.smart_support.available -eq $false) { $notes += 'SMART is not available through this device/controller.' }
    if ($Data.smart_support.enabled -eq $false) { $notes += 'Device reports SMART disabled. App does not change device settings.' }
    if ($null -eq $hours) { $notes += 'Power-on hours were not reported.' }
    if ($type -eq 'HDD') { $notes += 'HDD remaining life cannot be expressed as a reliable percentage.' }
    elseif ($null -eq $remaining) { $notes += 'No recognized endurance percentage. Vendor-specific raw attributes are included in the report.' }
    foreach ($message in @($Data.smartctl.messages)) { if ($message.string) { $notes += $message.string } }
    $smartHealth = 'Unknown'
    if ($null -ne $Data.smart_status.passed) {
        $smartHealth = if ($Data.smart_status.passed) { 'Passed' } else { 'FAILED' }
    }
    if ($nvme.critical_warning -gt 0) { $smartHealth = 'WARNING'; $notes += "NVMe critical warning: $($nvme.critical_warning)" }
    [pscustomobject]@{
        Model = $(if ($Data.model_name) { $Data.model_name } elseif ($Data.scsi_model_name) { $Data.scsi_model_name } else { $Data.device.name })
        Serial = [string]$Data.serial_number
        Device = $Data.device.name
        WindowsDiskNumber = Get-SmartWindowsDiskNumber $Data.device.name
        Protocol = $Data.device.protocol
        Type = $type
        CapacityGB = $(if ($Data.user_capacity.bytes) { [math]::Round($Data.user_capacity.bytes / 1e9, 1) } else { $null })
        PowerOnHours = $hours
        WearUsed = $wear
        Remaining = $remaining
        Temperature = $Data.temperature.current
        SmartHealth = $smartHealth
        MediaErrors = $nvme.media_errors
        Note = $notes -join ' '
        Raw = $Data
    }
}

function Get-SmartSnapshot {
    $exe = Join-Path $PSScriptRoot 'tools\smartctl.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        throw 'SMART reader missing. Restore tools/smartctl.exe from the complete SSD Life package (see README).'
    }
    $scan = Invoke-SmartctlJson $exe @('--scan-open', '-j')
    $readings = @(); $issues = @()
    foreach ($device in @($scan.devices)) {
        try {
            $arguments = @('-a', '-j')
            if ($device.type) { $arguments += @('-d', $device.type) }
            $arguments += $device.name
            $data = Invoke-SmartctlJson $exe $arguments
            $readings += Convert-SmartReading $data
        } catch { $issues += "$($device.name): $($_.Exception.Message)" }
    }
    if (-not @($scan.devices).Count) {
        $issues += 'SMART scan found no devices. Use Run as administrator; USB/RAID bridges may not expose SMART.'
    }
    foreach ($message in @($scan.smartctl.messages)) { if ($message.string) { $issues += $message.string } }
    [pscustomobject]@{ Readings=$readings; Issues=$issues }
}

function Merge-SmartSnapshot {
    param([object[]]$Drives, [object[]]$Readings)
    $used = @{}
    foreach ($drive in $Drives) {
        $matches = @()
        if ($null -ne $drive.WindowsDiskNumber) {
            $matches = @($Readings | Where-Object {
                $null -ne $_.WindowsDiskNumber -and $_.WindowsDiskNumber -eq $drive.WindowsDiskNumber
            })
        }
        if ($matches.Count -eq 0 -and $drive.Serial) {
            $matches = @($Readings | Where-Object { $_.Serial -and $_.Serial.Trim() -eq $drive.Serial.Trim() })
        }
        if ($matches.Count -eq 0) {
            $sameWindowsModels = @($Drives | Where-Object { $_.Drive -eq $drive.Drive })
            if ($sameWindowsModels.Count -eq 1) {
                $matches = @($Readings | Where-Object {
                    $_.Model -eq $drive.Drive -and (-not $drive.Serial -or -not $_.Serial)
                })
            }
        }
        if ($matches.Count -eq 1 -and -not $used.ContainsKey([string]$matches[0].Device)) {
            $s = $matches[0]; $used[[string]$s.Device] = $true
            foreach ($field in @('PowerOnHours','WearUsed','Remaining','Temperature')) {
                if ($null -ne $s.$field) { $drive.$field = $s.$field }
            }
            if ($s.Type -ne 'Unspecified') { $drive.Type = $s.Type }
            if ($drive.Type -eq 'HDD') { $drive.Remaining = $null; $drive.WearUsed = $null }
            $drive.SmartHealth = $s.SmartHealth; $drive.SmartDevice = $s.Device
            $drive.SmartRaw = $s.Raw; $drive.MediaErrors = $s.MediaErrors
            $drive.Source = 'Windows + smartctl SMART'
            $drive.Note = ($drive.Note + ' SMART: ' + $s.Note).Trim()
        }
        $drive
    }
    # Include devices visible only to smartctl. Do not guess their Windows disk mapping.
    foreach ($s in $Readings) {
        if (-not $used.ContainsKey([string]$s.Device)) {
            [pscustomobject]@{
                Drive=$s.Model; Id='Unmapped'; Serial=$s.Serial; Type=$s.Type; Bus=$s.Protocol; WindowsDiskNumber=$s.WindowsDiskNumber
                CapacityGB=$s.CapacityGB; Health='Unknown'; Operation='SMART device'
                Remaining=$s.Remaining; WearUsed=$s.WearUsed; Temperature=$s.Temperature
                PowerOnHours=$s.PowerOnHours; UncorrectedReads=$null; UncorrectedWrites=$null
                SmartHealth=$s.SmartHealth; SmartDevice=$s.Device; SmartRaw=$s.Raw; MediaErrors=$s.MediaErrors
                Source='smartctl SMART'; Note=$s.Note
            }
        }
    }
}
