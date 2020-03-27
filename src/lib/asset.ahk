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
    GetAsset(directory) {
        ; download the asset and checksum, then validate it
        asset_path := this.__DownloadFile(directory, this.asset_url)
        checksum_path := this.__DownloadFile(directory, this.checksum_url)

        if this.__ValidateAsset(asset_path, checksum_path, this.checksum_type) {
            if InStr(this.asset_name, ".zip") 
                return this.__ExtractZipAsset(asset_path, Format("{1}\latest", directory))
            else
                return asset_path
        } else {
            return false
        }
    } 

    ; download a file from remote
    __DownloadFile(directory, url) {
        SplitPath, url, asset_name
        download_path := Format("{1}\{2}", directory, asset_name)
        UrlDownloadToFile % url, %download_path%

        if ! ErrorLevel {
            this.log.verb(Format("Downloaded '{1}' to '{2}'", url, download_path))
            return download_path
        } else {
            this.log.err(Format("There was an error downloading '{1}' to '{2}'", url, download_path))
            return false
        }
    }

    ; extracts a zip asset to a directory
    __ExtractZipAsset(asset_path, extract_dir) {
        this.log.info(Format("Extracting asset '{1}' to '{2}'", asset_path, extract_dir))

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
            this.log.err(Format("Unable to find asset '{1}'", asset))
            return false
        }

        if ! FileExist(checksum) {
            this.log.err(Format("Unable to find checksum '{1}'", checksum))
            return false
        }

        switch algo {
            case "MD5": asset_checksum := LC_FileMD5(asset)
            case "SHA1": asset_checksum := LC_FileSHA(asset)
            case "SHA256": asset_checksum := LC_FileSHA256(asset)

            default: {
                this.log.err(Format("Unknown checksum algorithm '{1}'", algo))
                return false
            }
        }

        ; expects standard file checksum output {hash} {filename}
        FileRead checksum_contents, % checksum
        valid_checksum := StrSplit(checksum_contents, " ")
        this.log.verb(Format("Comparing checksums '{1}' vs '{2}'", asset_checksum, valid_checksum[1]))

        if (asset_checksum == valid_checksum[1]) {
            this.log.verb("Checksums match!")
            return true
        } else {
            this.log.verb("Checksums mismatch!")
            return false
        }
    }
}