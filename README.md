# MaxLab Dynamics SSD Life Free

[MaxLab Dynamics](https://MaxLabDynamics.com)

![MaxLab Dynamics logo](assets/maxlab-logo.jpg)

A portable Windows disk-health dashboard written in PowerShell and WPF.
Shows SMART power-on hours, SSD write endurance, temperature, Windows and
SMART health, and partition reports such as C: and D:.


## Download

[Download the latest Windows app](https://github.com/BeyondElectronics/MaxLab-Dynamics-SSD-Life-Free/releases/latest)

Open the release, download the Windows x64 ZIP under **Assets**, extract the entire folder, and run **Start.cmd**.

## Run

1. Download the complete repository or release ZIP and extract it.
2. Double-click **Start.cmd**.
3. For full SMART access, click **Run as admin** in the app, or launch
   **Start as administrator.cmd**. Approve the Windows UAC prompt.
4. Use **Refresh drives** for new readings, **Scan notes** for errors, or
   **Export report** for a JSON snapshot including raw SMART attributes.

Requires 64-bit Windows 10/11 with Windows PowerShell 5.1, WPF and the Windows
Storage module. The bundled smartctl executable is 64-bit. No Python, .NET
SDK, installer or background service is required. ExecutionPolicy Bypass is
used only for the launched PowerShell process; no persistent policy is changed.
Drive scanning works offline. Clicking the website link opens your default browser.

## What it reports

| Item | Behavior |
|---|---|
| NVMe SSDs, including many M.2 drives | SMART hours, temperature, health and percentage used where exposed |
| SATA/ATA SSDs, including 2.5-inch and M.2 SATA | Hours and health; endurance when smartctl provides a recognized percentage |
| HDDs | Hours, health, temperature and raw attributes where available; remaining life is N/A |
| SAS/SCSI and USB-attached storage | Enumerated through Windows/smartctl; available readings depend on controller pass-through |
| RAID, virtual disks, unsupported bridges | Listed where detected; inaccessible fields stay Unknown |
| Partitions and volumes | Disk model/number, partition number, letter, mount paths, format, capacity, free space and usage |

M.2 is a physical form factor, not a health protocol. The app reports media
type and connection/protocol when available; it does not infer an M.2 form
factor from NVMe. Memory cards, optical drives and virtual devices generally
do not expose useful SMART data. There is no promise of universal hardware
support.

## How readings work

Windows `Get-PhysicalDisk` and storage reliability counters supply the base
inventory. smartctl `--scan-open -j` discovers additional SMART devices;
`-a -j` reads each device using its detected type. Queries have a 30-second
timeout per process. Nonzero smartctl exit codes are a bitmask, so useful
readings and health warnings are retained. No tests, SMART-enable commands,
firmware updates, formatting or writes to user data are issued.

SMART devices are matched by the documented Windows physical-disk aliases
(`/dev/pdN` and `/dev/sd...`) and Get-Disk numbers. Windows PhysicalDisk IDs
are linked to Get-Disk only when model/serial matching is unique. This avoids
duplicating NVMe drives whose Windows namespace identifier differs from the
SMART controller serial. Hardware serials and unique models with no conflicting
serial are fallbacks. Ambiguous matches remain separate; discovery order is
never used as a disk identity.

Remaining write endurance is `max(0, 100 - percentage used)`. NVMe percentage
used and smartctl's unified `endurance_used.current_percent` are supported.
Windows wear is a fallback for known SSDs. ATA attribute IDs are not treated
as universal percentages. Unknown values remain null in exports. HDDs never
receive a remaining-life percentage.

**Endurance is not a failure countdown.** Hours are cumulative powered-on
hours, not the age since purchase. Even a healthy drive with high remaining
endurance can fail. Partitions share their physical disk's wear; free space
does not measure remaining SSD life.

## Troubleshooting

- Unknown hours/wear: retry as administrator and inspect Scan notes and the
  selected drive's notes. Some firmware, USB bridges and RAID controllers hide
  SMART; elevation cannot manufacture missing readings.
- SMART disabled: the app reports this without changing device settings.
- Missing reader: restore `tools/smartctl.exe` and `tools/drivedb.h` from the
  complete package. See THIRD_PARTY.md for the exact upstream release.
- Exported reports include drive serial numbers, labels and raw device data.
  Review/redact them before posting publicly. No personal drive reports are
  included in this repository.

## Develop and test

All application source is in `SSD-Life.ps1`, `DriveData.ps1`, and
`SmartData.ps1`. Edit these directly; no build step is needed.

Run the synthetic tests from the repository folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\tests\Test.ps1
```

These test parsing, endurance conversion, NVMe/ATA/HDD handling, duplicate
model matching, partitions, and WPF loading without accessing hardware.
Real-world validation was performed on a TEAM NVMe drive, an HP SATA SSD,
and Windows partitions. The asynchronous WPF refresh was also verified. Other controller/media combinations need hardware testing.

## Publish your copy on GitHub

Create an empty GitHub repository, open a terminal in this folder, then:

```powershell
git init
git add .
git commit -m "Add SSD Life SMART dashboard"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/ssd-life.git
git push -u origin main
```

Replace YOUR-USERNAME with your account. Keep the third-party license and
matching source archive when distributing the bundled SMART executable.
The application code is MIT licensed; smartmontools remains separately
licensed. See LICENSE and THIRD_PARTY.md.

## References

- [smartctl manual](https://github.com/smartmontools/smartmontools/blob/main/src/smartctl.8.in)
- [Windows storage reliability counters](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-storagereliabilitycounter)
