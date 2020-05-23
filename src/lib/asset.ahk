; asset.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk
#Include %A_LineFile%\..\..\ext\zip.ahk

class Asset {
    static alog := {}

    asset_name := ""
    asset_url := ""
    checksum_type := ""
    checksum_url := ""

    __New(asset_name, asset_url, checksum_url, checksum_type := "SHA1") {
        alog := new Logger("asset.ahk")
        this.log := alog

        this.asset_name := asset_name
        this.asset_url := asset_url
        this.checksum_url := checksum_url
        this.checksum_type := checksum_type
    }

    ; download, validate, and prepare an for usage
    GetAsset(directory, tag := "latest") {
        if ! InStr(FileExist(directory), "D") {
            FileCreateDir % directory
            this.log.verb("Created temp directory '{1}' (error: {2})", directory, A_LastError)

            ; HACK: FileAppend triggers an error code of ERROR_ALREADY_EXISTS but works anyway
            ; trigger a quick noop-style command to reset A_LastError
            FileGetAttrib, noop, % A_LineFile
        }

        ; download the asset and checksum, then validate it
        ; HACK: allows asset_url to be a path instead of a url
        if (! RegExMatch(this.asset_url, "^http.*$") and FileExist(this.asset_url)) {
            this.log.warn("Asset_url '{1}' is actually a path", this.asset_url)
            asset_path := this.asset_url
        } else {
            asset_path := this.__DownloadFile(directory, this.asset_url)
        }

        if this.checksum_url
            checksum_path := this.__DownloadFile(directory, this.checksum_url)

        if this.__ValidateAsset(asset_path, checksum_path, this.checksum_type) {
            if (InStr(this.asset_name, ".zip")) {
                SplitPath, asset_path,,, asset_ext, asset_name
                return this.__ExtractZipAsset(asset_path, Format("{1}\{2}-{3}", directory, asset_name, tag))
            } else {
                return asset_path
            }
        } else {
            return false
        }
    }

    ; download a file from remote
    __DownloadFile(directory, url) {
        SplitPath, url, asset_name
        download_path := Format("{1}\{2}", directory, asset_name)
        UrlDownloadToFile % url, % download_path
        result := A_LastError

        if ! A_LastError {
            this.log.verb("Downloaded '{1}' to '{2}'", url, download_path)
            return download_path
        } else {
            this.log.err("There was an error downloading '{1}' to '{2}' (error: {3})", url, download_path, result)
            return false
        }
    }

    ; extracts a zip asset to a directory
    __ExtractZipAsset(asset_path, extract_dir) {
        this.log.verb("Extracting asset '{1}' to '{2}'", asset_path, extract_dir)

        FileRemoveDir % extract_dir, 1
        FileCreateDir % extract_dir

        if ! ErrorLevel {
            Unz(asset_path, extract_dir)
            return extract_dir
        } else {
            return false
        }
    }

    ; validates the asset was downloaded correctly by comparing against a checksum file
    __ValidateAsset(asset, checksum, algo := "SHA1") {
        if ! FileExist(asset) {
            this.log.err("Unable to find asset '{1}'", asset)
            return false
        }

        if (algo != "None" and ! FileExist(checksum)) {
            this.log.err("Unable to find checksum '{1}'", checksum)
            return false
        }

        switch algo {
            case "None": {
                this.log.verb("No checksum requested for '{1}'", asset)
                return true
            }

            case "MD5": asset_checksum := LC_FileMD5(asset)
            case "SHA1": asset_checksum := LC_FileSHA(asset)
            case "SHA256": asset_checksum := LC_FileSHA256(asset)

            default: {
                this.log.err("Unknown checksum algorithm '{1}'", algo)
                return false
            }
        }

        ; expects standard file checksum output {hash} {filename}
        FileRead checksum_contents, % checksum
        valid_checksum := StrSplit(checksum_contents, " ")
        this.log.verb("Comparing checksums '{1}' vs '{2}'", asset_checksum, valid_checksum[1])

        if (asset_checksum == valid_checksum[1]) {
            this.log.verb("Checksum for '{1}' matches", asset)
            return true
        } else {
            this.log.err("Checksum for '{1}' does not match", asset)
            this.log.err("Checksum values '{1}' vs '{2}'", asset_checksum, valid_checksum[1])
            return false
        }
    }
}
