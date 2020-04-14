; updater.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global AUTHOR := "CEnnis91 © 2020"
global SELF := "package-updater"
global SOURCE := "https://github.com/smash64-dev/package-updater"
global VERSION := "1.0.0"

global APP_DIRECTORY := Format("{1}\{2}", A_AppData, SELF)
global TEMP_DIRECTORY := Format("{1}\{2}", A_Temp, SELF)

BackupOldPackage() {
	global
	OLD_PACKAGE.Backup(APP_DIRECTORY, OLD_PACKAGE.updater("Backups", "10"))
}

GetLatestChangelog() {
	global
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", "0"))
	local changelog_text := ""

	if github_api.GetReleases(TEMP_DIRECTORY) {
		; gather the changelog data, if any exists
		local changelog_file := OLD_PACKAGE.updater("ChangelogFile")

		if changelog_file {
			local changelog_asset := new Asset(changelog_file, github_api.GetFileURL(changelog_file), "", "None")
			local changelog_path := changelog_asset.GetAsset(TEMP_DIRECTORY)

			if FileExist(changelog_path) {
				FileRead, changelog_text, % changelog_path
			} else {
				log.err("Unable to download or find changelog asset from '{1}'", github_api.GetFileURL(changelog_file))
				changelog_text := "There was a problem getting the latest changelog"
			}
		} else {
			log.warn("No changelog has been provided with the latest release, missing 'ChangelogFile'")
			changelog_text := "No changelog has been provided with the latest release"
		}
	} else {
		log.crit("Unable to get release data from Github")
		changelog_text := "There was a problem getting the latest release information"
	}

	return changelog_text
}

GetLatestPackage() {
	global
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", 0))

	if github_api.GetReleases(TEMP_DIRECTORY) {
		local package_file := OLD_PACKAGE.updater("PackageFile")
		local checksum_file := OLD_PACKAGE.updater("ChecksumFile")
		local checksum_type := "SHA1"

		if package_file {
			local package_asset := new Asset(package_file, github_api.GetFileURL(package_file), github_api.GetFileURL(checksum_file), checksum_type)
			local package_path := package_asset.GetAsset(TEMP_DIRECTORY)

			if FileExist(package_path) {
				local new_updater := Format("{1}\{2}", package_path, OLD_PACKAGE.package("Updater", "package-updater.exe"))

				if FileExist(new_updater) {
					NEW_PACKAGE := new Package(new_updater)
					return true
				}
			} else {
				log.crit("Unable to download or verify package asset from '{1}'", github_api.GetFileURL(package_file))
			}
		} else {
			log.crit("Config data incomplete, unable to download package")
		}
	} else {
		log.crit("Unable to get release data from Github")
	}

	return false
}

IsLatestNewer() {
	global
	; TODO: version check
}

KillPackageProcess() {
	global
	local package_process := OLD_PACKAGE.package("Process")

	log.info("Killing process from package '{1}'", package_process)
	Process, Close, % package_process
}

NonInteractiveUpdate() {
	global

	if GetLatestPackage() {
		BackupOldPackage()
		KillPackageProcess()
		RunNewPackage()
	} else {
		MsgBox, Package Updater, Unable to update package
	}
}

RunNewPackage() {
	global
	local new_updater := NEW_PACKAGE.updater_binary
	local old_updater := OLD_PACKAGE.updater_binary

	if (! FileExist(new_updater)) {
		log.crit("Unable to find new package updater binary '{1}'", new_updater)
		return false
	}

	if (! FileExist(old_updater)) {
		log.crit("Unable to find old package updater binary '{1}'", old_updater)
		return false
	}

	log.info("Executing new package updater: '{1} '{2}''", new_updater, old_updater)
	Run %new_updater% "%old_updater%"
}

UpdatePackage() {
	global
	; TODO: finish phase 2
}

; phase 2
; transfer the latest package to the old location
SetLatestPackage(old_updater, new_updater) {
	global SELF, APP_DIRECTORY, TEMP_DIRECTORY, log

	old_package := new Package(old_updater)
	new_package := new Package(new_updater)

	log.info("Preparing to transfer package from '{1}' to '{2}'", new_package.base_directory, old_package.base_directory)
	transfer := new Transfer(new_package.base_directory, old_package.base_directory)

	if transfer {
		complex_paths := new_package.GetComplexPaths()
		transfer.BasicFiles(complex_paths)

		for complex, action in new_package.GetComplexKeys() {
			complex_data := new_package.main_data[complex]
			result := transfer.ComplexFile(complex_data, action)
			log.info("Performed '{1}' on '{2}' (result: {3})", action, complex_data["Path"], result)
		}
	}
}

; entry point
global log := new Logger("updater.ahk")
log.info("===================================")
log.info("= {1} (v{2})", SELF, VERSION)
log.info("===================================")

; create base working directories if they don't exist
for index, dir in [APP_DIRECTORY, TEMP_DIRECTORY] {
	if ! InStr(FileExist(dir), "D") {
		FileCreateDir % dir
		log.verb("Created working temp directory '{1}' (error: {2})", dir, A_LastError)
	}
}

; handle arguments
switch A_Args[1] {
	; standard update process, launch update dialog first
	case "":
		log.info("Executing phase 1 of the update process")
		global OLD_PACKAGE := new Package(A_ScriptFullPath)
		Main_Dialog()

	; run an update without displaying the main dialog
	; message boxes will still appear in phase 2 of the update
	case "-n":
		log.info("Bypassing main dialog and running update")
		global OLD_PACKAGE := new Package(A_ScriptFullPath)
		NonInteractiveUpdate()

	; display version information
	case "-v":
		log.info("Displaying version information")
		About_Dialog(1)

	; execute phase 2 of the update process
	default:
		log.info("Executing phase 2 of the update process")
		global NEW_PACKAGE := new Package(A_ScriptFullPath)
		global OLD_PACKAGE := new Package(A_Args[2])
}

exit
