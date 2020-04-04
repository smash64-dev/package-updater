; test.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global SELF := "package-updater-tests"
global VERSION := "1.0.0"
global log := new Logger("tests.ahk")

global app_directory := Format("{1}\{2}", A_AppData, SELF)
global temp_directory := Format("{1}\{2}", A_Temp, SELF)

TestIniConfig() {
    directory := Format("{1}\..\ini_config", A_LineFile)

    atomic := new IniConfig(Format("{1}\atomic.ini", directory))
    atomic_final := new IniConfig(Format("{1}\final\atomic.ini", directory))

    atomic.__InsertSection("new section")
    atomic.__InsertProperty("new section", "new key A", "new value A")
    atomic.__UpdateProperty("new section", "new key B", "new value B")
    atomic.__InsertProperty("new section 2", "new key A", "new value A")
    atomic.WriteConfig()

    atomic.__InsertProperty("new section", "new key B", "cannot overwrite")
    atomic.__DeleteProperty("new section", "new key A")
    atomic.__InsertProperty("new section", "new key A", "post delete A")
    atomic.WriteConfig()

    atomic.__DeleteProperty("new section 2", "new key A")
    atomic.WriteConfig()

    atomic_dup := new IniConfig(Format("{1}\atomic.ini", directory))
    if ((atomic.GetJSON() != atomic_final.GetJSON()) or (atomic.GetJSON() != atomic_dup.GetJSON())) {
        log.err("Atomic test configs do not match: test:'{1}' vs good:'{2}'", atomic.GetJSON(), atomic_final.GetJSON())
        return false
    }

    format := new IniConfig(Format("{1}\format.ini", directory))
    format_original := Format("{1}.bak", format.config_file)
    format_final := new IniConfig(Format("{1}\final\format.ini", directory))

    FileCopy, % format.config_file, % format_original, 1
    format.FormatConfig()

    if (LC_FileSHA(format.config_file) != LC_FileSHA(format_final.config_file)) {
        log.err("Format test config checksums do not match: test:'{1}' vs good:'{2}'", LC_FileSHA(format.config_file), LC_FileSHA(format_final.config_file))
        return false
    }

    initial := new IniConfig(Format("{1}\initial.ini", directory))
    upsert_config := new IniConfig(Format("{1}\upsert.ini", directory))
    delete_config := new IniConfig(Format("{1}\delete.ini", directory))
    insert_final := new IniConfig(Format("{1}\final\insert.ini", directory))
    update_final := new IniConfig(Format("{1}\final\update.ini", directory))
    delete_final := new IniConfig(Format("{1}\final\delete.ini", directory))

    initial.InsertConfig(upsert_config)
    if (initial.GetJSON() != insert_final.GetJSON()) {
        log.err("Insert test configs do not match: test:'{1}' vs good:'{2}'", initial.GetJSON(), insert_final.GetJSON())
        return false
    }

    initial_copy := new IniConfig(Format("{1}\initial.ini", directory))
    initial.RevertConfig()
    if (initial.GetJSON() != initial_copy.GetJSON()) {
        log.err("Revert test configs do not match: test:'{1}' vs good:'{2}'", initial.GetJSON(), initial_copy.GetJSON())
        return false
    }

    initial.UpdateConfig(upsert_config)
    if (initial.GetJSON() != update_final.GetJSON()) {
        log.err("Update test configs do not match: test:'{1}' vs good:'{2}'", initial.GetJSON(), update_final.GetJSON())
        return false
    }

    initial.RevertConfig()
    initial.DeleteConfig(delete_config)
    if (initial.GetJSON() != delete_final.GetJSON()) {
        log.err("Delete test configs do not match: test:'{1}' vs good:'{2}'", initial.GetJSON(), delete_final.GetJSON())
        return false
    }

    ; remove and restore unnecesasry test data
    FileDelete, % atomic.config_file
    FileCopy, % format_original, % format.config_file, 1
    FileDelete, % format_original

    return true
}

TestGithub() {
    global temp_directory

    gh_owner := "smash64-dev"
    gh_repo := "package-updater"

    github_stable := new Github(gh_owner, gh_repo, 0)
    github_beta := new Github(gh_owner, gh_repo, 1)

    if (github_stable == github_beta) {
        log.err("Stable and beta release URLs should not match")
        return false
    }

    github_beta.GetReleases(temp_directory)
    package_url := github_beta.GetFileURL(Format("{1}.zip", gh_repo))
    checksum_url := github_beta.GetFileURL("sha1sum.txt")

    if ! package_url {
        log.err("Unable to find latest package URL")
        return false
    }

    if ! checksum_url {
        log.err("Unable to find latest checksum URL")
        return false
    }

	asset := new Asset(Format("{1}.zip", gh_repo), package_url, checksum_url, "SHA1")

    ; test the internal methods individually
    asset_path := asset.__DownloadFile(temp_directory, asset.asset_url)
    checksum_path := asset.__DownloadFile(temp_directory, asset.checksum_url)
    if (! FileExist(asset_path) or ! FileExist(checksum_path)) {
        log.err("Unable to download asset data")
        return false
    }

    valid_asset := asset.__ValidateAsset(asset_path, checksum_path, "SHA1")
    if ! valid_asset {
        log.err("Unable to validate asset")
        return false
    }

    ; test the primary all-in-one method
    FileRemoveDir, % temp_directory, 1
	asset_location := asset.GetAsset(temp_directory)
    if (! asset_location or ! FileExist(asset_location)) {
        log.err("Unable to get and validate asset data")
        return false
    }

    return true
}

