Add-Type -AssemblyName PresentationFramework
$appPath = $PSCommandPath
. "$PSScriptRoot\DriveData.ps1"
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="MaxLab Dynamics SSD Life Free" Width="1250" Height="720" MinWidth="1000" MinHeight="550" Background="#101827" Foreground="#E5EDF8" WindowStartupLocation="CenterScreen">
 <Grid Margin="28">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <DockPanel Margin="0,0,0,20">
   <Border DockPanel.Dock="Left" Background="White" Width="104" Height="104" Margin="0,0,22,0"><Image x:Name="BrandLogo" Stretch="Uniform"/></Border>
   <StackPanel VerticalAlignment="Center">
    <TextBlock Text="MaxLab Dynamics SSD Life Free" FontSize="28" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock Text="SMART health, power-on hours and storage usage." FontSize="15" Foreground="#9EADC4" Margin="0,8,0,8"/>
    <TextBlock FontSize="15"><Hyperlink x:Name="Website" NavigateUri="https://MaxLabDynamics.com" Foreground="#70BCFF">https://MaxLabDynamics.com</Hyperlink></TextBlock>
   </StackPanel>
  </DockPanel>
  <DockPanel Grid.Row="1" Margin="0,0,0,18"><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button x:Name="Admin" Content="Run as admin" Padding="12,9" Margin="0,0,10,0"/><Button x:Name="Notes" Content="Scan notes" Padding="12,9" Margin="0,0,10,0"/><Button x:Name="Refresh" Content="Refresh drives" Padding="18,9" Margin="0,0,10,0"/><Button x:Name="Export" Content="Export report" Padding="18,9" IsEnabled="False"/></StackPanel><TextBlock x:Name="Status" Text="Ready to scan" VerticalAlignment="Center" TextWrapping="Wrap"/></DockPanel>
  <TabControl Grid.Row="2"><TabItem Header="All drives / SMART"><DataGrid x:Name="Drives" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single" Background="#F4F7FC" Foreground="#142034" RowHeight="42" HeadersVisibility="Column" GridLinesVisibility="Horizontal" BorderThickness="0">
   <DataGrid.Columns>
    <DataGridTextColumn Header="Drive" Binding="{Binding Drive}" Width="*"/>
    <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="85"/>
    <DataGridTextColumn Header="Connection" Binding="{Binding Bus}" Width="90"/>
    <DataGridTextColumn Header="GB" Binding="{Binding CapacityGB}" Width="85"/>
    <DataGridTextColumn Header="Windows" Binding="{Binding Health}" Width="85"/>
    <DataGridTextColumn Header="SMART" Binding="{Binding SmartHealth}" Width="85"/>
    <DataGridTextColumn Header="Endurance left" Binding="{Binding RemainingText}" Width="120"/>
    <DataGridTextColumn Header="Temp" Binding="{Binding TemperatureText}" Width="85"/>
    <DataGridTextColumn Header="Hours on" Binding="{Binding HoursText}" Width="90"/>
   </DataGrid.Columns>
  </DataGrid></TabItem><TabItem Header="Partitions / C:, D: ...">
   <DataGrid x:Name="Partitions" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" Background="#F4F7FC" Foreground="#142034" RowHeight="36" HeadersVisibility="Column">
    <DataGrid.Columns>
     <DataGridTextColumn Header="Drive" Binding="{Binding Letter}" Width="65"/>
     <DataGridTextColumn Header="Label" Binding="{Binding Label}" Width="110"/>
     <DataGridTextColumn Header="Physical disk" Binding="{Binding Disk}" Width="*"/>
     <DataGridTextColumn Header="Part." Binding="{Binding Partition}" Width="45"/>
     <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="80"/>
     <DataGridTextColumn Header="Format" Binding="{Binding FileSystem}" Width="75"/>
     <DataGridTextColumn Header="GB" Binding="{Binding CapacityGB}" Width="75"/>
     <DataGridTextColumn Header="Free GB" Binding="{Binding FreeText}" Width="75"/>
     <DataGridTextColumn Header="Used" Binding="{Binding UsedText}" Width="65"/>
     <DataGridTextColumn Header="Health" Binding="{Binding Health}" Width="85"/>
    </DataGrid.Columns>
   </DataGrid></TabItem></TabControl>
  <TextBox Grid.Row="3" x:Name="Details" IsReadOnly="True" TextWrapping="Wrap" Background="#1B293E" Foreground="#E5EDF8" BorderThickness="0" Padding="14" Margin="0,16,0,16" MinHeight="110" MaxHeight="170" VerticalScrollBarVisibility="Auto" Text="Select a drive to inspect its reported wear and errors."/>
  <TextBlock Grid.Row="4" TextWrapping="Wrap" Foreground="#9EADC4" Text="HDD life remaining: N/A. M.2 is a form factor; NVMe/SATA identify the protocol. Endurance left = 100 minus reported wear used, floored at 0%. This is an estimated write-wear budget, not time until failure. A healthy drive can still fail suddenly. Keep backups. Unknown means unavailable, never 100%."/>
 </Grid>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$logo = New-Object Windows.Media.Imaging.BitmapImage
