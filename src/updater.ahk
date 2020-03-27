; updater.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

; download and verify the latest release from github
DownloadLatestRelease(package, github, temp_dir) {
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

; entry point
global self := "package-updater"
global log := new Logger("updater.ahk")
log.verb("=====")

app_dir := Format("{1}\{2}", A_AppData, self)
temp_dir := Format("{1}\{2}", A_Temp, self)
FileCreateDir, %app_dir%
FileCreateDir, %temp_dir%
log.info(Format("Created working directories '{1}' and '{2}'", app_dir, temp_dir))

if A_Args.Length() > 0 {
	; we were run with arguments, this is likely phase two
	; replace the current package with the one supplied in the arguments
	old_package := new Package(A_Args[1])
	new_package := new Package(A_ScriptFullPath)

	log.info(Format("Preparing to transfer package from '{1}' to {2}", new_package.base_directory, old_package.base_directory))
	transfer := new Transfer(new_package.base_directory, old_package.base_directory)

	if transfer {
		watch_paths := new_package.GetWatchPaths()
		transfer.DoBasicFiles(watch_paths)
		transfer.DoComplexFile(new_package.config_data["Watch_Kaillera"])
	}
} else {
	; we were run without arguments, this is likely phase one
	; download/extract the latest release and backup the current package
	current_package := new Package(A_ScriptFullPath)
	current_updater := Format("{1}\{2}", current_package.base_directory, current_package.updater("Updater", "package-updater.exe"))
	github := new GitHub(current_package.updater("Owner"), current_package.updater("Repo"), current_package.updater("Beta"))

	TrayTip, % current_package.package("Name"), % "Updating, please wait..."

	latest_directory := DownloadLatestRelease(current_package, github, temp_dir)

	if latest_directory {
		latest_updater := Format("{1}\{2}", latest_directory, current_package.updater("Updater", "package-updater.exe"))

		; the latest updater exists, backup the old package, kill the process
		; and run the second updater to transfer the files over to the current
		if FileExist(latest_updater) {
			latest_package := new Package(latest_updater)

			current_package.Backup(app_dir, current_package.updater("Backups"))

			log.info(Format("Killing process from package '{1}'", current_package.package("Process")))
			Process, Close, % current_package.package("Process")

			log.info(Format("Executing new updater: '{1} '{2}''", latest_updater, current_updater))
			Run %latest_updater% "%current_updater%"
		} else {
			log.err(Format("Unable to find updater in '{1}'", latest_directory))
			return false
		}
	}
}

log.verb("=====")
exit
