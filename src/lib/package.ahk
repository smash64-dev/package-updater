; package.ahk

#Include %A_LineFile%\..\ini_config.ahk
#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk
#Include %A_LineFile%\..\..\ext\zip.ahk

class Package {
    static log := {}

    base_directory := ""
    complex_regex := "^Ensure_"
    config_data := {}
    config_func := {}
    config_json := ""
    updater_binary := ""
    updater_config := ""

    __New(updater_binary, updater_config := "") {
        plog := new Logger("package.ahk")
        this.log := plog

        this.updater_binary := updater_binary
        SplitPath, updater_binary,, binary_path
        this.updater_config := updater_config != "" ? updater_config : Format("{1}\updater.cfg", binary_path)

        ini_config := new IniConfig(this.updater_config)
        this.config_data := ini_config.GetData()

        ; HACK: useful for __Call
        for index, ini_section in ini_config.GetSections() {
            this.config_func[ini_section] := true
        }

        this.base_directory := this.__GetBaseDirectory(this.updater_binary, this.package("Process", updater_binary))
        this.config_json := ini_config.GetJSON()
        this.log.verb("config_json: '{1}'", this.config_json)
    }

    ; allows pull from different section of the config easier
    __Call(method, ByRef arg, args*) {
        if this.config_func[method] {
            return this.__GetSectionValue(method, arg, args*)
        } else if (method == "path") {
            directory := this.__GetDirectory(arg)
            file := this.__GetFile(arg)

            return directory ? directory : file
        }
    }

    ; backs up package to a directory, with the option to trim old backups
    Backup(directory, keep_old := 0) {
        FormatTime, now,, yyyy-MM-dd-HHmmss
        backup_zip := Format("{1}\backup-{2}-{3}.zip", directory, this.config_data["Package"]["Name"], now)

        this.log.info("Backing up '{1}' to '{2}'", this.base_directory, backup_zip)
        Zip(this.base_directory, backup_zip)

        ; trim old backups if specified
        if (keep_old > 0) {
            backup_list := ""

            loop %save_dir%\*.*
            {
                backup_list := backup_list . "`n" . A_LoopFileName
            }

            Sort backup_list, CLR
            backup_array := StrSplit(backup_list, "`n")
            backup_array.RemoveAt(1, keep_old)

            for index, backup in backup_array {
                if backup {
                    log.verb("Removing backup file '{1}\{2}'", directory, backup)
                    FileDelete, % Format("{1}\{2}", directory, backup)
                }
            }
        }
    }

    ; returns an object of special keys
    GetComplexKeys() {
        complex_hash := {}

        for key, value in this.config_data {
            if RegExMatch(key, this.complex_regex) {
                action := this.config_data[key]["Ensure"]
                complex_hash[key] := action
            }
        }

        return complex_hash
    }

    ; returns an object of special paths
    GetComplexPaths() {
        complex_hash := {}

        for key, value in this.config_data {
            if RegExMatch(key, this.complex_regex) {
                path := this.config_data[key]["Path"]
                complex_hash[path] := key

                ; add target paths to complex paths
                if this.config_data[key].HasKey("Target") {
                    path := this.config_data[key]["Target"]
                    complex_hash[path] := key
                }

                ; add content paths to complex paths (ini)
                if this.config_data[key].HasKey("Content") {
                    path := this.config_data[key]["Content"]
                    complex_hash[path] := key
                }
            }
        }

        return complex_hash
    }

    __GetBaseDirectory(updater_binary, package_binary) {
        ; FileExist works off A_WorkingDir, don't destroy that
        B_WorkingDir = %A_WorkingDir%
        SplitPath, updater_binary,, current_dir

        ; we shouldn't be more than 5 subdirectories deep anyway
        loop, 5 {
            SetWorkingDir, %current_dir%

            if FileExist(package_binary) {
                SetWorkingDir %B_WorkingDir%
                return current_dir
            }

            SplitPath, A_WorkingDir,, current_dir
        }

        this.log.err("Unable to determine base directory from '{1}'", updater_binary)
        return false
    }

    ; grab the full path of a directory relative to the base directory
    __GetDirectory(path) {
        fullpath := Format("{1}\{2}", this.base_directory, path)
        if InStr(FileExist(fullpath), "D") {
            return fullpath
        }

        this.log.warn("Directory '{1}' does not exist", fullpath)
        return false
    }

    ; grab the full path of a file relative to the base directory
    __GetFile(path) {
        fullpath := Format("{1}\{2}", this.base_directory, path)
        if FileExist(fullpath) {
            return fullpath
        }

        this.log.warn("File '{1}' does not exist", fullpath)
        return false
    }

    ; grab values from the config, using this instead of something from IniConfig
    ; because we're using this directly in __Call to do object magic
    __GetSectionValue(section_name, key_name, optional := "") {
        if this.config_data[section_name].Haskey(key_name) {
            return this.config_data[section_name][key_name]
        } else {
            if (optional != "") {
                this.log.warn("'{2}' was not found in [{1}] was not found, returning '{3}'", section_name, key_name, optional)
                return optional
            } else {
                this.log.err("'{2}' was not found in [{1}] was not found, field required", section_name, key_name)
                return false
            }
        }
    }
}