$logo.BeginInit()
$logo.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$logo.UriSource = [Uri](Join-Path $PSScriptRoot 'assets\maxlab-logo.jpg')
$logo.EndInit()
$window.FindName('BrandLogo').Source = $logo
$window.FindName('Website').Add_RequestNavigate({
    param($sender, $eventArgs)
    try { Start-Process -FilePath 'https://MaxLabDynamics.com' -ErrorAction Stop }
    catch { [Windows.MessageBox]::Show($_.Exception.Message, 'Could not open website') }
    $eventArgs.Handled = $true
})
$refresh = $window.FindName('Refresh'); $export = $window.FindName('Export')
$status = $window.FindName('Status'); $grid = $window.FindName('Drives'); $details = $window.FindName('Details')
$partitionGrid = $window.FindName('Partitions')
$script:partitions = @(); $script:issues = @()
$script:rows = @(); $script:job = $null; $script:scannedAt = $null
$window.FindName('Admin').Add_Click({
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $appPath) -ErrorAction Stop
        $window.Close()
    } catch { [Windows.MessageBox]::Show('Administrator launch was cancelled or failed: ' + $_.Exception.Message, 'MaxLab Dynamics SSD Life Free') }
})
$window.FindName('Notes').Add_Click({
    $message = if ($script:issues.Count) { $script:issues -join "`r`n" } else { 'No scan errors. Select a drive to see device-specific notes.' }
    [Windows.MessageBox]::Show($message, 'Scan notes')
})
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    if ($script:job.State -notin @('Completed','Failed','Stopped')) { return }
    $timer.Stop()
    try {
        $snapshot = Receive-Job $script:job -ErrorAction Stop
        $result = @($snapshot.Drives)
        $script:partitions = @($snapshot.Partitions)
        $script:issues = @($snapshot.Issues)
        if (-not $result.Count -and -not $script:partitions.Count) { throw ($script:issues -join '; ') }
        $partitionGrid.ItemsSource = $script:partitions
        $script:rows = @($result | ForEach-Object {
            $_ | Add-Member RemainingText $(if ($null -eq $_.Remaining) {if ($_.Type -eq 'HDD') {'N/A (HDD)'} else {'Unknown'}} else {"$($_.Remaining)%"}) -PassThru |
                Add-Member TemperatureText $(if ($null -eq $_.Temperature) {'Unknown'} else {"$($_.Temperature) C"}) -PassThru |
                Add-Member HoursText $(if ($null -eq $_.PowerOnHours) {'Unknown'} else {[string]$_.PowerOnHours}) -PassThru
        })
        $grid.ItemsSource = $script:rows
        $script:scannedAt = Get-Date
        $status.Text = "$($script:rows.Count) disk(s), $($script:partitions.Count) partition(s) - $($script:scannedAt.ToString('HH:mm:ss'))"
        if ($script:issues.Count) { $status.Text += ' (see scan notes)' }
        $export.IsEnabled = $true
        $grid.SelectedIndex = 0
        if ($script:issues.Count) { $details.Text = $script:issues -join "`r`n" }
    } catch {
        $script:rows = @(); $script:partitions = @(); $partitionGrid.ItemsSource = $null; $grid.ItemsSource = $null; $export.IsEnabled = $false
        $status.Text = 'Scan failed'
        $details.Text = 'Windows could not read your drives. Close this app and use Start as administrator.cmd. If it still fails, the storage provider may be unavailable. Details: ' + $_.Exception.Message
    } finally { Remove-Job $script:job -Force; $script:job = $null; $refresh.IsEnabled = $true }
})
$refresh.Add_Click({
    $refresh.IsEnabled = $false; $export.IsEnabled = $false; $status.Text = 'Reading drive counters...'
    $details.Text = 'Reading hardware data. This may take a few seconds.'
    $script:job = Start-Job -ArgumentList "$PSScriptRoot\DriveData.ps1" -ScriptBlock { param($source) . $source; Get-StorageSnapshot }
    $timer.Start()
})
$grid.Add_SelectionChanged({
    $d = $grid.SelectedItem
    if ($null -eq $d) { return }
    $readErrors = if ($null -eq $d.UncorrectedReads) {'Unknown'} else {$d.UncorrectedReads}
    $writeErrors = if ($null -eq $d.UncorrectedWrites) {'Unknown'} else {$d.UncorrectedWrites}
    $wearText = if ($null -eq $d.WearUsed) {'Unknown'} else {"$($d.WearUsed)%"}
    $details.Text = "Drive ID: $($d.Id) | $($d.Type) / $($d.Bus) | SMART: $($d.SmartHealth) | Wear used: $wearText`r`nSource: $($d.Source) | SMART device: $($d.SmartDevice) | NVMe media errors: $(if ($null -eq $d.MediaErrors) {"Unknown"} else {$d.MediaErrors})`r`nUncorrected read errors: $readErrors | Write errors: $writeErrors`r`n$($d.Note)"
})
$partitionGrid.Add_SelectionChanged({
    $p = $partitionGrid.SelectedItem
    if ($null -ne $p) {
        $details.Text = "$($p.Letter) $($p.Label) | Disk: $($p.Disk) | Partition: $($p.Partition)`r`nCapacity: $($p.CapacityGB) GB | Free: $($p.FreeText) GB | Used: $($p.UsedText)`r`nMount paths: $($p.AccessPaths -join ', ')`r`nPartitions share the wear of their physical SSD; space usage is not remaining SSD endurance."
    }
})
$export.Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'JSON report (*.json)|*.json'; $dialog.FileName = 'MaxLab-Dynamics-SSD-Life-Free-report.json'
    if ($dialog.ShowDialog()) {
        try { [pscustomobject]@{Application='MaxLab Dynamics SSD Life Free';Website='https://MaxLabDynamics.com';ScannedAt=$script:scannedAt.ToString('o');Source='Windows Storage and smartmontools SMART';Drives=$script:rows;Partitions=$script:partitions;Issues=$script:issues} | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8; $status.Text = 'Report saved' }
        catch { [Windows.MessageBox]::Show($_.Exception.Message, 'Could not save report') }
    }
})
$window.Add_Closed({ $timer.Stop(); if ($script:job) { Stop-Job $script:job; Remove-Job $script:job -Force } })
$window.Add_ContentRendered({ $refresh.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) })
$null = $window.ShowDialog()
