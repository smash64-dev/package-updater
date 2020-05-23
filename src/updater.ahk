; updater.ahk

#NoTrayIcon
#SingleInstance force

#Include %A_LineFile%\..\include.ahk

global AUTHOR := "CEnnis91 © 2020"
global SELF := "package-updater"
global SOURCE := "https://github.com/smash64-dev/package-updater"
global VERSION := "0.10.0"

global APP_DIRECTORY := Format("{1}\{2}", A_AppData, SELF)
global TEMP_DIRECTORY := Format("{1}\{2}", A_Temp, SELF)

; creates a global file handle for this session to write to
FormatTime, LOG_NOW, , yyyy-MM-dd-HHmmss
global LOGGER_LOG_FILE := Format("{1}\{2}.log", TEMP_DIRECTORY, LOG_NOW)
global LOGGER_LOG_FILE_HANDLE := FileOpen(LOGGER_LOG_FILE, "a", 0x200)

; perform a backup on the old package if the config allows
BackupOldPackage(tag := "") {
    global

    local backup_directory := Format("{1}\{2}", APP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))
    FileCreateDir % backup_directory

    if InStr(FileExist(backup_directory), "D") {
        return OLD_PACKAGE.Backup(backup_directory, tag, OLD_PACKAGE.updater("Backups", "10"))
    } else {
        log.warn("Unable to create backup, directory '{1}' does not exist", backup_directory)
        return false
    }
}

; format a version string into v#.#.# format
CleanVersionString(version_text) {
    global

    ; this regex is not the recommeneded regex for semver, but it will work well enough for basic
    ; https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
    RegExMatch(version_text, "^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*).*$", SemVer)
    clean_text := Format("v{1}.{2}.{3}", SemVer1, SemVer2, SemVer3)

    ; minimum string length: v0.0.0 (6)
    if (StrLen(clean_text) < 6) {
        log.warn("Clean version string '{1}' appears invalid", clean_text)
        return false
    } else {
        return clean_text
    }
}

; creates a log file in TEMP_DIRECTORY for viewing
DumpLogFiles(log_name := "lastlog.txt") {
    global

    ; concatenate all the old logs into a single file and open it
    local log_dump := Format("{1}\{2}", TEMP_DIRECTORY, log_name)
    local log_format := Format("{1}\*.log", TEMP_DIRECTORY)
    local log_list := ""

    loop, files, %log_format%
    {
        log_list := log_list . "`n" . A_LoopFileFullPath
    }

    Sort log_list, CL
    log_list_array := StrSplit(log_list, "`n")

    FileDelete, % log_dump
    FileAppend, % "", % log_dump

    for index, log_file in log_list_array {
        if log_file {
            FileRead, log_file_content, % log_file
            FileAppend, % Format("{1}`n`n", log_file_content), % log_dump
        }
    }

    ; if we have an open log, append it to the dump
    if log.log_file {
        FileAppend, % Format("{1}`n`n", log.Dump()), % log_dump
    }

    ; dump information about the current config
    local main_config := OLD_PACKAGE.main_ini.GetJSON()
    local user_config := OLD_PACKAGE.user_ini.GetJSON()
    FileAppend, % "-----------------------------------`n`n`n", % log_dump
    FileAppend, % Format("Package Directory: '{1}'`n`n", OLD_PACKAGE.base_directory), % log_dump
    FileAppend, % Format("Main Config: '{1}'`n`nUser Config: '{2}'`n", main_config, user_config), % log_dump

    return log_dump
}

; clean up the environment and close out log files before exiting
ExitClean(final_message := "") {
    global

    ; clean up old log files, they're text files, we can keep a lot
    old_log_format := Format("{1}\*.log", TEMP_DIRECTORY)
    old_log_list := ""
    old_log_preserve := 25

    loop, files, %old_log_format%
    {
        old_log_list := old_log_list . "`n" . A_LoopFileFullPath
    }

    Sort old_log_list, CLR
    old_log_array := StrSplit(old_log_list, "`n")
    old_log_array.RemoveAt(1, old_log_preserve)

    for index, old_log in old_log_array {
        if old_log {
            FileDelete, % old_log
        }
    }

    ; submit a final log message
    if final_message {
        log.crit("===================================")
        log.crit(final_message)
        log.crit("===================================")
    } else {
        log.crit("===================================")
    }

    ; exit cleanly
    LOGGER_LOG_FILE_HANDLE.Close()
    ExitApp
}

