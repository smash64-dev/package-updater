; updater.ahk

#NoTrayIcon
#Include %A_LineFile%\..\lib\github.ahk
#Include %A_LineFile%\..\lib\json.ahk
#Include %A_LineFile%\..\lib\libcrypt.ahk
#Include %A_LineFile%\..\lib\logger.ahk
#Include %A_LineFile%\..\lib\package.ahk
#Include %A_LineFile%\..\lib\zip.ahk

; backup the entire package directory, just in case
; restoration is a manual process, for now
BackupOldPackage(package, save_dir) {
	FormatTime, now,, yyyy-MM-dd-HHmmss
	source := package.updater("Source")
	repo := StrSplit(source, "/")

	backup_zip := Format("{1}\backup-{2}-{3}.zip", save_dir, repo[2], now)
	log.info(Format("Zipping '{1}' to '{2}'", package.base_directory, backup_zip))
	;Zip(package.base_directory, backup_zip)

	; trim old backups to package specification
	; finds all the backup files, sorts by name (!) and keeps the latest X
	; TODO: sort by file creation time
	keep_old := package.updater("Backups")
	backup_list := ""

	loop %save_dir%\*.* {
		backup_list := backup_list . "`n" . A_LoopFileName
	}
	Sort backup_list, CLR
	backup_array := StrSplit(backup_list, "`n")
	backup_array.RemoveAt(1, keep_old)

	for index, backup in backup_array {
		if backup {
			log.info(Format("Removing backup file '{1}\{2}'", save_dir, backup))
			FileDelete, % Format("{1}\{2}", save_dir, backup)
		}
	}
}

; download and verify the latest release from github
DownloadLatestRelease(package, github, temp_dir) {
	; queries the API for the latest release information
	release_json := Format("{1}\{2}.json", temp_dir, package.package("Name"))
	UrlDownloadToFile % github.release_url, %release_json%

	; find the urls we need to download with
	found_release := github.LoadJSON(release_json)
	if found_release {
		found_assets := github.FindAssets(package.updater("PackageFile"), package.updater("ChecksumFile"))
	} else {
		log.err(Format("Unable to find proper release data in '{1}'", release_json))
		return false
	}

	; download the proper assets
	if found_assets {
		; download the full package
		SplitPath % github.package_url, package_filename
		package_path := Format("{1}\{2}", temp_dir, package_filename)
		UrlDownloadToFile % github.package_url, %package_path%
		log.info(Format("Downloaded '{1}' to '{2}' (Result: {3})", github.package_url, package_path, ErrorLevel))
		
		; download the checksum file to validate our package
		SplitPath % github.checksum_url, checksum_filename
		checksum_path := Format("{1}\{2}", temp_dir, checksum_filename)
		UrlDownloadToFile % github.checksum_url, %checksum_path%
		log.info(Format("Downloaded '{1}' to '{2}' (Result: {3})", github.checksum_url, checksum_path, ErrorLevel))
	} else {
		log.err(Format("Unable to find appropriate assets to download from '{1}'", release_json))
		return false
	}

	; verify the package downloaded correctly
	if (FileExist(checksum_path) and FileExist(package_path)) {
		package_checksum := LC_FileSHA(package_path)

		FileRead, valid_contents, %checksum_path%
		valid_array := StrSplit(valid_contents, " ")
		log.info(Format("Checksum comparison '{1}' vs '{2}'", package_checksum, valid_array[1]))

		if (package_checksum == valid_array[1]) {
			log.info("Checksums match!")
			return package_path
		} else {
			log.warn("Checksums mismatch!")
			return false
		}
	} else {
		log.err(Format("Unable to find all downloaded assets '{1}' and '{2}'", checksum_path, package_path))
		return false
	}

	return false
}

ExtractNewPackage(package_path, extract_dir) {
	log.info(Format("Extracting package '{1}' to '{2}'", package_path, extract_dir))

	FileRemoveDir, %extract_dir%, 1
	FileCreateDir, %extract_dir%
	Unz(package_path, extract_dir)
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

	log.info(Format("Preparing to update package '{1}' to {2}", old_package.base_directory, new_pkg.base_directory))
} else {
	; we were run without arguments, this is likely phase one
	; download/extract the latest release and backup the current package
	current_package := new Package(A_ScriptFullPath)
	github := new GitHub(current_package.updater("Source"), current_package.updater("Beta"))

	latest_release := DownloadLatestRelease(current_package, github, temp_dir)
	latest_directory := Format("{1}\{2}-latest", temp_dir, current_package.package("Name"))

	if latest_release {
		BackupOldPackage(current_package, app_dir)
		ExtractNewPackage(latest_release, latest_directory)

		latest_updater := Format("{1}\{2}", latest_directory, current_package.updater("Updater", "package-updater.exe"))
		latest_package := new Package(latest_updater)
		log.info(Format("Validating latest package by checking for '{1}'", latest_updater))

		; the latest package parsed, run that updater
		if latest_package {
			Process, Close, % current_package.package("Process")
			Run, % latest_package.updater("Updater") . " " . current_package.updater("Updater")
		}
	}
}

log.verb("=====")
exit