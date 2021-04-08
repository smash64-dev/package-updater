# Changelog

## [0.10.2] - 2021-04-07

### Changed

- improved latest version detection

## [0.10.1] - 2020-05-23

### Added

- additional way to trigger menu bar toggle for improved wine support

### Changed

- tweaked logging to be less verbose

### Fixed

- RecordUpdate not recording in_beta properly
- __GetLatestBuild not sorting semver tags properly

## [0.10.0] - 2020-05-23

### Added

- progress bar to check and update actions
- menu bar for development/troubleshooting
- ability to hide and/or toggle menu bar
- local package update support from menu bar
- manual backup support from menu bar
- submit feedback option from menu bar
- logging to a file and dump logs from menu bar
- run an external program post update with PostUpdate
- record update actions for troubleshooting

### Changed

- gui now shows more popups on errors
- backups can now be tagged
- download directories and paths are more unique
- ensure directory is now "present" not "latest"
- command line options have been adjusted
- improved logging

### Fixed

- checksums were not checked in some cases
- ini_config would incorrectly store empty keys
- unix paths in configs would break transfers
- TransferLink had an incorrect regex

## [0.9.4] - 2020-04-28

### Added

- self mode which runs uninteractively

### Fixed

- autostart does not work when package Process changes
- updater freezes when toggling beta flag mid-update check

## [0.9.3] - 2020-04-21

### Added

- wine support for zip / unzip (requires 7-Zip)

### Changed

- make asset extract directory more unique

### Fixed

- user override config not being protected during transfer

## [0.9.2] - 2020-04-21

### Changed

- hide tray icon
- build id detection logging

### Fixed

- incorrect version number

## [0.9.1] - 2020-04-21

### Fixed

- build ID checks not working properly
- package-updater updater.cfg complex file order
- close the updater after transitioning to phase 2
- minor version strings

## [0.9.0] - 2020-04-20

- Initial beta release

[0.9.0]: https://github.com/smash64-dev/package-updater/releases/tag/v0.9.0
[0.9.1]: https://github.com/smash64-dev/package-updater/releases/tag/v0.9.1
[0.9.2]: https://github.com/smash64-dev/package-updater/releases/tag/v0.9.2
[0.9.3]: https://github.com/smash64-dev/package-updater/releases/tag/v0.9.3
[0.9.4]: https://github.com/smash64-dev/package-updater/releases/tag/v0.9.4
[0.10.0]: https://github.com/smash64-dev/package-updater/releases/tag/v0.10.0
[0.10.1]: https://github.com/smash64-dev/package-updater/releases/tag/v0.10.1
[0.10.2]: https://github.com/smash64-dev/package-updater/releases/tag/v0.10.2
