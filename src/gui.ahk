; gui.ahk

About_Dialog(about_only := 0) {
    global

    local title := "About"
    local version_text := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    local description_text := "Generic zip package update utility written in AutoHotkey"
    local author_text := Format("Copyright: {1}", AUTHOR ? AUTHOR : "Unknown")
    local source_text := SOURCE ? SOURCE : "https://www.github.com"

    MsgBox, % (0x40 | 0x2000), % title, % Format("{1}`n{2}`n`n{3}`n{4}", version_text, description_text, author_text, source_text)

    if about_only
        ExitClean()
    else
        return
}

Beta_Checkbox(enable_when_valid := 1) {
    global

    local beta_message := ""
    local beta_configurable := ""

    if (OLD_PACKAGE.updater("Beta", "0") == "-1") {
        beta_message := "Beta feature is currently unavailable"
        GuiControl, Text, Beta, % Format("{1}{2}", beta_message, beta_configurable)
        GuiControl, Disable, Beta
        return
    } else {
        beta_message := "Update to beta releases, when available"
    }

    if (! OLD_PACKAGE.__CanUpdateUserProperty("Updater", "Beta")) {
        beta_configurable := " (not user configurable)"
        GuiControl, Disable, Beta
    } else {
        if (enable_when_valid) {
            GuiControl, Enable, Beta
        } else {
            GuiControl, Disable, Beta
        }
    }

    local updater_beta := OLD_PACKAGE.updater("Beta", "0")
    if (updater_beta != "0" and updater_beta != "1") {
        OLD_PACKAGE.UpdateUserProperty("Updater", "Beta", "0")
        updater_beta := "0"
    }

    GuiControl, Text, Beta, % Format("{1}{2}", beta_message, beta_configurable)
    GuiControl,, Beta, % OLD_PACKAGE.updater("Beta", "0")
    return
}

Beta_Warning_Dialog() {
    global

    local beta_changed := false
    local warning_title := "Warning"
    local warning_text := ""

    local base_text := "Are you sure you want to receive beta releases?"
    local custom_text := OLD_PACKAGE.gui("BetaWarning", false)

    if (custom_text) {
        warning_text := Format("{1}`n`n{2}", custom_text, base_text)
    } else {
        warning_text := Format("{1}", base_text)
    }

    GuiControlGet, beta_precheck,, Beta
    if beta_precheck {
        MsgBox, % (0x4 | 0x30 | 0x100 | 0x2000), % warning_title, % warning_text

        IfMsgBox, Yes
        {
            GuiControl,, Beta, 1
            beta_changed := true
        }

        IfMsgBox, No
        {
            GuiControl,, Beta, 0
            beta_changed := false
        }
    } else {
        beta_changed := true
    }

    GuiControlGet, beta_final,, Beta
    if (beta_changed) {
        OLD_PACKAGE.UpdateUserProperty("Updater", "Beta", beta_final)
        return true
    } else {
        return false
    }
}