TestPackage() {
    package := new Package(A_LineFile, Format("{1}\..\..\conf\tests.cfg", A_LineFile))

    if package.package("Name") != "package-updater-tests" {
        log.err("Package name invalid")
        return false
    }

    if package.updater("Invalid", "default") != "default" {
        log.err("Bad key default invalid")
        return false
    }

    if package.path("README.md") == "" {
        log.err("Unable to find README.md")
        return false
    }

    if package.path("invalid\dir\path") != 0 {
        log.err("Found non-existant directory")
        return false
    }

    complex_paths := package.GetComplexPaths()
    if (! complex_paths.HasKey("ensure directory") or ! complex_paths.HasKey("ensure present file.txt")) {
        log.err("Complex paths is missing basic definitions")
        return false
    }

    complex_keys := package.GetComplexKeys()
    if (! complex_keys.HasKey("Ensure_Directory") or ! complex_keys.HasKey("Ensure_Present_File")) {
        log.err("Complex keys is missing basic definitions")
        return false
    }

    ; TODO: Backup
    return true
}

TestTransfer() {
    ; this should already be verified
    package := new Package(A_LineFile, Format("{1}\..\..\conf\tests.cfg", A_LineFile))

    ; initialize environment, ensure directories have spaces
    ; -------------------------------------------------------------------------
    src := Format("{1}\{2}", package.base_directory, "tests\transfer source")
    dest := Format("{1}\{2}", package.base_directory, "tests\transfer destination")

    ; don't create destination, have Transfer make it
    FileRemoveDir, % src, 1
    FileCreateDir, % src
    FileRemoveDir, % dest, 1

    transfer := new Transfer(src, dest)
    complex_paths := package.GetComplexPaths()

    ; create basic files in both source and destination
    ; -------------------------------------------------------------------------
    FileAppend, % "basic file", % transfer.src("basic file.txt")
    FileCreateDir, % transfer.src("basic directory")

    FileAppend, % "overwritten", % transfer.src("modified basic.txt")
    FileAppend, % "overwrite me", % transfer.dest("modified basic.txt")

    ; perform the basic transfer
    transfer.BasicFiles(complex_paths)

    ; test basic file transfer
    if ! FileExist(transfer.dest("basic file.txt")) {
        log.err("'basic file.txt' did not transfer properly")
        return false
    }

    ; test basic directory transfer
    if ! InStr(FileExist(transfer.dest("basic directory")), "D") {
        log.err("'basic directory' did not transfer properly")
        return false
    }

    ; test basic file overwriting
    FileRead, modified_basic, % transfer.dest("modified basic.txt")
    if (modified_basic != "overwritten") {
        log.err("'modified basic.txt' was not overwritten")
        return false
    }

    ; create complex files in both source and destination
    ; -------------------------------------------------------------------------
    FileAppend, % "ensure absent file", % transfer.dest("ensure absent file.txt")
    FileCreateDir, % transfer.dest("ensure absent directory")

    FileAppend, % "ensure latest file", % transfer.src("ensure latest file.txt")
    FileAppend, % "ensure latest file", % transfer.src("ensure latest file modified.txt")
    FileAppend, % "ensure latest file modified", % transfer.dest("ensure latest file modified.txt")

    FileAppend, % "ensure present file", % transfer.src("ensure present file.txt")
    FileAppend, % "ensure present file", % transfer.src("ensure present file modified.txt")
    FileAppend, % "ensure present file modified", % transfer.dest("ensure present file modified.txt")

    ; perform the complex transfer
    for complex, action in package.GetComplexKeys() {
	    complex_data := package.config_data[complex]
		result := transfer.ComplexFile(complex_data, action)
	}

    ; test ensure absent file
    if FileExist(transfer.dest("ensure absent file.txt")) {
        log.err("'ensure absent file.txt' was not properly removed")
        return false
    }

    ; test ensure absent directory
    if InStr(FileExist(transfer.dest("ensure absent directory")), "D") {
        log.err("'ensure absent directory' was not properly removed")
        return false
    }

    ; test ensure directory
    if ! InStr(FileExist(transfer.dest("ensure directory")), "D") {
        log.err("'ensure directory' was not properly created")
        return false
    }

    ; test ensure latest file
    if (LC_FileSHA(transfer.src("ensure latest file.txt")) != LC_FileSHA(transfer.dest("ensure latest file.txt"))) {
        log.err("'ensure latest file.txt' was not properly created")
        return false
    }

    ; test ensure latest file modified
    if (LC_FileSHA(transfer.src("ensure latest file modified.txt")) != LC_FileSHA(transfer.dest("ensure latest file modified.txt"))) {
        log.err("'ensure latest file.txt' was not properly updated")
        return false
    }

    ; test ensure link
    FileGetShortcut % transfer.dest("windows directory.lnk"), link_target
    if (link_target != "C:\Windows") {
        log.err("'windows directory' was not properly created")
        return false
    }

    ; test ensure present file
    if (LC_FileSHA(transfer.src("ensure present file.txt")) != LC_FileSHA(transfer.dest("ensure present file.txt"))) {
        log.err("'ensure present file.txt' was not properly created")
        return false
    }

    ; test ensure present file modified
    if (LC_FileSHA(transfer.src("ensure present file modified.txt")) == LC_FileSHA(transfer.dest("ensure present file modified.txt"))) {
        log.err("'ensure present file.txt' was improperly modified")
        return false
    }

    ; remove unnecesasry test data
    ; -------------------------------------------------------------------------
    for index, dir in [src, dest] {
        FileRemoveDir, % dir, 1
    }

    return true
}

; entry point
log.info("===================================")
log.info("= {1} (v{2})", SELF, VERSION)
log.info("===================================")

; run tests
;package_test := TestPackage()
;github_test := TestGithub()
ini_config_test := TestIniConfig()
;transfer_test := TestTransfer()

exit