; pulls the latest changelog information from github
; returns the changelog text as a string
GetLatestChangelog() {
    global

    local temp_base := Format("{1}\{2}", TEMP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))
    local github_auth := OLD_PACKAGE.updater("ApiAuth", false) ? OLD_PACKAGE.updater("ApiAuth", false) : ""
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", "0"), github_auth)
    local changelog_text := ""

    if github_api.GetReleases(temp_base) {
        ; gather the changelog data, if any exists
        local changelog_file := OLD_PACKAGE.updater("ChangelogFile")

        if changelog_file {
            local changelog_asset := new Asset(changelog_file, github_api.GetFileURL(changelog_file), "", "None")
            local changelog_path := changelog_asset.GetAsset(temp_base)

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

    local temp_base := Format("{1}\{2}", TEMP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))
    local github_auth := OLD_PACKAGE.updater("ApiAuth", false) ? OLD_PACKAGE.updater("ApiAuth", false) : ""
    local github_api := new GitHub(OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"), OLD_PACKAGE.updater("Beta", "0"), github_auth)

    if github_api.GetReleases(temp_base) {
        local package_file := OLD_PACKAGE.updater("PackageFile")
        local checksum_file := OLD_PACKAGE.updater("ChecksumFile")
        local checksum_type := "SHA1"

        if package_file {
            local package_asset := new Asset(package_file, github_api.GetFileURL(package_file), github_api.GetFileURL(checksum_file), checksum_type)
            local package_path := package_asset.GetAsset(temp_base)

            if FileExist(package_path) {
                local new_updater := Format("{1}\{2}", package_path, OLD_PACKAGE.package("Updater", "package-updater.exe"))

                if FileExist(new_updater) {
                    NEW_PACKAGE := new Package(new_updater)

                    ; basic sanity check of the new package
                    local old_package_config := OLD_PACKAGE.main_ini.GetJSON()
                    local new_package_config := NEW_PACKAGE.main_ini.GetJSON()

                    ; the package looks invalid, but let the process continue
                    if (old_package_config != "{}" and new_package_config == "{}") {
                        log.warn("NEW_PACKAGE '{1}' does not appear to be a valid package", new_package)
                    }

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

    if (! old_id or ! new_id) {
        log.warn("Unable to determine build IDs, reverting to version checks '{1}' vs '{2}'", old_id, new_id)
        old_id := old_version
        new_id := new_version
    }

    log.info("Comparing old: '{1}' vs new: '{2}' (result: {3})", old_id, new_id, old_id == new_id)
    return old_id == new_id
}

; kill any existing process, pulled from the config
KillPackageProcess() {
    global

    local package_process := OLD_PACKAGE.package("Process", 0)

    if package_process {
        log.info("Killing process from package '{1}'", package_process)
        Process, Close, % package_process
    } else {
        log.warn("Unable to find process from package '{1}'", package_process)
    }
}

; perform an update without any user interaction
NonInteractiveUpdate() {
    global

    local latest_version := GetLatestPackage()
    if ! IsCurrentLatest(latest_version) {
        BackupOldPackage("auto")
        KillPackageProcess()

        local run_result := RunNewPackage()
        if ! run_result {
            ExitClean("There was an error executing the new package")
        } else {
            ExitClean()
        }
    } else {
        ExitClean("There was an issue running the update non-interactively")
    }
}

; ask or tell the user about the updater change
NotifyCallback(complex_data) {
    global

    local show_remember := NEW_PACKAGE.gui("ShowRemember", 0)
    local response := Change_Notification_Dialog(complex_data, show_remember)

    local answer := response[1]
    local remember := response[2]
    local remember_value := answer ? "Allow" : "Deny"
    log.verb("User response: answer: '{1}' and remember: '{2}' ({3})", answer, remember, remember_value)

    if (complex_data["Notify"] == "Tell") {
        log.verb("Notify was 'Tell': Allow action")
        return answer
    }

    if (complex_data["Notify"] == "Ask" and remember) {
        NEW_PACKAGE.UpdateUserProperty(complex_data["__SectionName__"], "Remember", remember_value)
    }

    log.verb("Notify was 'Ask': {1} action", remember_value)
    return answer
}

; perform an update check only without any user interaction
; displays a message box if an update is present, exits quietly otherwise
QuietUpdateCheck() {
    global

    ; FIXME: this doesn't respect or integrate with ExitClean() well
    local latest_version := GetLatestPackage()

    if ! IsCurrentLatest(latest_version) {
        Update_Available_Dialog(latest_version)
    } else {
        log.info("Package appears to be the latest version '{1}'", latest_version)
    }
}

; records the update action in the user config for debugging purposes later
RecordUpdate(update_type := "unknown") {
    global

    ; record this update action in the user config
    local record_obj := {}
    record_obj.in_beta := OLD_PACKAGE.updater("Beta", "0")
    record_obj.old_ver := CleanVersionString(OLD_PACKAGE.package("Version", "0.0.0"))
    record_obj.old_id := OLD_PACKAGE.package("BuildId", "0")
    record_obj.new_ver := CleanVersionString(NEW_PACKAGE.package("Version", "0.0.0"))
    record_obj.new_id := NEW_PACKAGE.package("BuildId", "0")
    record_obj.type := update_type

    ; build a json string and base64 it, to store cleaner
    local record_json := JSON.Dump(record_obj)
    local record_base64 := LC_Base64_EncodeText(record_json)

    FormatTime, now, , yyyyMMddHHmmss
    log.info("Recording update in history: '{1}={2}'", now, record_json)
    OLD_PACKAGE.UpdateUserProperty("Update_History", now, record_base64)
    return true
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

; start the package process, pulled from the config
RunPackageProcess(use_gui := 0) {
    global

    local auto_start := OLD_PACKAGE.updater("AutoStart", 0)
    local package_process := OLD_PACKAGE.path(NEW_PACKAGE.package("Process"))

    if (auto_start) {
        log.info("Executing new package process: '{1}'", package_process)

        if FileExist(package_process) {
            Run %package_process%
        } else {
            log.err("Package process '{1}' does not exist, not running", package_process)

            if use_gui {
                local fail_title := "Error"
                local fail_message := Format("Unable to find process '{1}'.", package_process)
                MsgBox, % (0x10 | 0x2000), % fail_title, % fail_message
            }
        }
    } else {
        log.info("Not executing new package: '{1}', autostart disabled", package_process)
    }
}

; execute an extra, external program after updating
RunPostUpdate(use_gui := 0) {
    global

    local post_update := OLD_PACKAGE.path(NEW_PACKAGE.updater("PostUpdate", 0))
    local version := CleanVersionString(NEW_PACKAGE.package("Version", "0.0.0"))

    if (post_update) {
        log.info("Executing post update program: '{1}'", post_update)

        if FileExist(post_update) {
            RunWait %post_update% "%version%"

            if ! ErrorLevel {
                log.warn("Post update program returned with an error code '{1}'", ErrorLevel)
            } else {
                log.info("Post update program returned with no errors")
            }
        } else {
            log.warn("Post update program '{1}' does not exist, not running", post_update)

            if use_gui {
                local warning_title := "Warning"
                local warning_message := Format("Unable to find post update program '{1}'.", post_update)
                MsgBox, % (0x30 | 0x2000), % warning_title, % warning_message
            }
        }
    } else {
        log.info("No post update program to execute '{1}", post_update)
    }
}

; used in phase 2 of an update "NEW_PACKAGE"
; performs the update and transfers important files to "OLD_PACKAGE"
UpdatePackage(force := 0) {
    global

    log.info("Preparing to transfer package from '{1}' to '{2}'", NEW_PACKAGE.base_directory, OLD_PACKAGE.base_directory)

    if (force) {
        show_progress := false
        transfer := new Transfer(NEW_PACKAGE.base_directory, OLD_PACKAGE.base_directory)
    } else {
        show_progress := true
        show_progress_title := Format("Updating {1}", NEW_PACKAGE.gui("Name", SELF ? SELF : "package-updater"))
        transfer := new Transfer(NEW_PACKAGE.base_directory, OLD_PACKAGE.base_directory, Func("NotifyCallback"))
        Show_Progress(show_progress_title)
    }

    if transfer {
        local complex_paths := new_package.GetComplexPaths()
        local complex_keys := new_package.GetComplexKeys()

        ; calculate what percent of basic files translates to progress
        local basic_percent := NEW_PACKAGE.gui("BasicProgress", "0.5")
        local total_actions := complex_keys.Count() / (1 - basic_percent)
        local basic_actions := total_actions * basic_percent
        transfer.BasicFiles(complex_paths)

        if show_progress {
            ; yes, we artificially add delays to make the the progress bar look better
            Show_Progress(show_progress_title, basic_actions/total_actions)
            Sleep 1000
        }

        for complex, action in complex_keys {
            ; get the complex data, inject the section name into the object
            local complex_data := new_package.main_data[complex]
            complex_data["__SectionName__"] := complex

            if show_progress {
                Show_Progress(show_progress_title, (basic_actions + A_Index)/total_actions)
            }

            local result := transfer.ComplexFile(complex_data, action)
            if (result) {
                log.info("Performed '{1}' on '{2}'", action, complex_data["Path"])
            } else {
                log.info("Did not perform '{1}' on '{2}'", action, complex_data["Path"])
            }
        }

        if show_progress {
            Show_Progress(show_progress_title, -3, "Update complete!")
        }

        ; runs an external program post update, if one exists
        RunPostUpdate(show_progress)

        ; runs the package process if autostart is enabled
        RunPackageProcess(show_progress)
    } else {
        if show_progress {
            local fail_title := "Error"
            local fail_message := Format("There was a problem transferring data.")
            MsgBox, % (0x10 | 0x2000), % fail_title, % fail_message
        }
        ExitClean("There was an issue creating the transfer object, transfer failed")
    }
    ExitClean()
}

; entry point
global log := new Logger("updater.ahk")
log.crit("===================================")
log.crit("= {1} (v{2})", SELF, VERSION)
log.crit("===================================")

; create base working directories if they don't exist
for index, dir in [APP_DIRECTORY, TEMP_DIRECTORY] {
    if ! InStr(FileExist(dir), "D") {
        FileCreateDir % dir
        log.verb("Created working temp directory '{1}' (error: {2})", dir, A_LastError)
    }
}

log.info("Processing arguments: {1} {2} {3}", A_ScriptFullPath, A_Args[1], A_Args[2])

; handle arguments
switch A_Args[1] {
    ; check for updates quietly, and only notify the user if
    ; there is a new update, this is ignorable via user config
    case "-c", "--check-updates":
        log.info("Quietly checking for updates")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        QuietUpdateCheck()

    ; display help information
    case "-h", "--help":
        log.info("Displaying help information")
        Help_Dialog(1)

    ; run an update without displaying the main dialog
    ; message boxes will still appear in phase 2 of the update
    case "-n", "--non-interactive":
        log.info("Bypassing main dialog and running update")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        NonInteractiveUpdate()

    ; run a self update, this applies the config to yourself
    ; non-interactively, this is useful for development purposes
    case "-s", "--self-quiet":
        log.info("Updating self package")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        global NEW_PACKAGE := new Package(A_ScriptFullPath)
        RecordUpdate("self-auto")
        UpdatePackage(1)

    ; run a self update, this applies the config to yourself
    ; interactively, this is useful for development purposes
    case "--self-update":
        log.info("Updating self package")
        global OLD_PACKAGE := new Package(A_ScriptFullPath)
        global NEW_PACKAGE := new Package(A_ScriptFullPath)
        RecordUpdate("self-user")
        UpdatePackage(0)

    ; display version information
    case "-v", "--version":
        log.info("Displaying version information")
        About_Dialog(1)

    default:
        if FileExist(A_Args[1]) {
            ; execute phase 2 of the update process
            log.info("Executing phase 2 of the update process")
            global OLD_PACKAGE := new Package(A_Args[1])

            ; load OLD_PACKAGE user config into NEW_PACKAGE
            ; we have to transfer both user_config_path and user_ini
            global NEW_PACKAGE := new Package(A_ScriptFullPath)
            NEW_PACKAGE.user_config_path := OLD_PACKAGE.user_config_path
            NEW_PACKAGE.user_ini := OLD_PACKAGE.user_ini
            NEW_PACKAGE.ReloadConfigFromDisk(1)

            RecordUpdate("user")
            UpdatePackage(0)
        } else {
            ; standard update process, launch update dialog first
            log.info("Executing phase 1 of the update process")
            global OLD_PACKAGE := new Package(A_ScriptFullPath)
            Main_Dialog()
        }
}

exit
