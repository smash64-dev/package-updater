; package.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\json.ahk

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
            this.log.info(this.updater_config)
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

    ; grab values from the config, with an optional default 
    __GetSectionValue(sec, key, default_value := "") {
        if this.config_data[sec].HasKey(key)
            return this.config_data[sec][key]
        else
            return default_value
    }
}
