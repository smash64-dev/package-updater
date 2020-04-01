; test.ahk

#SingleInstance force
#Include %A_LineFile%\..\include.ahk

global SELF := "package-updater-tests"
global VERSION := "1.0.0"
global log := new Logger("tests.ahk")

global app_directory := Format("{1}\{2}", A_AppData, SELF)
global temp_directory := Format("{1}\{2}", A_Temp, SELF)

TestGithub() {
    global temp_directory

    gh_owner := "smash64-dev"
    gh_repo := "project64k-legacy"

    github_stable := new Github(gh_owner, gh_repo, 0)
    github_beta := new Github(gh_owner, gh_repo, 1)

    if (github_stable == github_beta) {
        log.err("Stable and beta release URLs should not match")
        return false
    }

    github_beta.GetReleases(temp_directory)
    package_url := github_beta.GetFileURL(Format("{1}.zip", gh_repo))

    if ! package_url {
        log.err("Unable to find latest package URL")
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

    ; TODO: Backup, GetComplexKeys, GetComplexPaths
    return true
}

; entry point
log.info("===================================")
log.info("= {1} (v{2})", SELF, VERSION)
log.info("===================================")

; run tests
package_test := TestPackage()
github_test := TestGithub()

; TODO: Asset, ini_config, transfer tests
