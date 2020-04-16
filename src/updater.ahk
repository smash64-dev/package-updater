; updater.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global AUTHOR := "CEnnis91 © 2020"
global SELF := "package-updater"
global SOURCE := "https://github.com/smash64-dev/package-updater"
global VERSION := "1.0.0"

global APP_DIRECTORY := Format("{1}\{2}", A_AppData, SELF)
global TEMP_DIRECTORY := Format("{1}\{2}", A_Temp, SELF)

; perform a backup on the old package if the config allows
BackupOldPackage() {
    global

    OLD_PACKAGE.Backup(APP_DIRECTORY, OLD_PACKAGE.updater("Backups", "10"))
}

; format a version string into v#.#.# format
CleanVersionString(version_text) {
    global

    ; this regex is not the recommeneded regex for semver, but it will work well enough for basic
    ; https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
    RegExMatch(version_text, "^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*).*$", SemVer)
    clean_text := Format("v{1}.{2}.{3}", SemVer1, SemVer2, SemVer3)

    ; minimum string length: v0.0.0 (6)
    if (StrLen(clean_text) < 6)
        return false
    else
        return clean_text
}

; pulls the latest changelog information from github
; returns the changelog text as a string
GetLatestChangelog() {
    global

    local github_auth := OLD_PACKAGE.updater("ApiAuth", false) ? OLD_PACKAGE.updater("ApiAuth", false) : ""
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", "0"), github_auth)
    local changelog_text := ""

    if github_api.GetReleases(TEMP_DIRECTORY) {
        ; gather the changelog data, if any exists
        local changelog_file := OLD_PACKAGE.updater("ChangelogFile")

        if changelog_file {
            local changelog_asset := new Asset(changelog_file, github_api.GetFileURL(changelog_file), "", "None")
            local changelog_path := changelog_asset.GetAsset(TEMP_DIRECTORY)

            if (changelog_path and FileExist(changelog_path)) {
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

; determines and downloads the latest new package
; returns the version on success, false on failure
GetLatestPackage() {
    global

    local github_auth := OLD_PACKAGE.updater("ApiAuth", false) ? OLD_PACKAGE.updater("ApiAuth", false) : ""
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", "0"), github_auth)

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

                    local latest_version := github_api.latest_build.tag_name
                    log.info("New version found, tag name '{1}'", latest_version)
                    return latest_version
                } else {
                    log.crit("Unable to find new updater '{1}'", new_updater)
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

; determine if the current version is different from the latest version
; returns true if the version ids match, false if not
;
; NOTE: this function has no concept of "upgrading" and "downgrading"
; it is only important that the version information is different, as all package
; updates are handled on github (or another service), and packages act like
; a configuration management tool, we only care what the server says is latest
; this can create odd behavior when jumping between beta/official branches
;
; build IDs within the package config are the primary way to determine if a build
; is different; these can be commit IDs and automatically generated with git archive
; if unique build IDs don't exist, the version string will be used
IsCurrentLatest(latest_version) {
    global

    local old_id := OLD_PACKAGE.package("BuildId", false)
    local old_version := CleanVersionString(OLD_PACKAGE.package("Version", "0.0.0"))

    local new_id := NEW_PACKAGE.package("BuildId", false)
    local new_version := CleanVersionString(latest_version)

    if (! old_build_id or ! new_build_id) {
        log.warn("Unable to determine build IDs, reverting to version checks")
        old_id := old_version
        new_id := new_version
    }

    log.info("Comparing old: '{1}' vs new: '{2}' (result: {3})", old_id, new_id, old_id == new_id)
    return old_id == new_id
}

; kill any existing process, pulled from the config
KillPackageProcess() {
    global

    local package_process := OLD_PACKAGE.package("Process")
    log.info("Killing process from package '{1}'", package_process)
    Process, Close, % package_process
}

; perform an update without any user interaction
NonInteractiveUpdate() {
    global

    local latest_version := GetLatestPackage()
    if ! IsCurrentLatest(latest_version) {
        BackupOldPackage()
        KillPackageProcess()
        RunNewPackage()
    } else {
        MsgBox, Package Updater, Unable to update package
        ExitApp
    }
}

; perform an update check only without any user interaction
; displays a message box if an update is present, exits quietly otherwise
QuietUpdateCheck() {
    global

    local latest_version := GetLatestPackage()
    if ! IsCurrentLatest(latest_version) {
        Update_Available_Dialog(latest_version)
    }
}

; transition to the new updater binary to continue the update
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

; used in phase 2 of an update "NEW_PACKAGE"
; performs the update and transfers important files to "OLD_PACKAGE"
UpdatePackage() {
    global

    MsgBox, Package Updater, This is Phase #2
    ExitApp
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
global log := new Logger("updater.ahk", "V")
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
    ; run an update without displaying the main dialog
    ; message boxes will still appear in phase 2 of the update
    case "-n":
        log.info("Bypassing main dialog and running update")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        NonInteractiveUpdate()

    ; check for updates quietly, and only notify the user if
    ; there is a new update, this is ignorable via user config
    case "-q":
        log.info("Quietly checking for updates")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        QuietUpdateCheck()

    ; display version information
    case "-v":
        log.info("Displaying version information")
        About_Dialog(1)

    default:
		if FileExist(A_Args[1]) {
			; execute phase 2 of the update process
			log.info("Executing phase 2 of the update process")
			global NEW_PACKAGE := new Package(A_ScriptFullPath)
			global OLD_PACKAGE := new Package(A_Args[1])
			UpdatePackage()
		} else {
			; standard update process, launch update dialog first
			log.info("Executing phase 1 of the update process")
			global OLD_PACKAGE := new Package(A_ScriptFullPath)
			Main_Dialog()
		}
}

exit
