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

Main_Dialog() {
    global

    local title := Format("Package Updater — v{1}", VERSION ? VERSION : "0.0.0")
    local exe_path := OLD_PACKAGE.path(OLD_PACKAGE.package("Process"))
    local exe_icon := LoadPicture(A_IsCompiled ? exe_path : "AutoHotkey.exe", "w64 h64 Icon1")

    local header_text := ""
    local description_text := ""
    local more_info_text := ""
    local changelog_text := ""

    ; build gui skeleton
    Gui, Main:New, -MaximizeBox -MinimizeBox
    Gui, Main:+LabelMain_Gui +LastFound
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

    ; allow the package maintainer to control if beta is available
    if (OLD_PACKAGE.updater("Beta") == "-1")  {
        GuiControl, Text, Beta, % Format("Beta feature is currently unavailable")
        GuiControl, Disable, Beta
    } else {
        GuiControl, Text, Beta, % Format("Update to beta releases, when available")
        GuiControl, Enable, Beta
    }

    ; display gui and immediately check for updates
    Gui, Main:Show, Center h402 w579, % title
    Gosub, MainButtonCheckForUpdates
    return

    ; check for beta releases
    MainBeta:
        ; TODO: load warning from user preferences
        local warning_title := "Warning"
        local warning_text := "Beta releases are not supported and may be UNSTABLE. Do not use beta unless you have been told to.`n`nAre you sure you want to receive beta releases?"

        GuiControlGet, beta_checkbox,, Beta
        if beta_checkbox {
            MsgBox, % (0x4 | 0x30 | 0x100 | 0x2000), % warning_title, % warning_text

            ; TODO: save to user preferences
            IfMsgBox, Yes
            {
                GuiControl,, Beta, 1
            } else {
                GuiControl,, Beta, 0
            }
        }
        return

    ; display dialog about package-updater
    MainButtonAbout:
        About_Dialog(0)
        return

    ; check for updates again
    MainButtonCheckForUpdates:
        GuiControl, Text, Header, Checking for Updates
        GuiControl, Text, Description, Please wait, this will only take a few seconds...

        GuiControl, Text, CheckUpdates, Checking...
        GuiControl, Disable, CheckUpdates

        GetLatestPackage()
        local changelog_text := GetLatestChangelog()

        GuiControl, Text, Changelog, % changelog_text
        GuiControl, Text, CheckUpdates, Check for Updates
        GuiControl, Enable, CheckUpdates

        return

    ; reapply the update from this version
    MainButtonRerunUpdate:
        return

    ; update to the latest version
    MainButtonUpdate:
        return

    Main_GuiClose:
        Gui, Main:Destroy
        ExitApp
}
