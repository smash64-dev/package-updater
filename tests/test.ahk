; test.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global SELF := "package-updater-tests"
global VERSION := "1.0.0"
global log := new Logger("tests.ahk")

global app_directory := Format("{1}\{2}", A_AppData, SELF)
global temp_directory := Format("{1}\{2}", A_Temp, SELF)

assert(description, test, fail_extra := "") {
    if (test == "TODO") {
        log.crit("TODO: {1}", description)
        return true
    } else if (test) {
        log.crit("FAIL: {1}", description)

        if fail_extra {
            log.info("{1}", fail_extra)
        }
        return false
    } else {
        log.crit("PASS: {1}", description)
        return true
    }
}

TestGithub() {
    global temp_directory
    log.crit("=== Performing Github Tests ===")

    gh_owner := "smash64-dev"
    gh_repo := "package-updater"

    github_stable := new Github(gh_owner, gh_repo, 0)
    github_beta := new Github(gh_owner, gh_repo, 1)

    assert("Checking that stable and beta release URLS do not match", github_stable == github_beta)

    github_beta.GetReleases(temp_directory)
    package_url := github_beta.GetFileURL(Format("{1}.zip", gh_repo))
    checksum_url := github_beta.GetFileURL("sha1sum.txt")

    assert("Latest package URL exists", ! package_url)
    assert("Latest checksum URL exists", ! checksum_url)

	asset := new Asset(Format("{1}.zip", gh_repo), package_url, checksum_url, "SHA1")

    ; test the internal methods individually
    asset_path := asset.__DownloadFile(temp_directory, asset.asset_url)
    checksum_path := asset.__DownloadFile(temp_directory, asset.checksum_url)
    assert("Downloaded asset data", (! FileExist(asset_path) or ! FileExist(checksum_path)))

    valid_asset := asset.__ValidateAsset(asset_path, checksum_path, "SHA1")
    assert("Validating asset", ! valid_asset)

    ; test the primary all-in-one method
    FileRemoveDir, % temp_directory, 1
	asset_location := asset.GetAsset(temp_directory)
    assert("Get and validate asset data", (! asset_location or ! FileExist(asset_location)))

    return true
}

TestIniConfig() {
    global temp_directory
    log.crit("=== Performing IniConfig Tests ===")

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
    fail_extra := Format("test:'{1}' vs good:'{2}'", atomic.GetJSON(), atomic_final.GetJSON())
    assert("Atomic test config data", ((atomic.GetJSON() != atomic_final.GetJSON()) or (atomic.GetJSON() != atomic_dup.GetJSON())), fail_extra)

    format := new IniConfig(Format("{1}\format.ini", directory))
    format_original := Format("{1}.bak", format.config_file)
    format_final := new IniConfig(Format("{1}\final\format.ini", directory))

    FileCopy, % format.config_file, % format_original, 1
    format.FormatConfig()

    fail_extra := Format("test:'{1}' vs good:'{2}'", LC_FileSHA(format.config_file), LC_FileSHA(format_final.config_file))
    assert("Format test config checksums", LC_FileSHA(format.config_file) != LC_FileSHA(format_final.config_file), fail_extra)

    initial := new IniConfig(Format("{1}\initial.ini", directory))
    upsert_config := new IniConfig(Format("{1}\upsert.ini", directory))
    delete_config := new IniConfig(Format("{1}\delete.ini", directory))
    insert_final := new IniConfig(Format("{1}\final\insert.ini", directory))
    update_final := new IniConfig(Format("{1}\final\update.ini", directory))
    delete_final := new IniConfig(Format("{1}\final\delete.ini", directory))

    initial.InsertConfig(upsert_config)
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), insert_final.GetJSON())
    assert("Insert test config data", initial.GetJSON() != insert_final.GetJSON(), fail_extra)

    initial_copy := new IniConfig(Format("{1}\initial.ini", directory))
    initial.RevertConfig()
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), initial_copy.GetJSON())
    assert("Revert test config data", initial.GetJSON() != initial_copy.GetJSON(), fail_extra)

    initial.UpdateConfig(upsert_config)
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), update_final.GetJSON())
    assert("Update test config data", initial.GetJSON() != update_final.GetJSON(), fail_extra)

    initial.RevertConfig()
    initial.DeleteConfig(delete_config)
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), delete_final.GetJSON())
    assert("Delete test config data", initial.GetJSON() != delete_final.GetJSON(), fail_extra)

    ; remove and restore unnecesasry test data
    FileDelete, % atomic.config_file
    FileCopy, % format_original, % format.config_file, 1
    FileDelete, % format_original

    return true
}

TestPackage() {
    global temp_directory
    log.crit("=== Performing Package Tests ===")

    package := new Package(A_LineFile, Format("{1}\..\..\conf\tests.cfg", A_LineFile))

    assert("Package name", package.package("Name") != "package-updater-tests")
    assert("Invalid key default value", package.updater("Invalid", "default") != "default")
    assert("Path to 'README.md'", package.path("README.md") == "")
    assert("Path to invalid directory", package.path("invalid\dir\path") != 0)

    complex_paths := package.GetComplexPaths()
    assert("Build complex paths", (! complex_paths.HasKey("ensure directory") or ! complex_paths.HasKey("ensure present file.txt")))

    complex_keys := package.GetComplexKeys()
    assert("Build complex keys", (! complex_keys.HasKey("Ensure_Directory") or ! complex_keys.HasKey("Ensure_Present_File")))

    assert("Backup()", "TODO")

    return true
}

