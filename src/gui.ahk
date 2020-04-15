; gui.ahk

About_Dialog(about_only := 0) {
    global

    local title := "About Package Updater"
    local version_text := Format("{1} — v{2}", SELF ? SELF : "package-updater", VERSION ? VERSION : "0.0.0")
    local description_text := "Generic zip package update utility written in AutoHotkey"
    local author_text := Format("Copyright: {1}", AUTHOR ? AUTHOR : "Unknown")
    local source_text := SOURCE ? SOURCE : "https://www.github.com"

    MsgBox, % (0x40 | 0x2000), % title, % Format("{1}`n{2}`n`n{3}`n{4}", version_text, description_text, author_text, source_text)

    if about_only
        ExitApp
    else
        return
}

Beta_Checkbox() {
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
        GuiControl, Enable, Beta
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

Check_For_Updates() {
    global

    ; give some kind of status text while we wait
    GuiControl, Text, Header, Checking for Updates
    GuiControl, Text, Description, Please wait, this will only take a few seconds...
    GuiControl, Text, CheckUpdates, Checking...

    GuiControl, Disable, RerunUpdate
    GuiControl, Disable, Update
    GuiControl, Disable, CheckUpdates

    ; pull down the latest package info
    local header := ""
    local desc_1 := ""
    local desc_2 := ""
    local latest_version := GetLatestPackage()
    local changelog_text := GetLatestChangelog()
    GuiControl, Text, Changelog, % changelog_text

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
        GuiControl, Hide, RerunUpdate
        GuiControl, Hide, Update
        GuiControl, Text, CheckUpdates, Check for Updates
        GuiControl, Enable, CheckUpdates
        return false
    }

    if IsLatestDifferent(latest_version) {
        if package_name
            header := Format("{1} has a new version available!", package_name)
        else
            header := Format("A new version version is available!")

        desc_1 := Format("The latest release available is {1} — you have {2}.", new_version, old_version)
        desc_2 := Format("Would you like to download and install it now?")

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

        GuiControl, Show, RerunUpdate
        GuiControl, Enable, RerunUpdate
        GuiControl, Hide, Update
        GuiControl, Enable, Update
    }

    GuiControl, Text, Header, % Format("{1}", header)
    GuiControl, Text, Description, % Format("{1}`n{2}", desc_1, desc_2)
    GuiControl, Text, CheckUpdates, Check for Updates
    GuiControl, Enable, CheckUpdates
    return true
}

Main_Dialog() {
    global

    local title := Format("Package Updater — v{1}", VERSION ? VERSION : "0.0.0")
    local exe_path := OLD_PACKAGE.path(OLD_PACKAGE.package("Process"))
    local exe_icon := LoadPicture(A_IsCompiled ? exe_path : "AutoHotkey.exe", "w64 h64 Icon1")

    local header_text := ""
    local description_text := ""
    local changelog_text := ""

    local github_home := Format("{1}/{2}/{3}", "https://www.github.com", OLD_PACKAGE.updater("Owner"), OLD_PACKAGE.updater("Repo"))
    local more_info_text := OLD_PACKAGE.gui("MoreInfo", github_home)

    ; build gui skeleton
    Gui, Main:New, -MaximizeBox -MinimizeBox
    Gui, Main:+LabelMainGui +LastFound
    Gui, Main:Default

    Gui, Main:Add, Picture, x12 y09 w64 h64 vExeIcon

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

    GuiControl, Hide, RerunUpdate
    GuiControl, Hide, Update

    ; build and set the beta checkbox
    Beta_Checkbox()

    ; display gui and immediately check for updates
    Gui, Main:Show, Center h402 w579, % title
    Gosub, MainButtonCheckForUpdates
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
        Check_For_Updates()
        return

    ; reapply the update from this version
    MainButtonRerunUpdate:
        return

    ; update to the latest version
    MainButtonUpdate:
        return

    MainGuiClose:
        Gui, Main:Destroy
        ExitApp
}
