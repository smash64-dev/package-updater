; transfer.ahk

#Include %A_LineFile%\..\ini_config.ahk
#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\package.ahk
#Include %A_LineFile%\..\..\ext\libcrypt.ahk

class Transfer {
    static log := {}

    notify_callback := 0
    src_dir := ""
    dest_dir := ""

    __New(src_dir, dest_dir, notify_callback := 0) {
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

        if IsFunc(notify_callback) {
            this.log.info("Registering '{1}' as the notify callback", notify_callback.Name)
            this.notify_callback := notify_callback
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
        this.__CopyDirectoryTree(from_pattern)

        ; transfer files over ONLY if they are not being watched
        loop files, % from_pattern, FR
        {
            relative_stripped := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")

            if ! ignore_list.HasKey(relative_stripped) {
                ; only transfer the file if it's different
                if (! this.__HasLatestChecksum(relative_stripped, LC_FileSHA(this.src(relative_stripped)))) {
                    this.__TransferFile(relative_stripped)
                } else {
                    this.log.verb("File '{1}' already matches the content", relative_stripped)
                }
            }
        }
    }

    ; backup an individual file in place
    BackupFile(complex_data) {
        backup := complex_data["Backup"] ? complex_data["Backup"] : 0

        if (backup) {
            backup_path := Format("{1}.bak", complex_data["Path"])

            this.log.info("Performing a backup on '{1}' ({2}", complex_data["Path"], backup_path)
            this.__TransferRelative(complex_data["Path"], backup_path, 1, 1)
        }
    }

    ; handle managed file or directory based on specification
    ComplexFile(complex_data, action) {
        this.log.debug("Performing complex action '{1}' on '{2}'", action, complex_data["Name"])

        ; handle certain complex file types differently
        if complex_data.HasKey("Type") {
            complex_type := complex_data["Type"]

            ; use this section to extend specific file type handlers
            switch complex_type
            {
                case "Ini":     return this.__DoIniConfig(complex_data, action)

                default:
                    this.log.warning("Unknown complex type '{1}'", complex_type)
                    return false
            }
        }

        switch action
        {
            ; https://puppet.com/docs/puppet/latest/types/file.html#file-attribute-ensure
            case "Absent":      return this.__DoAbsent(complex_data)
            case "Directory":   return this.__DoLatest(complex_data, "D")
            case "Duplicate":   return this.__DoDuplicate(complex_data)
            case "Latest":      return this.__DoLatest(complex_data)
            case "Link":        return this.__DoLatest(complex_data, "L")
            case "Noop":        return true
            case "Present":     return this.__DoPresent(complex_data)
            case "Rename":      return this.__DoRename(complex_data)

            default:
                this.log.err("Unknown action '{1}'", action)
                return false
        }
    }

    ; process data and user input to determine if we should perform the action
    __AllowAction(complex_data) {
        ignorable := complex_data["Ignorable"] ? complex_data["Ignorable"] : 1
        notify := complex_data["Notify"] ? complex_data["Notify"] : "None"
        remember := complex_data["Remember"] ? complex_data["Remember"] : "None"

        ; some complex files cannot be ignored
        if ignorable {
            ; if it's ignorable, see if the user stored a preference
            switch remember
            {
                case "Allow":
                    this.log.info("User preference saved as '{1}' for '{2}'", remember, complex_data["Name"])
                    return true

                case "Deny":
                    this.log.info("User preference saved as '{1}' for '{2}'", remember, complex_data["Name"])
                    return false

                case "None":
                    this.log.verb("No user preference saved for '{1}', continuing to notify", complex_data["Name"])

                default:
                    this.log.warn("Unknown remember directive '{1}', continuing to notify", remember)
                    complex_data["Remember"] = "None"
            }
        } else {
            if (remember != "None") {
                this.log.warn("User tried to '{1}' action '{2}', but it is not ignorable", remember, complex_data["Name"])
            }
        }

        ; notify the user in some way
        switch notify
        {
            case "Ask":
                this.log.verb("Valid notify directive '{1}', requesting action for '{2}'", notify, complex_data["Name"])

            case "Tell":
                this.log.verb("Valid notify directive '{1}', requesting action for '{2}'", notify, complex_data["Name"])

            case "None":
                this.log.info("No notify required, allowing action '{1}'", complex_data["Name"])
                return true

            default:
                this.log.warn("Unknown notify directive '{1}', allowing action '{2}'", notify, complex_data["Name"])
                return true
        }

        ; execute the callback
        if IsFunc(this.notify_callback) {
            response := this.notify_callback.Call(complex_data)
            allowing := response ? "allowing" : "not allowing"

            this.log.info("Notified user with '{1}', {2} action '{3}'", notify, allowing, complex_data["Name"])
            return response
        } else {
            this.log.warn("No callback function registered, allowing action '{1}'", complex_data["Name"])
            return true
        }
    }

    ; builds a directory tree in the destination
    __CopyDirectoryTree(pattern) {
        loop files, % pattern, DR
        {
            relative_stripped := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")
            this.__TransferDir(relative_stripped)
        }
    }

    ; ensure a path does not exist in the destination
    __DoAbsent(complex_data) {
        if ! this.__VerifyStruct(complex_data, ["Path"])
            return false

        if FileExist(this.dest(complex_data["Path"])) {
            if this.__AllowAction(complex_data) {
                recurse := complex_data.HasKey("Recurse") ? complex_data["Recurse"] : 0
                this.BackupFile(complex_data)
                return this.__TransferDelete(complex_data["Path"], recurse)
            } else {
                return false
            }
        } else {
            this.log.verb("Complex file '{1}' already removed from destination", complex_data["Path"])
            return true
        }
    }

    ; ensure a path is duplicated in the package
    __DoDuplicate(complex_data) {
        if ! this.__VerifyStruct(complex_data, ["Path"])
            return false

        if FileExist(this.dest(complex_data["Path"])) {
            if this.__AllowAction(complex_data) {
                overwrite := complex_data.HasKey("Overwrite") ? complex_data["Overwrite"] : 0
                return this.__TransferRelative(complex_data["Path"], complex_data["Target"], 1, overwrite)
            } else {
                return false
            }
        } else {
            this.log.warn("Complex path '{1}' does not exist in destination", complex_data["Path"])
            return false
        }
    }

    ; ensure an ini config is partially modified appropriately
    __DoIniConfig(complex_data, action) {
        if ! this.__VerifyStruct(complex_data, ["Path", "Content", "Type"])
            return false

        ; work off the destination ini, this means the ini should be at least
        ; transferred as present, if there's a concern about it not being in destination
        ; if Local is set, then the content comes from the old package (likely user made)
        local_content := complex_data["Local"] ? complex_data["Local"] : 0
        path := this.dest(complex_data["Path"])

        if (local_content) {
            content := this.dest(complex_data["Content"])

            if (! FileExist(content)) {
                log.warn("Local content '{1}' does not exist in destination", content)
                return false
            }
        } else {
            content := this.src(complex_data["Content"])
        }

        format := complex_data.HasKey("Format") ? complex_data["Format"] : 1

        ; the full path is only needed for the IniConfig class
        ini_config := new IniConfig(path)
        ini_content := new IniConfig(content)

        switch action
        {
            case "Absent":      modify_count := ini_config.DeleteConfig(ini_content)
            case "Latest":      modify_count := ini_config.UpdateConfig(ini_content)
            case "Present":     modify_count := ini_config.InsertConfig(ini_content)

            default:
                this.log.err("Unknown ini action '{1}'", action)
                return false
        }

        ; use the partial path again within class
        if ! this.__HasLatestContent(complex_data["Path"], ini_config) {
            if this.__AllowAction(complex_data) {
                this.BackupFile(complex_data)
                return this.__TransferIniConfig(complex_data["Path"], ini_config, format)
            } else {
                return false
            }
        } else {
            this.log.verb("Ini Config '{1}' already matches the content (format: {2})", complex_data["Path"], format)

            if format
                ini_config.__FormatIni()
            return true
        }
    }

    ; ensure a path matches specific content in the destination
    __DoLatest(complex_data, path_type := 0) {
        switch path_type {
            case "D":
                if this.__VerifyStruct(complex_data, ["Path"]) {
                    if this.__AllowAction(complex_data) {
                        return this.__TransferDir(complex_data["Path"])
                    } else {
                        return false
                    }
                } else {
                    return false
                }

            case "L":
                if this.__VerifyStruct(complex_data, ["Path", "Target"]) {
                    if this.__AllowAction(complex_data) {
                        return this.__TransferLink(complex_data)
                    } else {
                        return false
                    }
                } else {
                    return false
                }

            default:
                if this.__VerifyStruct(complex_data, ["Path"]) {
                    if (complex_data.HasKey("Checksum")) {
                        if (! this.__HasLatestChecksum(complex_data["Path"], complex_data["Checksum"])) {
                            if this.__AllowAction(complex_data) {
                                this.BackupFile(complex_data)
                                return this.__TransferFile(complex_data["Path"])
                            } else {
                                return false
                            }
                        } else {
                            this.log.verb("File '{1}' already matches the content (format: {2})", complex_data["Path"])
                            return true
                        }
                    } else {
                        ; there are no restrictions, just transfer
                        if this.__AllowAction(complex_data) {
                            this.BackupFile(complex_data)
                            return this.__TransferFile(complex_data["Path"])
                        } else {
                            return false
                        }
                    }
                } else {
                    return false
                }
        }
    }

    ; ensure a path exists in the destination
    __DoPresent(complex_data, path_type := 0) {
        if ! this.__VerifyStruct(complex_data, ["Path"])
            return false

        if ! FileExist(this.dest(complex_data["Path"])) {
            ; __AllowAction not needed, it's handled by __DoLatest
            return this.__DoLatest(complex_data, path_type)
        } else {
            this.log.verb("Complex path '{1}' already exists in destination", complex_data["Path"])
        }

        return true
    }

    ; ensure a path is moved to a different path in the destination
    __DoRename(complex_data) {
        if ! this.__VerifyStruct(complex_data, ["Path", "Target"])
            return false

        if FileExist(this.dest(complex_data["Path"])) {
            if this.__AllowAction(complex_data) {
                overwrite := complex_data.HasKey("Overwrite") ? complex_data["Overwrite"] : 0
                return this.__TransferRelative(complex_data["Path"], complex_data["Target"], 0, overwrite)
            } else {
                return false
            }
        } else {
            this.log.warn("Complex path '{1}' does not exist in destination", complex_data["Path"])
            return false
        }
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
        if ! FileExist(this.dest(path_name)) {
            this.log.verb("File '{1}' does not exist in destination {2}", path_name, this.dest(path_name))
            return false
        }

        switch algo {
            case "MD5":     current_checksum := LC_FileMD5(this.dest(path_name))
            case "SHA1":    current_checksum := LC_FileSHA(this.dest(path_name))
            case "SHA256":  current_checksum := LC_FileSHA256(this.dest(path_name))

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
    __HasLatestContent(path_name, valid_content) {
        ; perform a dry run
        change_count := valid_content.__WriteIni(1)

        this.log.verb("Ini config '{1}' has '{2}' pending changes", path_name, change_count)
        return change_count == 0 ? true : false
    }

    ; delete a file or directory (recursive) on the destination
    __TransferDelete(path_name, recurse := 0) {
        if InStr(FileExist(this.dest(path_name)), "D") {
            FileRemoveDir % this.dest(path_name), recurse
            result := A_LastError

            this.log.verb("[TDe] Deleted directory '{1}' (error: {2})", path_name, A_LastError)
            return result ? false : true
        } else if FileExist(this.dest(path_name)) {
            FileDelete % this.dest(path_name)
            result := A_LastError

            this.log.verb("[TDe] Deleted file '{1}' (error: {2})", path_name, A_LastError)
            return result ? false : true
        } else {
            return true
        }
    }

    ; creates a directory from in destination directory
    __TransferDir(path_name) {
        if ! InStr(FileExist(this.dest(path_name)), "D") {
            FileCreateDir, % this.dest(path_name)
            result := A_LastError

            this.log.verb("[TDi] Transferred '{1}' (error: {2})", path_name, result)
            return result ? false : true
        }
        return true
    }

    ; moves a file from source to destination directory
    __TransferFile(path_name) {
        FileCopy, % this.src(path_name), % this.dest(path_name), 1
        result := A_LastError

        this.log.verb("[TF] Transferred '{1}' (error: {2})", path_name, result)
        return result ? false : true
    }

    ; ensures ini section/kvp exist or don't exist in the destination
    __TransferIniConfig(path_name, ini_content, format := 1) {
        ini_content.WriteConfig(format)
        result := A_LastError

        this.log.verb("[TI] Transferred '{1}' (error: {2})", path_name, result)
        return result ? false : true
    }

    ; creates a shortcut in destination directory to another location
    __TransferLink(complex_data) {
        link_name := complex_data["Path"] ? complex_data["Path"] : false
        target_path := complex_data["Target"] ? complex_data["Target"] : false
        working_dir := complex_data["WorkingDir"] ? complex_data["WorkingDir"] : ""
        args := complex_data["Arguments"] ? complex_data["Arguments"] : ""
        description := complex_data["Description"] ? complex_data["Description"] : ""
        icon_file := complex_data["Icon"] ? complex_data["Icon"] : ""
        icon_no := complex_data["IconNumber"] ? complex_data["IconNumber"] : ""
        run_state := complex_data["RunState"] ? complex_data["RunState"] : ""

        if RegExMatch(link_name, "$.*[.]lnk$")
            link_path := this.dest(link_name)
        else
            link_path := Format("{1}.lnk", this.dest(link_name))

        ; always delete the shortcut before creating it
        FileDelete % link_path
        FileCreateShortcut, % target_path, % link_path, % working_dir, % args, % description, % icon_file,, % icon_no, % run_state
        result := A_LastError

        this.log.verb("[TL] Transferred '{1}' (error: {2})'", link_name, result)
        return result ? false : true
    }

    ; moves or copies a file or directory within the destination package
    __TransferRelative(old_path, new_path, copy := 0, overwrite := 0) {
        overwrite_final := overwrite

        if InStr(FileExist(this.dest(old_path)), "D") {
            if copy {
                FileCopyDir, % this.dest(old_path), % this.dest(new_path), overwrite_final
            } else {
                overwrite_final := overwrite_final ? 2 : 0
                FileMoveDir, % this.dest(old_path), % this.dest(new_path), % overwrite_final
            }
            result := A_LastError

            this.log.verb("[TR] Transferred directory '{1}' to '{2}' (overwrite: {3}) (error: {4})", old_path, new_path, overwrite_final, A_LastError)
            return result ? false : true
        } else if FileExist(this.dest(old_path)) {
            if copy
                FileCopy, % this.dest(old_path), % this.dest(new_path), overwrite_final
            else
                FileMove, % this.dest(old_path), % this.dest(new_path), % overwrite_final
            result := A_LastError

            this.log.verb("[TR] Transferred directory '{1}' to '{2}' (overwrite: {3}) (error: {4})", old_path, new_path, overwrite_final, A_LastError)
            return result ? false : true
        } else {
            this.log.err("[TR] Original path '{1}' does not exist", old_path)
            return false
        }
    }

    ; ensure an optional complex field has the correct value
    __VerifyKey(complex_data, key, valid_list) {
        if complex_data.HasKey(key) {
            for index, value in valid_list {
                if (complex_data[key] == value) {
                    return true
                }
            }

            this.log.err("Optional complex data field '{1}' has invalid value '{2}'", key, complex_data[key])
            return false
        } else {
            this.log.debug("Optional complex data field '{1}' does not exist, ignoring", key)
            return true
        }
    }

    ; ensure a complex data structure has the correct fields (and values)
    __VerifyStruct(complex_data, required_list) {
        for index, required in required_list {
            if ! complex_data.HasKey(required) {
                this.log.err("Complex data object is missing '{1}' key", required)
                return false
            }
        }

        ; these values should have already been implicitly verified; ensure anyway
        for index, required_implied in ["Name", "Ensure"] {
            if ! complex_data.HasKey(required_implied) {
                this.log.err("Complex data object is missing '{1}' implied key", required_implied)
                return false
            }
        }

        ; ensure that any optional values present have valid values
        if ! this.__VerifyKey(complex_data, "Backup", [0, 1])
            return false

        if ! this.__VerifyKey(complex_data, "Ignorable", [0, 1])
            return false

        if ! this.__VerifyKey(complex_data, "Local", [0, 1])
            return false

        if ! this.__VerifyKey(complex_data, "Notify", ["Ask", "None", "Tell"])
            return false

        if ! this.__VerifyKey(complex_data, "Overwrite", [0, 1])
            return false

        if ! this.__VerifyKey(complex_data, "Remember", ["Allow", "Deny", "None"])
            return false

        return true
    }
}
