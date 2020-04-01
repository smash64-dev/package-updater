; ini_config.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk

class IniConfig {
    static iclog := {}

    ini_config := ""
    ini_data := {}
    ini_sections := []

    __New(ini_config) {
        iclog := new Logger("ini_config.ahk")
        this.log := iclog

        this.ini_config := ini_config
        if ! FileExist(this.ini_config) {
            this.log.err("Config file '{1}' does not exist", this.ini_config)
            return false
        }

        this.log.verb("Loading config file '{1}' into memory", this.ini_config)
        this.LoadData()
    }

    ; return the entire ini hash object
    GetData() {
        return this.ini_data
    }

    ; return the entire ini object in a JSON string
    GetJSON() {
        return JSON.Dump(this.ini_data)
    }

    ; return an array of sections in the file
    GetSections() {
        return this.ini_sections
    }

    ; same as HasKey, but works with ini sections better
    HasKey(section_name, key_name) {
        return this.ini_data[section_name].HasKey(key_name)
    }

    ; loads ini file data into a hash object
    ; FIXME: does not support ini with unnamed "default" section
    LoadData() {
        IniRead, ini_sections, % this.ini_config

        try {
            loop, parse, ini_sections, `n, `r
            {
                ; help build the object better
                ini_section := A_LoopField
                this.ini_sections.Push(ini_section)
                this.ini_data[ini_section] := {}

                IniRead, section_keys, % this.ini_config, % ini_section

                loop, parse, section_keys, `n, `r
                {
                    section_key := StrSplit(A_LoopField, "=")
                    key := Trim(section_key[1])
                    value := Trim(section_key[2])

                    this.ini_data[ini_section][key] := value
                    this.log.debug("Adding '{1}.{2}' = '{3}'", ini_section, key, value)
                }
            }
        } catch err {
            this.log.err("Unable to read config file '{1}' (error: {2})", this.ini_config, err)
            return false
        }

        return true
    }

    ; updates both file and data and hash object with new config data
    SetData(new_config, remove := 0, dry_run := 0) {
        new_data := new_config.GetData()
        change_count := 0

        try {
            for index, new_section in new_config.GetSections() {
                changed_section := false

                for new_key, new_value in new_data[new_section] {
                    if remove {
                        ; remove an ini key value pair
                        change_count++

                        if ! dry_run {
                            this.ini_data[new_section].Delete(new_key)
                            IniDelete, % this.ini_config, % new_section, % new_key
                            result := A_LastError

                            this.log.verb("Removing '{1}.{2}' from config (error: {3})", new_section, new_key, result)
                        }
                    } else {
                        ; add or update an ini key value pair
                        if ! this.ini_data.HasKey(new_section) and ! dry_run {
                            this.ini_data[new_section] := {}
                            this.log.verb("Adding section '{1}' to object", new_section)
                        }

                        if this.ini_data[new_section][new_key] != new_value {
                            changed_section := true
                            change_count++

                            if ! dry_run {
                                this.ini_data[new_section][new_key] := new_value
                                IniWrite, % new_value, % this.ini_config, % new_section, % new_key
                                result := A_LastError

                                this.log.verb("Updating '{1}.{2}' to '{3}' (error: {4})", new_key, new_section, new_value, result)
                            }
                        }
                    }
                }

                ; add a new line to the end of the section to make it cleaner
                if ! remove and changed_section {
                    if ! dry_run {
                        FileAppend, `n, % this.ini_config
                        result := A_LastError

                        this.log.verb("Appending newline to end of section '{1}' (error: {2})", new_section, result)

                        ; HACK: FileAppend triggers an error code of ERROR_ALREADY_EXISTS but works anyway
                        ; trigger a quick noop-style command to reset A_LastError
                        Run echo ""
                    }
                }

                ; handle entire ini section removal
                if (remove and new_data[new_section]) {
                    change_count++

                    if ! dry_run {
                        this.ini_data.Delete(new_section)
                        IniDelete, % this.ini_config, % new_section
                        result := A_LastError

                        this.log.info("Removing section '{1}' removed (error: {2})", new_section, result)
                    }
                }
            }
        } catch err {
            this.log.err("Unable to read config file '{1}': (error: {2})", this.ini_config, err)
            return false
        }

        return change_count
    }
}