Change_Notification_Dialog(complex_data, remember := 0) {
    global

    switch complex_data["Ensure"] {
        case "Absent":      verb := "remove"
        case "Directory":   verb := "create"
        case "Duplicate":   verb := "copy"
        case "Latest":      verb := "update"
        case "Link":        verb := "create"
        case "Present":     verb := "create"
        case "Rename":      verb := "move"
        default:            verb := "update"
    }

    switch complex_data["Type"] {
        case "Ini":         verb_extra := " part of "
        default:            verb_extra := ""
    }

    title := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    allow := "Yes", deny := "No", okay := "OK"

    switch complex_data["Notify"] {
        case "Ask":
            ask_tell := "Do you want to make this change?"
            button_text := Format("{1}|{2}", allow, deny)

        case "Tell":
            ask_tell := "This change is required."
            button_text := Format("{1}", okay)
            remember := ""
    }

    check_text := remember ? "Remember my choice" : ""

    if (A_OSVersion == "WIN_XP" or A_OSVersion == "WIN_2000") {
        message_format := "{1} would like to {2}{3} your {4} ({5}).`n`n{6}"
        message := Format(message_format, NEW_PACKAGE.gui("Name", SELF ? SELF : "package-updater"), verb, verb_extra, complex_data["Name"], complex_data["Path"], ask_tell)

        response := MsgBoxEx(message, title, button_text, 5, check_text, "-SysMenu")
    } else {
        message_format := "{1} would like to {2}{3} your {4} ({5})."
        message := Format(message_format, NEW_PACKAGE.gui("Name", SELF ? SELF : "package-updater"), verb, verb_extra, complex_data["Name"], complex_data["Path"])
        message_2 := Format("{1}", ask_tell)
        reason := complex_data["Reason"] ? complex_data["Reason"] : ""

        result := TaskDialogDirect(message, message_2, title, button_text, 101, 0xFFFD, 0x40, check_text, reason, "Less Info", "More Info", 1)
        response := result[1]
        check_text := result[2]
    }

    switch response {
        case allow:     return [1, check_text == 1 ? true : false]
        case deny:      return [0, check_text == 1 ? true : false]
        case okay:      return [1, false]
        default:        return [1, false]
    }
}

Check_For_Updates() {
    global
    progress_title := Format("Checking for Updates...")
    Show_Progress(progress_title)

    ; give some kind of status text while we wait
    GuiControl, Text, Header, Checking for Updates
    GuiControl, Text, Description, Please wait, this will only take a few seconds...
    GuiControl, Text, CheckUpdates, Checking...

    GuiControl, Disable, LocalUpdate
    GuiControl, Disable, RerunUpdate
    GuiControl, Disable, Update
    GuiControl, Disable, CheckUpdates

    ; pull down the latest package info
    ; there's only 2 things we need to do, get the changelog and package
    local header := ""
    local desc_1 := ""
    local desc_2 := ""

    local changelog_text := GetLatestChangelog()
    Show_Progress(progress_title, 50)
    GuiControl, Text, Changelog, % changelog_text

    local latest_version := GetLatestPackage()
    Show_Progress(progress_title, 100)

    local package_name := OLD_PACKAGE.gui("Name", false)
    local updater_beta := OLD_PACKAGE.updater("Beta", "0")
    local old_version := CleanVersionString(OLD_PACKAGE.package("Version", "0.0.0"))
    local new_version := CleanVersionString(latest_version)

    if (! new_version) {
        header := "Whoops, something happened!"
        desc_1 := Format("Unable to get release information about the package.")
        desc_2 := Format("Check 'More Info' for more information, and then try again in a few minutes.")

        GuiControl, Text, Header, % Format("{1}", header)
        GuiControl, Text, Description, % Format("{1}`n{2}", desc_1, desc_2)
        GuiControl, Hide, LocalUpdate
        GuiControl, Hide, RerunUpdate
        GuiControl, Hide, Update
        GuiControl, Text, CheckUpdates, Check for Updates
        GuiControl, Enable, CheckUpdates

        Show_Progress(progress_title, -3, "Error checking for update!")
        return false
    }

    if ! IsCurrentLatest(latest_version) {
        if package_name
            header := Format("{1} has a new version available!", package_name)
        else
            header := Format("A new version version is available!")

        desc_1 := Format("The latest release available is {1} — you have {2}.", new_version, old_version)
        desc_2 := Format("Would you like to download and install it now?")

        GuiControl, Hide, LocalUpdate
        GuiControl, Enable, LocalUpdate
        GuiControl, Hide, RerunUpdate
        GuiControl, Enable, RerunUpdate
        GuiControl, Show, Update
        GuiControl, Enable, Update

    } else {
        if package_name
            header := Format("{1} is all up to date!", package_name)
        else
            header := Format("You're all up to date!")

        desc_1 := Format("You currently have the latest version — {1}.", old_version)
        desc_2 := Format("To get the latest information about the project, click 'More Info'.")

        GuiControl, Hide, LocalUpdate
        GuiControl, Enable, LocalUpdate
        GuiControl, Show, RerunUpdate
        GuiControl, Enable, RerunUpdate
        GuiControl, Hide, Update
        GuiControl, Enable, Update
    }

    GuiControl, Text, Header, % Format("{1}", header)
    GuiControl, Text, Description, % Format("{1}`n{2}", desc_1, desc_2)
    GuiControl, Text, CheckUpdates, Check for Updates
    GuiControl, Enable, CheckUpdates

    Show_Progress(progress_title, -3, "Check complete!")
    return true
}

