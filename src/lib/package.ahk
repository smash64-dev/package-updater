; package.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk
#Include %A_LineFile%\..\..\ext\zip.ahk

class Package {
    static log := {}
    static reserved := {base_directory:true, updater_binary:true, updater_config:true}

    base_directory := ""
    config_data := {}
    config_func := {}
    config_json := ""
    updater_binary := ""
    updater_config := ""

    __New(updater_binary, config := "") {
        plog := new Logger("package.ahk")
        this.log := plog

        this.updater_binary := updater_binary
        SplitPath, updater_binary,, binary_path
        this.updater_config := updater_config != "" ? updater_config : binary_path . "\updater.cfg"

        if FileExist(this.updater_config) {
            ; read through the entire config and turn it into an object
            IniRead, tools_sections, % this.updater_config

            loop, parse, tools_sections, `n, `r
            {
                ; help build the object better
                tools_section := A_LoopField
                this.config_func[tools_section] := true
                this.config_data[tools_section] := {}

                IniRead, section_keys, % this.updater_config, %tools_section%

                loop, parse, section_keys, `n, `r
                {
                    section_key := StrSplit(A_LoopField, "=")
                    key := Trim(section_key[1])
                    value := Trim(section_key[2])

                    this.config_data[tools_section][key] := value
                }
            }
        } else {
            this.log.err(Format("Unable to find config file '{1}'", this.updater_config))
            return false
        }

        this.base_directory := this.__GetBaseDirectory(this.updater_binary, this.config_data["Package"]["Process"])
        this.config_json := JSON.Dump(this.config_data)

        this.log.info(Format("config_json: '{1}'", this.config_json))
    }

    ; allows pull from different section of the config easier
    __Call(method, ByRef arg, args*) {
        if this.config_func[method]
            return this.__GetSectionValue(method, arg, args*)
    }

    ; allows using directory paths or filenames as properties
    __Get(path) {
        if ! Package.reserved[path] {
            directory := this.GetDirectory(StrReplace(path, "_", "\"))

            if directory
                return directory
            else
                return this.GetFile(StrReplace(path, "_", "\"))
        } else {
            return this.path
        }
    }

    ; backs up package to a directory, with the option to trim old backups
    Backup(directory, keep_old := 0) {
        FormatTime, now,, yyyy-MM-dd-HHmmss
        backup_zip := Format("{1}\backup-{2}-{3}.zip", directory, this.config_data["Package"]["Name"], now)
        
        this.log.info(Format("Zipping '{1}' to '{2}'", this.base_directory, backup_zip))
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
                    log.verb(Format("Removing backup file '{1}\{2}'", directory, backup))
                    FileDelete, % Format("{1}\{2}", directory, backup)
                }
            }
        }
    }

    ; grab the full path of a directory relative to the base directory
    GetDirectory(path) {
        fullpath := Format("{1}\{2}", this.base_directory, path)
        if InStr(FileExist(fullpath), "D") {
            return fullpath
        }

        this.log.warn(Format("Directory '{1}' does not exist", fullpath))
        return false
    }

    ; grab the full path of a file relative to the base directory
    GetFile(path) {
        fullpath := Format("{1}\{2}", this.base_directory, path)
        if FileExist(fullpath) {
            return fullpath
        }

        this.log.warn(Format("File '{1}' does not exist", fullpath))
        return false
    }

    ; returns an object of special paths
    GetWatchPaths() {
        watch_hash := {}

        for key, value in this.config_data {
            if RegExMatch(key, "^Watch_") {
                path := this.config_data[key]["Path"]
                watch_hash[path] := key
            }
        }

        return watch_hash
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

        this.log.err("Unable to determine base directory")
        return false
    }

    ; grab values from the config
    __GetSectionValue(sec, key, optional := false) {
        if this.config_data[sec].HasKey(key) {
            return this.config_data[sec][key]
        } else {
            if optional {
                this.log.warn(Format("[{1}]{2} was not found, but value is optional", sec, key))
                return ""
            } else {
                this.log.err(Format("[{1}]{2} was not found", sec, key))
                return false
            }
        }
    }
}
