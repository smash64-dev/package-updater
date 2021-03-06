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
    Backup(directory, tag := "", keep_old := 0) {
        FormatTime, now,, yyyy-MM-dd-HHmmss

        if (tag != "" and ! RegexMatch(tag, "^[-].*$")) {
            tag := Format("-{1}", tag)
        }
        backup_zip := Format("{1}\backup{2}-{3}.zip", directory, tag, now)

        this.log.info("Backing up '{1}' to '{2}'", this.base_directory, backup_zip)
        Zip(this.base_directory, backup_zip)

        ; trim old backups if specified
        if (keep_old > 0) {
            backup_format := Format("{1}\backup{2}*.zip", directory, tag)
            backup_list := ""

            ; find other backups with the same tag
            loop, files, %backup_format%
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

        return backup_zip
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
                path_fixed := StrReplace(path, "/", "\")
                complex_hash[path_fixed] := key

                ; add target paths to complex paths
                if this.main_data[key].HasKey("Target") {
                    path := this.main_data[key]["Target"]
                    path_fixed := StrReplace(path, "/", "\")
                    complex_hash[path_fixed] := key
                }

                ; add content paths to complex paths (ini)
                if this.main_data[key].HasKey("Content") {
                    path := this.main_data[key]["Content"]
                    path_fixed := StrReplace(path, "/", "\")
                    complex_hash[path_fixed] := key
                }
            }
        }

        ; don't copy the override config
        override_config := this.__GetSectionValue("User", "Override", false)
        if (override_config and ! complex_hash.HasKey(override_config)) {
            log.info("Adding user override to complex list, do not transfer")
            complex_hash[override_config] := "User_Override"
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

        key_exists := JSON.Load(this.main_ini.original_data)[section_name].HasKey(key_name)
        key_value := JSON.Load(this.main_ini.original_data)[section_name][key_name]

        ; if the key exists but is empty, it doesn't count, but key=0 does count
        if ((key_exists and key_value != "") or key_value) {
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
                this.log.verb("'{2}' was not found in [{1}], returning '{3}'", section_name, key_name, optional)
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