Help_Dialog(help_only := 0) {
    global

    local title := "Help"
    local version_text := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    local cmdline_text := Format("{1} [-c] [-h] [-n] [-q] [-s] [-v]", A_ScriptName)

    local cmd_check := Format("    -c, --check-updates: Quietly checks for updates")
    local cmd_help := Format("    -h, --help: Displays this help dialog")
    local cmd_noni := Format("    -n, --non-interactive: Runs a non-interactive update")
    local cmd_self := Format("    -s, --self-quiet: Updates self non-interactively`n    --self-update: Updates self interactively")
    local cmd_version := Format("    -v, --version: Displays an about dialog")
    local cmd_default := Format("Running {1} without arguments will run a normal update process with a dialog and interactive options.", A_ScriptName)

    local cmdline_description := Format("{1}`n{2}`n{3}`n{4}`n{5}`n`n{6}", cmd_check, cmd_help, cmd_noni, cmd_self, cmd_version, cmd_default)
    MsgBox, % (0x40 | 0x2000), % title, % Format("{1}`n{2}`n`n{3}", version_text, cmdline_text, cmdline_description)

    if help_only
        ExitClean()
    else
        return
}

Main_Dialog() {
    global

    ; needed for registering the trigger to open the menu bar
    static double_click_count := 0

    local title := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    local exe_path := OLD_PACKAGE.path(OLD_PACKAGE.package("Process"))

    local icon_no := OLD_PACKAGE.gui("IconNumber", "1")
    local icon_res := "64"
    local icon_data := Format("w{1} h{1} Icon{2}", icon_res, icon_no)
    local exe_icon := LoadPicture(A_IsCompiled ? exe_path : "AutoHotkey.exe", icon_data)

    local header_text := ""
    local description_text := ""
    local changelog_text := ""

    local github_home := Format("{1}/{2}/{3}", "https://www.github.com", OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"))
    local more_info_text := OLD_PACKAGE.gui("MoreInfo", github_home)

    ; build gui skeleton
    Gui, Main:New, -MaximizeBox -MinimizeBox
    Gui, Main:+LabelMainGui +LastFound
    Gui, Main:Default
    Main_Dialog_MenuBar()

    Gui, Main:Add, Picture, x12 y09 w64 h64 vExeIcon gExeIcon

    Gui, Main:Font, S12 CDefault Bold, Verdana
    Gui, Main:Add, Text, x92 y09 w470 h20 vHeader
    Gui, Main:Font, S8 CDefault Norm, Verdana
    Gui, Main:Add, Text, x92 y39 w470 h33 vDescription

    Gui, Main:Font, S8 CDefault Bold, Verdana
    Gui, Main:Add, GroupBox, x82 y79 w480 h230, Release Notes
    Gui, Main:Font, S8 CDefault Norm, Verdana
    Gui, Main:Add, Link, x492 y79 w60 h20 vMoreInfo
    Gui, Main:Add, Edit, x92 y99 w460 h200 vChangelog +ReadOnly -TabStop
    Gui, Main:Add, CheckBox, x82 y319 w480 h20 vBeta gMainBeta

    Gui, Main:Add, Button, x432 y359 w130 h30 vCheckUpdates, Check for Updates
    Gui, Main:Add, Button, x312 y359 w110 h30 vLocalUpdate, Local Update
    Gui, Main:Add, Button, x312 y359 w110 h30 vRerunUpdate, Rerun Update
    Gui, Main:Add, Button, x312 y359 w110 h30 vUpdate, Update
    Gui, Main:Add, Button, x82 y359 w100 h30 vAbout, About
    GuiControl, Focus, Check for Updates

    ; fill in control data
    GuiControl,, ExeIcon, HBITMAP:%exe_icon%
    GuiControl, Text, Header, % header_text
    GuiControl, Text, Description, % description_text
    GuiControl, Text, MoreInfo, <a href="%more_info_text%">More Info</a>
    GuiControl, Text, Changelog, % changelog_text

    GuiControl, Hide, LocalUpdate
    GuiControl, Hide, RerunUpdate
    GuiControl, Hide, Update

    ; build and set the beta checkbox
    Beta_Checkbox(0)

    ; display gui and immediately check for updates
    Gui, Main:Show, Center AutoSize, % title
    Gosub, MainButtonCheckForUpdates
    return

    ; register events that occur on the icon
    ExeIcon:
        if (A_GuiControlEvent == "DoubleClick") {
            double_click_count := double_click_count + 1

            ; require 2 double click events before we toggle it
            ; this should cut down on accidental activation
            if (double_click_count >= 2) {
                double_click_count := 0
                Toggle_Main_Dialog_Menu()
            }
        }
        return

    ; check for beta releases, auto refresh if it changes
    MainBeta:
        if Beta_Warning_Dialog() {
            Check_For_Updates()
        }
        return

    ; display dialog about package-updater
    MainButtonAbout:
        About_Dialog(0)
        return

    ; check for updates
    MainButtonCheckForUpdates:
        Beta_Checkbox(0)
        Check_For_Updates()
        Beta_Checkbox(1)
        return

    ; update to a local package
    MainButtonLocalUpdate:
        Run_Update()
        return

    ; reapply the update from this version
    MainButtonRerunUpdate:
        Run_Update(1)
        return

    ; update to the latest version
    MainButtonUpdate:
        Run_Update()
        return

    MainGuiClose:
        Gui, Main:Destroy
        ExitClean()
}

Main_Dialog_MenuBar() {
    global

    ; file menu definition
    always_show_menu := "&Always Show Menu"
    Menu, MainFileMenu, Add, &Check for Updates, MainButtonCheckForUpdates
    Menu, MainFileMenu, Add, % always_show_menu, FileMenuAlwaysShow
    Menu, MainFileMenu, Add
    Menu, MainFileMenu, Add, E&xit, MainGuiClose

    if (OLD_PACKAGE.__CanUpdateUserProperty("Gui", "ShowMenuBar")) {
        Menu, MainFileMenu, Enable, % always_show_menu
    } else {
        Menu, MainFileMenu, Disable, % always_show_menu
    }

    if (OLD_PACKAGE.gui("ShowMenuBar", 0)) {
        Menu, MainFileMenu, Check, % always_show_menu
    } else {
        Menu, MainFileMenu, Uncheck, % always_show_menu
    }

    ; developer menu definition
    Menu, MainDevMenu, Add, &Update with Local Package, DevMenuLocalPackage
    Menu, MainDevMenu, Add
    Menu, MainDevMenu, Add, Backup Package &Now, DevMenuBackupNow
    Menu, MainDevMenu, Add, Open &Backups Directory, DevMenuBackups
    Menu, MainDevMenu, Add
    Menu, MainDevMenu, Add, Open &Package Directory, DevMenuPackage
    Menu, MainDevMenu, Add, Open &Temp Directory, DevMenuTemp
    Menu, MainDevMenu, Add, Open User &Config, DevMenuUserConfig

    Menu, MainDevMenu, Add
    Menu, MainDevMenu, Add, Dump &Log Files, DevMenuLogFiles

    if (OLD_PACKAGE.gui("SubmitFeedback", 0)) {
        Menu, MainDevMenu, Add, &Submit Feedback, DevMenuSubmitFeedback
    }

    ; help menu definition
    Menu, MainHelpMenu, Add, &Updater Help, HelpMenuHelp
    Menu, MainHelpMenu, Add
    Menu, MainHelpMenu, Add, &About, MainButtonAbout

    ; menu bar definition
    Menu, MainMenuBar, Add, &File, :MainFileMenu
    Menu, MainMenuBar, Add, &Developer, :MainDevMenu
    Menu, MainMenuBar, Add, &Help, :MainHelpMenu

    ; hotkey toggle definition; ctrl+shift+alt+d
    Hotkey, IfWinActive, ahk_class AutoHotkeyGUI
    Hotkey, !^+d, Toggle_Main_Dialog_Menu, On
    Toggle_Main_Dialog_Menu(OLD_PACKAGE.gui("ShowMenuBar", 0))
    return

    ; file menu callbacks
    FileMenuAlwaysShow:
        local show_menu_bar := OLD_PACKAGE.gui("ShowMenuBar", 0)
        show_menu_bar := show_menu_bar ? 0 : 1

        if show_menu_bar {
            Menu, MainFileMenu, Check, % always_show_menu
        } else {
            Menu, MainFileMenu, Uncheck, % always_show_menu
        }

        OLD_PACKAGE.UpdateUserProperty("Gui", "ShowMenuBar", show_menu_bar)
        return

    ; developer menu callbacks
    DevMenuBackupNow:
        backup_path := BackupOldPackage("manual")
        SplitPath, % backup_path, backup_zip

        if FileExist(backup_path) {
            local backup_title := "Package Backup"
            local backup_message := Format("Backup complete, '{1}' can be found in the backups directory.", backup_zip)
            MsgBox, % (0x40 | 0x2000), % backup_title, % backup_message
        } else {
            local backup_title := "Package Backup"
            local backup_message := Format("There was an error backing up the package.")
            MsgBox, % (0x10 | 0x2000), % backup_title, % backup_message
        }
        return

    DevMenuBackups:
        local backup_directory := Format("{1}\{2}", APP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))
        return Open_Path("backups directory", backup_directory)

    DevMenuLocalPackage:
        local select_message := Format("Select a package archive or executable")
        local select_format := Format("Package file (*.exe; *.zip)")

        FileSelectFile, package_path, 3, % OLD_PACKAGE.base_directory, % select_message, % select_format
        local new_updater := package_path

        ; if the user selected a zip file, we have to extract it first
        if RegExMatch(package_path, "^.*[.]zip$") {
            SplitPath, % package_path, package_file
            local package_asset := new Asset(package_file, package_path, "", "None")
            local temp_base := Format("{1}\{2}", TEMP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))

            package_extract := package_asset.GetAsset(temp_base, "manual")
            new_updater := Format("{1}\{2}", package_extract, OLD_PACKAGE.package("Updater", "package-updater.exe"))
        }

        if FileExist(new_updater) {
            NEW_PACKAGE := new Package(new_updater)

            local old_version := CleanVersionString(OLD_PACKAGE.package("Version", "0.0.0"))
            local local_version := CleanVersionString(NEW_PACKAGE.package("Version", "0.0.0"))

            ; update the ui now that we have a new package
            local header := Format("Local package appears to be valid!")
            local desc_1 := Format("The local package's version is {1} — you have {2}.", local_version, old_version)
            local desc_2 := Format("Would you like to attempt to update to this package now? (Unsupported)")

            SplitPath, % NEW_PACKAGE.main_config_path, new_package_main_config_name
            FileRead, new_package_main_config, % NEW_PACKAGE.main_config_path
            local changelog_1 := Format("Release notes are not available for local packages.")
            local changelog_2 := Format("Displaying main config '{1}':", new_package_main_config_name)
            local changelog_text := Format("{1}`n{2}`n`n{3}", changelog_1, changelog_2, new_package_main_config)

            ; basic sanity check of the new package
            local old_package_config := OLD_PACKAGE.main_ini.GetJSON()
            local new_package_config := NEW_PACKAGE.main_ini.GetJSON()

            ; the package looks invalid, but let the process continue
            if (old_package_config != "{}" and new_package_config == "{}") {
                header := Format("Local package appears to be invalid!")
            }

            GuiControl, Text, Header, % Format("{1}", header)
            GuiControl, Text, Description, % Format("{1}`n{2}", desc_1, desc_2)
            GuiControl, Text, Changelog, %` Format("{1}", changelog_text)

            GuiControl, Show, LocalUpdate
            GuiControl, Enable, LocalUpdate
            GuiControl, Hide, RerunUpdate
            GuiControl, Hide, Update
        } else {
            if (new_updater != "") {
                local error_title := "Error"
                local error_message := Format("Selected file does not appear to be a valid package: '{1}'.", package_path)
                MsgBox, % (0x10 | 0x2000), % error_title, % error_message
                return false
            }
        }
        return true

    DevMenuLogFiles:
        last_log_txt := DumpLogFiles("lastlog.txt")
        Open_Path("last log", last_log_txt)
        return

    DevMenuPackage:
        return Open_Path("package directory", OLD_PACKAGE.base_directory)

    DevMenuSubmitFeedback:
        local submit_feedback := OLD_PACKAGE.gui("SubmitFeedback", 0)
        if (submit_feedback) {
            Run, %submit_feedback%
        }
        return

    DevMenuTemp:
        local temp_base := Format("{1}\{2}", TEMP_DIRECTORY, OLD_PACKAGE.package("Name", "unknown"))
        return Open_Path("temp directory", temp_base)

    DevMenuUserConfig:
        return Open_Path("user config", OLD_PACKAGE.user_config_path)

    ; help menu callbacks
    HelpMenuHelp:
        Help_Dialog(0)
        return
}

Open_Path(name := "", path := "") {
    ; check to see if it's a directory first
    if InStr(FileExist(path), "D") {
        Run, explore %path%
        return true
    } else {
        ; open it in notepad as a text file
        ; we could use 'open', but this only adds complexity for the user
        if FileExist(path) {
            Run, Notepad.exe "%path%"
            return true
        } else {
            error_title := "Error"
            error_message := Format("Unable to find {1} '{2}'.", name, path)
            MsgBox, % (0x10 | 0x2000), % error_title, % error_message
            return false
        }
    }
}

Run_Update(rerun := 0) {
    global

    if rerun {
        local ask_title := "Are you sure?"
        local base_text := "Do you want to reapply the latest update?"
        local custom_text := NEW_PACKAGE.gui("RerunText", OLD_PACKAGE.gui("RerunText", false))
    } else {
        local ask_title := "Are you sure?"
        local base_text := "Do you want to update to the latest version?"
        local custom_text := NEW_PACKAGE.gui("UpdateText", OLD_PACKAGE.gui("UpdateText", false))
    }

    if (custom_text) {
        ask_text := Format("{1}`n`n{2}", custom_text, base_text)
    } else {
        ask_text := Format("{1}", base_text)
    }

    MsgBox, % (0x4 | 0x30 | 0x100 | 0x2000), % ask_title, % ask_text
    IfMsgBox, No
        return false

    ; disable any hotkeys before we start the update process
    ; do not show any progress bar here because we're about to exit
    Hotkey, !^+d, Toggle_Main_Dialog_Menu, Off
    BackupOldPackage("auto")
    KillPackageProcess()

    local run_result := RunNewPackage()
    if ! run_result {
        local error_title := "Package Update"
        local error_message := Format("There was an error executing the new package.")
        MsgBox, % (0x10 | 0x2000), % error_title, % error_message
        ExitClean("There was an error executing the new package")
    } else {
        ExitClean()
    }
}

Show_Progress(title := "", percentage := 0, force_message := "") {
    global

    static progress_message
    static progress_message_time := 0
    static progress_percentage
    static message_cycle := 3

    ; how much padding we add when positioning the window
    local padding_x := 2
    local padding_y := 2

    local window_title := title ? title : NEW_PACKAGE.gui("Name", SELF ? SELF : "package-updater")
    local default_messages := "Please wait;This will only take a few seconds"
    local messages_string := NEW_PACKAGE.gui("ProgressMessages", OLD_PACKAGE.gui("ProgressMessages", default_messages))
    messages_string := messages_string ? messages_string : default_messages

    ; update the message every few seconds
    FormatTime, now, , yyyyMMddHHmmss
    if (now - progress_message_time > message_cycle) {
        progress_message_time := now
        local last_progress_message := progress_message
        local messages_array := StrSplit(messages_string, ";")

        ; make sure the message always changes
        while (progress_message == last_progress_message) {
            Random message_index, 1, messages_array.Length()
            progress_message := messages_array[message_index]
        }
    }

    local window_message := Format("{1}...", force_message ? force_message : progress_message)
    window_message := force_message ? force_message : window_message

    ; adjust percentage if we sent a fraction < 1
    if (percentage > 0 and percentage <= 1) {
        percentage := percentage * 100
    }

    ; yes, we artificially add delays to make the the progress bar look better
    if (percentage < 0) {
        Progress, % progress_percentage, % window_message, % window_title

        local delay_off := Abs(percentage) * 1000
        Sleep delay_off

        Progress Off
    } else if (percentage) {
        ; save the percentage
        progress_percentage := percentage

        Progress, % percentage, % window_message, % window_title
        Sleep 250
    } else {
        ; the progress window is always on top
        ; when we show it, we don't want it to interfere with the rest of the UI
        ; detect it's size and move it to a sane location
        DetectHiddenWindows, On
        Progress, B1 Hide, % window_message, % window_title

        SysGet, monitor_primary, MonitorPrimary
        SysGet, MonitorBounds, MonitorWorkArea, % monitor_primary
        WinGetPos, progress_x, progress_y, progress_w, progress_h, , % window_message

        ; after we've moved it, show the progress bar
        progress_x_final := MonitorBoundsRight - padding_x - progress_w
        progress_y_final := MonitorBoundsBottom - padding_y - progress_h
        Progress, % Format("B1 X{1} Y{2}", progress_x_final, progress_y_final), % window_message, % window_title
        Progress Show
    }

}

Toggle_Main_Dialog_Menu(force := -1) {
    global
    static main_menubar_visible := 0

    if (force != -1) {
        main_menubar_visible := force ? 0 : 1
    }

    if main_menubar_visible {
        Gui, Main:Menu
        Gui, Main:Show, AutoSize
        main_menubar_visible := 0
    } else {
        Gui, Main:Menu, MainMenuBar
        Gui, Main:Show, AutoSize
        main_menubar_visible := 1
    }
}

Update_Available_Dialog(latest_version) {
    global

    local update_title := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    local base_text := Format("A new version is available ({1}), update now?", latest_version)
    local custom_text := NEW_PACKAGE.gui("UpdateAvailable", OLD_PACKAGE.gui("UpdateAvailable", false))

    if (custom_text) {
        ; support showing the latest version from the UpdateAvailable message
        if InStr(custom_text, "{1}") {
            update_text := Format(custom_text, latest_version)
        } else {
            update_text := custom_text
        }
    } else {
        update_text := base_text
    }

    MsgBox, % (0x4 | 0x30 | 0x100 | 0x2000), % update_title, % update_text
    IfMsgBox, Yes
        Main_Dialog()
    IfMsgBox, No
        ExitClean()
}