TestTransfer() {
    global temp_directory
    log.crit("=== Performing Transfer Tests ===")

    ; this should already be verified
    package := new Package(A_LineFile, Format("{1}\..\..\conf\tests.cfg", A_LineFile))

    ; initialize environment, ensure directories have spaces
    ; -------------------------------------------------------------------------
    src := Format("{1}\{2}", package.base_directory, "tests\transfer source")
    dest := Format("{1}\{2}", package.base_directory, "tests\transfer destination")

    ; don't create destination, have Transfer make it
    FileRemoveDir, % dest, 1

    transfer := new Transfer(src, dest)
    complex_paths := package.GetComplexPaths()

    ; create basic files in both source and destination
    ; -------------------------------------------------------------------------
    FileAppend, % "overwrite me", % transfer.dest("modified basic.txt")

    ; perform the basic transfer
    transfer.BasicFiles(complex_paths)

    ; test basic file and directory transfer
    assert("Transfer 'basic file.txt'", ! FileExist(transfer.dest("basic file.txt")))
    assert("Transfer 'basic directory'", ! InStr(FileExist(transfer.dest("basic directory")), "D"))

    ; test basic file overwriting
    FileRead, modified_basic, % transfer.dest("modified basic.txt")
    assert("Overwrite 'modified basic.txt'", modified_basic != "overwritten")

    ; create complex files in both source and destination
    ; -------------------------------------------------------------------------
    FileAppend, % "ensure absent file", % transfer.dest("ensure absent file.txt")
    FileCreateDir, % transfer.dest("ensure absent directory")

    FileAppend, % "ensure latest file modified", % transfer.dest("ensure latest file modified.txt")
    FileAppend, % "ensure present file modified", % transfer.dest("ensure present file modified.txt")

    FileCreateDir, % transfer.dest("ensure duplicate directory")
    FileCreateDir, % transfer.dest("ensure rename directory")
    FileAppend, % "ensure duplicate directory file", % transfer.dest("ensure duplicate directory\file.txt")
    FileAppend, % "ensure rename directory file", % transfer.dest("ensure rename directory\file.txt")

    ; perform the complex transfer
    for complex, action in package.GetComplexKeys() {
	    complex_data := package.config_data[complex]
		result := transfer.ComplexFile(complex_data, action)
	}

    ; test ensure absent file and directory
    assert("Remove 'ensure absent file.txt'", FileExist(transfer.dest("ensure absent file.txt")))
    assert("Remove 'ensure absent directory'", InStr(FileExist(transfer.dest("ensure absent directory")), "D"))

    ; test ensure directory things
    assert("Create 'ensure directory'", ! InStr(FileExist(transfer.dest("ensure directory")), "D"))
    assert("Duplicate 'ensure duplicate directory'", (LC_FileSHA(transfer.dest("ensure duplicate directory\file.txt")) != LC_FileSHA(transfer.dest("ensure duplicate directory 2\file.txt"))))

    ; test ensure ini content
    initial = new IniConfig(transfer.dest("ini config\initial.ini"))
    final = new IniConfig(transfer.dest("ini config\final.ini"))
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), final.GetJSON())
    assert("Ensure changing ini config data", initial.GetJSON() != final.GetJSON(), fail_extra)

    ; test ensure ini match
    initial = new IniConfig(transfer.src("ini config\match.ini"))
    final = new IniConfig(transfer.dest("ini config\match.ini"))
    fail_extra := Format("test:'{1}' vs good:'{2}'", initial.GetJSON(), final.GetJSON())
    assert("Ensure unchanging ini config data", initial.GetJSON() != final.GetJSON(), fail_extra)

    ; test ensure latest file
    assert("Create 'ensure latest file.txt'", (LC_FileSHA(transfer.src("ensure latest file.txt")) != LC_FileSHA(transfer.dest("ensure latest file.txt"))))
    assert("Update 'ensure latest file.txt'", (LC_FileSHA(transfer.src("ensure latest file modified.txt")) != LC_FileSHA(transfer.dest("ensure latest file modified.txt"))))

    ; test ensure link
    FileGetShortcut % transfer.dest("windows directory.lnk"), link_target
    assert("Create 'windows directory' shortcut", link_target != "C:\Windows")

    ; test ensure present file and modification
    assert("Create 'ensure present file.txt'", (LC_FileSHA(transfer.src("ensure present file.txt")) != LC_FileSHA(transfer.dest("ensure present file.txt"))))
    assert("Test modify 'ensure present file.txt'", (LC_FileSHA(transfer.src("ensure present file modified.txt")) == LC_FileSHA(transfer.dest("ensure present file modified.txt"))))

    ; test ensure renaming directories and files
    assert("Rename 'ensure rename directory 2'", ! InStr(FileExist(transfer.dest("ensure rename directory 2")), "D"))
    assert("Rename 'ensure rename file'", ! FileExist(transfer.dest("ensure duplicate directory 2\renamed.txt")))
    assert("Rename 'ensure rename file' (content)", (LC_FileSHA(transfer.dest("ensure duplicate directory\file.txt")) == LC_FileSHA(transfer.dest("ensure duplicate directory 2\renamed.txt"))))

    ; remove unnecesasry test data
    ; -------------------------------------------------------------------------
    for index, dir in [dest] {
        FileRemoveDir, % dir, 1
    }

    return true
}

; entry point
log.crit("===================================")
log.crit("= {1} (v{2})", SELF, VERSION)
log.crit("===================================")

; run tests
package_test := TestPackage()
github_test := TestGithub()
ini_config_test := TestIniConfig()
transfer_test := TestTransfer()

exit
