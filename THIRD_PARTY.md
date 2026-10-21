# smartmontools 7.5

SSD Life runs the unmodified smartctl command-line tool as a separate process.
No smartd service is installed or started.

- Project: https://www.smartmontools.org/
- Release: https://github.com/smartmontools/smartmontools/releases/tag/RELEASE_7_5
- Windows package: `smartmontools-7.5.win32-setup.exe`, official GitHub release.
- Included files: `tools/smartctl.exe` (64-bit) and `tools/drivedb.h`.
- License text: `third-party/smartmontools-COPYING.txt` (GPL version 2).
- Matching upstream source: `third-party/smartmontools-7.5.tar.gz`, copied
  without modification from the same official release. Keep this archive and
  license with redistributed binary packages. The source contains build and
  installation instructions and individual file copyright/license notices.
- SHA-256 of the included smartctl.exe:
  `B5DB94E5082C042BE44994B7A4FA8F7B5C8E713B2AB1C9A560D8F7A7995EA27D`.

Vendor-specific ATA attributes are interpreted by smartctl and its drive
database. SSD Life does not assume a universal meaning for ATA attribute IDs.
