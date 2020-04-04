; github.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk

class GitHub {
    static ghlog := {}

    github_api := "https://api.github.com"
    github_owner := ""
    github_repo := ""
    json_payload := ""
    latest_build := {}
    latest_build_id := 1
    release_url := ""
    wants_beta := false

    __New(github_owner, github_repo, wants_beta) {
        ghlog := new Logger("github.ahk")
        this.log := ghlog

        if github_owner and github_repo {
            all_releases := Format("{1}/repos/{2}/{3}/releases", this.github_api, github_owner, github_repo)
            latest_release := Format("{1}/latest", all_releases)

            this.github_owner := github_owner
            this.github_repo := github_repo
            this.wants_beta := wants_beta
        } else {
            this.log.err("Unable to determine release_url: '{1}' '{2}' (beta: {3})", github_owner, github_repo, wants_beta)
            return false
        }

        ; if no beta, then just pull the latest release
        this.release_url := wants_beta ? all_releases : latest_release
        this.log.info("release_url: '{1}' (beta: {2})", this.release_url, this.wants_beta)
    }

    ; find an asset url from an asset name
    GetFileURL(file_name) {
        assets := this.latest_build.assets

        loop {
            current_name := assets[A_Index].name

            if InStr(current_name, file_name) {
                asset_url := assets[A_Index].browser_download_url
                this.log.verb("Asset '{1}' url found: '{2}'", file_name, asset_url)
                return asset_url
            } else {
                this.log.debug("Asset '{1}' does not match", current_name)
            }
        } until !assets[A_Index].id

        this.log.err("Unable to find '{1}' in assets", file_name)
        return false
    }

    GetReleases(directory) {
        if ! InStr(FileExist(directory), "D") {
            FileCreateDir % directory
            this.log.verb("Created temp directory '{1}' (error: {2})", directory, A_LastError)

            ; HACK: FileAppend triggers an error code of ERROR_ALREADY_EXISTS but works anyway
            ; trigger a quick noop-style command to reset A_LastError
            FileGetAttrib, noop, % A_LineFile
        }

        release_json := Format("{1}\{2}-{3}.json", directory, this.github_owner, this.github_repo)
        UrlDownloadToFile % this.release_url, % release_json
        result := A_LastError

        if ! A_LastError {
            this.log.verb("Downloaded '{1}' to '{2}'", this.release_url, directory)
            FileRead release_data, % release_json
            this.log.debug("release_json: '{1}'", release_data)

            return this.__LoadJSON(release_json)
        } else {
            this.log.err("There was an error downloading '{1}' to '{2}' (error: {3})", release_json, directory, result)
            return false
        }
    }

    ; returns the array id of the latest build from the JSON data
    __GetLatestBuildId() {
        build_list := {}
        build_tags := ""

        loop {
            tag_name := this.json_payload[A_Index].tag_name
            build_list[tag_name] := A_Index
            build_tags := build_tags . "`n" . tag_name
        } until !this.json_payload[A_Index].id

        Sort build_tags, CLR
        builds_array := StrSplit(build_tags, "`n")
        latest_id := builds_array[1]

        return build_list[latest_id]
    }

    ; load the API results into a JSON object
    __LoadJSON(json_file) {
        if FileExist(json_file) {
            FileRead, json_str, %json_file%

            if json_str {
                try {
                    if this.wants_beta {
                        this.json_payload := JSON.Load(json_str)
                        this.latest_build_id := this.__GetLatestBuildId()
                    } else {
                        this.json_payload := JSON.Load("[" . json_str . "]")
                        this.latest_build_id := 1
                    }
                } catch err {
                    this.log.err("Unable to read JSON data: (error: {1})", err)
                    return false
                }

                this.latest_build := this.json_payload[this.latest_build_id]
            } else {
                this.log.err("Could not read JSON file '{1}'", json_file)
                return false
            }
        } else {
            this.log.err("Unable to find JSON file '{1}'", json_file)
            return false
        }

        return true
    }
}
