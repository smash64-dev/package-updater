; package.ahk

#Include %A_LineFile%\..\ini_config.ahk
#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk
#Include %A_LineFile%\..\..\ext\zip.ahk

class Package {
    static log := {}

    base_directory := ""
    complex_regex := "^Ensure_"
    main_config_path := ""
    main_data := {}
    main_ini := {}
    updater_binary := ""
    user_config_path := ""
    user_data := {}
    user_ini := {}

    __New(updater_binary, main_config := "") {
        plog := new Logger("package.ahk")
        this.log := plog

        ; splitpath doesn't like forward slashes in paths
        this.updater_binary := StrReplace(updater_binary, "/", "\")
        SplitPath, % this.updater_binary,, binary_path
        this.main_config_path := main_config ? main_config : Format("{1}\updater.cfg", binary_path)

        this.main_ini := new IniConfig(this.main_config_path)
        this.ReloadConfigFromDisk(1)
    }

    ; allows pull from different section of the config easier
    __Call(method, ByRef arg, args*) {
        if this.main_ini.HasSection(method) {
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
        backup_zip := Format("{1}\backup-{2}-{3}.zip", directory, this.__GetSectionValue("Package", "Name"), now)

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

        for key, value in this.main_data {
            if RegExMatch(key, this.complex_regex) {
                action := this.main_data[key]["Ensure"]
                complex_hash[key] := action
            }
        }

        return complex_hash
    }

    ; returns an object of special paths
    GetComplexPaths() {
        complex_hash := {}

        for key, value in this.main_data {
            if RegExMatch(key, this.complex_regex) {
                path := this.main_data[key]["Path"]
                complex_hash[path] := key

                ; add target paths to complex paths
                if this.main_data[key].HasKey("Target") {
                    path := this.main_data[key]["Target"]
                    complex_hash[path] := key
                }

                ; add content paths to complex paths (ini)
                if this.main_data[key].HasKey("Content") {
                    path := this.main_data[key]["Content"]
                    complex_hash[path] := key
                }
            }
        }

        return complex_hash
    }

    ReloadConfigFromDisk(update_original := 0) {
        ; load the base config and store it in the object
        this.main_ini.ReadConfig(update_original)
        this.main_data := this.main_ini.GetData()

        ; package_binary can be defined with a BaseFile value, if not drop
        ; to the package process or updater binary
        package_binary := this.__GetSectionValue("Package", "BaseFile", this.__GetSectionValue("Package", "Process", this.updater_binary))
        this.base_directory := this.__GetBaseDirectory(this.updater_binary, package_binary)

        ; we've already created a user object, just reload it
        if (this.user_config_path) {
            if (! this.user_ini.Count()) {
                this.user_ini := new IniConfig(this.user_config_path)
            }

            this.user_ini.ReadConfig(update_original)
            this.main_ini.InsertConfig(this.user_ini)

            ; store the extra user data into the object
            this.main_data := this.main_ini.GetData()
        } else {
            override_config := this.__GetSectionValue("User", "Override", false)
            SplitPath, override_config,, override_dir

            ; if a user override config is defined and present, INSERT new values into the object
            ; this will not overwrite existing values, consider updater.cfg read-only from this perspective
            ; this will create an override config if the parent directory exists
            if (override_config and this.__GetDirectory(override_dir)) {
                this.user_config_path := Format("{1}\{2}", this.base_directory, override_config)
                this.user_ini := new IniConfig(this.user_config_path)
                this.main_ini.InsertConfig(this.user_ini)

                ; store the extra user data into the object
                this.main_data := this.main_ini.GetData()
            }
        }

        this.log.verb("config_json: '{1}'", this.main_ini.GetJSON())
    }

    ; writes a property to the user file, if possible
    UpdateUserProperty(section_name, key_name, value) {
        if (this.__CanUpdateUserProperty(section_name, key_name)) {
            this.log.verb("Writing '{1}.{2}' = '{3}' to user config", section_name, key_name, value)

            this.user_ini.__UpdateProperty(section_name, key_name, value)
            this.user_ini.WriteConfig(1)
            this.ReloadConfigFromDisk()

            if (this.user_ini.data[section_name][key_name] == value) {
                return true
            } else {
                this.log.warn("'{1}.{2}' did not appear to update in user config", section_name, key_name)
                return false
            }
        } else {
            this.log.warn("Property '{1}.{2}' is not user configurable", section_name, key_name)
            return false
        }
    }

    ; determine if the main config already has a key present
    __CanUpdateUserProperty(section_name, key_name) {
        if (! this.__HasUserConfig()) {
            this.log.warn("Cannot update user property '{1}.{2}', no user config", section_name, key_name)
            return false
        }

        if (JSON.Load(this.main_ini.original_data)[section_name][key_name]) {
            this.log.warn("Cannot update user property '{1}.{2}' exists in main config", section_name, key_name)
            return false
        }

        return true
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
        if this.main_data[section_name].Haskey(key_name) {
            return this.main_data[section_name][key_name]
        } else {
            if (optional or StrLen(optional) > 0) {
                this.log.warn("'{2}' was not found in [{1}], returning '{3}'", section_name, key_name, optional)
                return optional
            } else {
                this.log.err("'{2}' was not found in [{1}], field required", section_name, key_name)
                return false
            }
        }
    }

    __HasUserConfig() {
        return (FileExist(this.user_config_path) and this.user_ini.config_file)
    }
}
