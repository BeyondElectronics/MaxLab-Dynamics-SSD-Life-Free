$ErrorActionPreference = 'Stop'
try {
    $app = Join-Path $PSScriptRoot 'SSD-Life.ps1'
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $app)
} catch {
    Write-Error ('Administrator launch was cancelled or failed: ' + $_.Exception.Message)
    exit 1
}
