; transfer.ahk

#Include %A_LineFile%\..\ini_config.ahk
#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\package.ahk

class Transfer {
    static log := {}

    src_dir := ""
    dest_dir := ""

    __New(src_dir, dest_dir) {
        tlog := new Logger("transfer.ahk")
        this.log := tlog

        if InStr(FileExist(src_dir), "D") {
            this.src_dir := src_dir
        } else {
            this.log.err("Unable to find source directory '{1}'", src_dir)
            return false
        }

        ; we don't need this directory to exist, if it
        ; doesn't this will just act as a copy/paste
        this.dest_dir := dest_dir
        if ! InStr(FileExist(this.dest_dir), "D") {
            this.log.warn("Unable to find destination directory '{1}', creating", dest_dir)
            FileCreateDir % dest_dir
        }
    }

    ; allows pull from different section of the config easier
    __Call(method, ByRef arg, args*) {
        if (method == "dest")
            return this.__GetDestPath(arg, args*)
        else if (method == "src")
            return this.__GetSrcPath(arg, args*)
    }

    ; move unmanaged files or directories from one directory to another
    BasicFiles(ignore_list) {
        ; create every directory we might need
        ; if we want to delete a directory we will do it later
        from_pattern := Format("{1}\*.*", this.src_dir)

        loop files, % from_pattern, DR
        {
            relative_stripped := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")
            this.__TransferDir(relative_stripped)
        }

        ; transfer files over ONLY if they are not being watched
        loop files, % from_pattern, FR
        {
            relative_stripped := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")

            if ! ignore_list.HasKey(relative_stripped)
                this.__TransferFile(relative_stripped)
        }
    }

    ; TODO: backup file
    BackupFile() {

    }

    ; handle managed file or directory based on specification
    ComplexFile(complex_data, action) {
        this.log.debug("Performing complex action '{1}' on '{2}'", action, complex_data["Name"])

        switch action
        {
            ; https://puppet.com/docs/puppet/latest/types/file.html#file-attribute-ensure
            case "Absent":      return this.__DoAbsent(complex_data)
            case "Directory":   return this.__DoLatest(complex_data, "D")
            case "Latest":      return this.__DoLatest(complex_data)
            case "Link":        return this.__DoLatest(complex_data, "L")
            case "Present":     return this.__DoPresent(complex_data)

            default:
                this.log.error("Unknown action '{1}'", action)
                return false
        }
    }

    ; ensure a path does not exist in the destination
    __DoAbsent(complex_data) {
        if FileExist(this.dest(complex_data["Path"])) {
            return this.__TransferDelete(complex_data["Path"])
        } else {
            this.log.verb("Complex file '{1}' already removed from destination", complex_data["Path"])
            return true
        }
    }

    ; ensure a path matches specific content in the destination
    __DoLatest(complex_data, path_type := 0) {
        switch path_type {
            case "D":   return this.__TransferDir(complex_data["Path"])
            case "L":   return this.__TransferLink(complex_data["Path"], complex_data["Target"])
            default:    return this.__TransferFile(complex_data["Path"])
        }
    }

    __DoNotify(complex_data) {
        switch complex_data["Notify"] {
            case "Ask":     return true
            case "None":    return true
            case "Tell":    return true

            default:
                this.log.error("Unknown notify directive '{1}'", complex_data["Notify"])
                return false
        }
    }

    ; ensure a path exists in the destination
    __DoPresent(complex_data, path_type := 0) {
        if ! FileExist(this.dest(complex_data["Path"])) {
            this.__DoLatest(complex_data, path_type)
        } else {
            this.log.verb("Complex path '{1}' already exists in destination", complex_data["Path"])
        }

        return true
    }

    ; return the full path of the destination
    __GetDestPath(relative_path) {
        return Format("{1}\{2}", this.dest_dir, relative_path)
    }

    ; return the full path of the source
    __GetSrcPath(relative_path) {
        return Format("{1}\{2}", this.src_dir, relative_path)
    }

    ; determines if the destination file already matches the latest content via checksum
    __HasLatestChecksum(path_name, valid_checksum, algo := "SHA1") {
        if FileExist(this.dest(path_name)) {
            this.log.verb("File '{1}' does not exist in destination", path_name)
            return false
        }

        switch algo {
            case "MD5": current_checksum := LC_FileMD5(this.dest(path_name))
            case "SHA1": current_checksum := LC_FileSHA(this.dest(path_name))
            case "SHA256": current_checksum := LC_FileSHA256(this.dest(path_name))

            default: {
                this.log.err("Unknown checksum algorithm '{1}'", algo)
                return false
            }
        }

        if (current_checksum == valid_checksum) {
            this.log.verb("Checksum for '{1}' matches", path_name)
            return true
        } else {
            this.log.verb("Checksum for '{1}' does not match", path_name)
            this.log.verb("Checksum values '{1}' vs '{2}'", current_checksum, valid_checksum)
            return false
        }
    }

    ; determines if the destination file already has the latest content
    ; when absent is true, it ensures the data is missing from the destination
    ; this only works for ini style config files
    __HasLatestContent(path_name, valid_content, absent := 0) {

    }

    ; delete a file or directory (recursive) on the destination
    __TransferDelete(path_name) {
        if InStr(FileExist(this.dest(path_name)), "D") {
            FileRemoveDir % this.dest(path_name), 1
            result := A_LastError

            this.log.verb("Deleted directory '{1}' (error: {2})'", path_name, A_LastError)
            return result ? false : true
        } else if FileExist(this.dest(path_name)) {
            FileDelete % this.dest(path_name)
            result := A_LastError

            this.log.verb("Deleted file '{1}' (error: {2})'", path_name, A_LastError)
            return result ? false : true
        } else {
            return true
        }
    }

    ; creates a directory from in destination directory
    __TransferDir(path_name) {
        if ! InStr(FileExist(this.dest(path_name)), "D") {
            FileCreateDir % this.dest(path_name)
            result := A_LastError

            this.log.verb("Transferred '{1}' (error: {2})'", path_name, result)
            return result ? false : true
        }
        return true
    }

    ; moves a file from source to destination directory
    __TransferFile(path_name) {
        FileCopy, % this.src(path_name), % this.dest(path_name), 1
        result := A_LastError

        this.log.verb("Transferred '{1}' (error: {2})'", path_name, result)
        return result ? false : true
    }

    ; ensures ini section/kvp exist or don't exist in the destination
    __TransferIni(path_name, ini_content, absent := 0) {
    }

    ; creates a shortcut in destination directory to another location
    __TransferLink(link_name, target_path) {
        if RegExMatch(link_name, "$.*[.]lnk$")
            link_path := this.dest(link_name)
        else
            link_path := Format("{1}.lnk", this.dest(link_name))

        FileCreateShortcut, % target_path, % link_path
        result := A_LastError

        this.log.verb("Transferred '{1}' (error: {2})'", link_name, result)
        return result ? false : true
    }
}
