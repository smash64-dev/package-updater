; updater.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global SELF := "package-updater"
global VERSION := "1.0.0"
global log := new Logger("updater.ahk")

; download and verify the latest release from github
DownloadLatestPackage(package, github, temp_dir) {
	found_release := github.GetReleases(temp_dir)

	if found_release {
		package_url := github.GetFileURL(package.updater("PackageFile"))
		checksum_url := github.GetFileURL(package.updater("ChecksumFile"))

		asset := new Asset(package.updater("PackageFile"), package_url, checksum_url, "SHA1")
		asset_location := asset.GetAsset(temp_dir)

		if FileExist(asset_location) {
			return asset_location
		} else {
			log.warn(Format("Unable to find asset '{1}'", asset_location))
			return false
		}
	} else {
		log.err(Format("Unable to find proper release data in '{1}'", release_json))
		return false
	}
}

; phase 1
; grab the latest package to update to
GetLatestPackage(old_updater) {
	global SELF, app_directory, temp_directory, log

	old_package := new Package(old_updater)
	github := new GitHub(old_package.updater("Owner"), old_package.updater("Repo"), old_package.updater("Beta", "0"))

	latest_directory := DownloadLatestPackage(old_package, github, temp_directory)

	if latest_directory {
		new_updater := Format("{1}\{2}", latest_directory, old_package.updater("Updater", "package-updater.exe"))

		; the latest updater exists, backup the old package, kill the process
		; and run the second updater to transfer the files over to the current
		if FileExist(new_updater) {
			old_package.Backup(app_directory, old_package.updater("Backups", "10"))
			kill_process := old_package.package("Process")
			new_package := new Package(new_updater)

			if kill_process and new_package {
				log.info(Format("Killing process from package '{1}'", kill_process))
				Process, Close, % kill_process

				log.info(Format("Executing new updater: '{1} '{2}''", new_updater, old_updater))
				Run %new_updater% "%old_updater%"

				return true
			}
		} else {
			log.err(Format("Unable to find updater in '{1}'", latest_directory))
			return false
		}
	}
}

; phase 2
; transfer the latest package to the old location
SetLatestPackage(old_updater, new_updater) {
	global SELF, app_directory, temp_directory, log

	old_package := new Package(old_updater)
	new_package := new Package(new_updater)

	log.info(Format("Preparing to transfer package from '{1}' to {2}", new_package.base_directory, old_package.base_directory))
	transfer := new Transfer(new_package.base_directory, old_package.base_directory)

	if transfer {
		watch_paths := new_package.GetWatchPaths()
		transfer.DoBasicFiles(watch_paths)
		transfer.DoComplexFile(new_package.config_data["Watch_Kaillera"])
	}
}

ShowVersionInformation() {
	global SELF, VERSION
	MsgBox, 0, % SELF, % Format("Version: v{1}", VERSION)
	return true
}

; entry point
log.verb("===================================")
log.verb(Format("= {1} (v{2})", SELF, VERSION))
log.verb("===================================")

global app_directory := Format("{1}\{2}", A_AppData, SELF)
FileCreateDir % app_directory
log.info(Format("Created working app directory '{1}' ({2})", app_directory, ErrorLevel))

global temp_directory := Format("{1}\{2}", A_Temp, SELF)
FileCreateDir % temp_directory
log.info(Format("Created working temp directory '{1}' ({2})", temp_directory, ErrorLevel))

switch A_Args[1] {
	case "":	GetLatestPackage(A_ScriptFullPath)
	case "-v":	ShowVersionInformation()
	default:	SetLatestPackage(A_Args[1], A_ScriptFullPath)
}

exit
