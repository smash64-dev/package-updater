; ini_config.ahk

#Include %A_LineFile%\..\logger.ahk
#Include %A_LineFile%\..\..\ext\json.ahk

class IniConfig {
    static iclog := {}

    config_file := ""
    data := {}
    sections := []

    ; these should only be set once, then read only
    original_data := {}
    original_sections := []

    __New(config_file) {
        iclog := new Logger("ini_config.ahk")
        this.log := iclog

        this.config_file := config_file
        if ! FileExist(this.config_file) {
            this.log.warn("Config file '{1}' does not exist, creating empty file", this.config_file)
            FileAppend, % "", % this.config_file
        }

        ; read the config from disk and update original data structures
        this.ReadConfig(1)
    }

    ; remove sections and properties from the config
    ; an empty section will remove the entire section
    DeleteConfig(new_config) {
        change_count := 0
        new_data := new_config.GetData()
        new_sections := new_config.GetSections()

        for index, new_section in new_sections {
            ; handle recursively deleting an entire section
            ; important: do not use Length() use Count()
            if ! new_data[new_section].Count() {
                this.__DeleteSection(new_section, 1)
                continue
            }

            for new_key, new_value in new_data[new_section] {
                if this.__DeleteProperty(new_section, new_key)
                    change_count++
            }
        }

        return change_count
    }

    ; format the config to be cleaner and more consistent
    FormatConfig() {
        this.log.verb("Formatting config file '{1}'", this.config_file)
        return this.__FormatIni()
    }

    ; return the entire ini hash object
    GetData() {
        return this.data
    }

    ; return the entire ini object in a JSON string
    GetJSON() {
        return JSON.Dump(this.data)
    }

    ; return an array of sections in the file
    GetSections() {
        return this.sections
    }

    ; same as HasKey, but works with ini sections better
    HasKey(section_name, key_name) {
        return this.data[section_name].HasKey(key_name)
    }

    HasSection(section_name) {
        return this.data.HasKey(section_name)
    }

    ; add new sections and properties to the config
    InsertConfig(new_config, update := 0) {
        change_count := 0
        new_data := new_config.GetData()
        new_sections := new_config.GetSections()

        for index, new_section in new_sections {
            for new_key, new_value in new_data[new_section] {
                if this.__InsertProperty(new_section, new_key, new_value, update)
                    change_count++
            }
        }

        return change_count
    }

    ; read the config file from disk
    ; caution, can optionally update the original data
    ReadConfig(update_original := 0) {
        this.log.verb("Loading config file '{1}'", this.config_file)

        this.__ReadIni(data, sections)
        this.data := data
        this.sections := sections

        ; store the original data, in case we ever want to revert
        if update_original {
            this.original_data := JSON.Dump(this.data)
            this.original_sections := JSON.Dump(this.sections)
        }
    }

    ; return the config in memory to the original data structure
    RevertConfig() {
        this.data := JSON.Load(this.original_data)
        this.sections := JSON.Load(this.original_sections)
    }

    ; add and insert new sections and properties into the config
    UpdateConfig(new_config) {
        return this.InsertConfig(new_config, 1)
    }

    ; write the config data to the disk
    WriteConfig(format := 1, dry_run := 0) {
        this.log.verb("Saving config file '{1}'", this.config_file)
        return this.__WriteIni(dry_run)
    }

    ; delete a section if it exists, don't allow deleting keys unless recurse is true
    __DeleteSection(section_name, recurse := 0) {
        if this.data.HasKey(section_name) {
            ; important: do not use Length() use Count()
            if (recurse or ! this.data[section_name].Count()) {
                this.log.verb("Removing section '{1}' from object (recurse: {2})", section_name, recurse)
                this.sections.Delete(section_name)
                this.data.Delete(section_name)
                return true
            } else {
                this.log.warn("Section '{1}' is not empty, use recurse to force", section_name)
                return false
            }
        }
        return false
    }

    ; delete a key value pair in a section if it exists
    __DeleteProperty(section_name, key) {
        this.log.verb("DeleteProperty {1} {2}", section_name, key)
        if this.data[section_name].HasKey(key) {
            this.log.verb("Removing property '{1}.{2}' from object", section_name, key)
            this.data[section_name].Delete(key)

            ; delete the entire section if there are no more keys
            ; important: do not use Length() use Count()
            if ! this.data[section_name].Count() {
                this.__DeleteSection(section_name, 1)
            }
            return true
        }
        return false
    }

    ; create a new section if it doesn't exist
    __InsertSection(section_name) {
        if ! this.data.HasKey(section_name) {
            this.log.verb("Inserting section '{1}' to object", section_name)
            this.sections.Push(section_name)
            this.data[section_name] := {}
            return true
        }
        return false
    }

    ; create a new property if in a section if it doesn't exist
    ; download allow updating unless update is true
    __InsertProperty(section_name, key, value, update := 0) {
        ; if the section was inserted, the property will be created, we will
        ; end up returning true regardless, so we don't need to track this return
        this.__InsertSection(section_name)

        if (this.data[section_name].HasKey(key) and this.data[section_name][key] != value) {
            if update {
                this.log.verb("Updating property '{1}.{2}' = '{3}' to object", section_name, key, value)
                this.data[section_name][key] := value
                return true
            } else {
                this.log.warn("Property '{1}.{2}' already exists in object, use update to force", section_name, key)
                return false
            }
        } else {
            this.log.verb("Inserting property '{1}.{2}' = '{3}' to object", section_name, key, value)
            this.data[section_name][key] := value
            return true
        }

        return false
    }

    ; read ini file from disk, clean up whitespace formatting, and write it back to disk
    __FormatIni() {
        soh := Chr(1)
        FileRead, config_str, % this.config_file

        ; remove excess whitespace around and within sections
        config_str := StrReplace(config_str, "`r`n", soh)
        config_str := RegExReplace(config_str, Format("(.){1}+([[])", soh), Format("$1{1}{1}$2", soh))
        config_str := RegExReplace(config_str, Format("(.){1}{1}+([^/;#[])", soh), Format("$1{1}$2", soh))
        config_str := StrReplace(config_str, soh, "`r`n")

        ; write to file
        config_handle := FileOpen(this.config_file, "w")
        config_handle.Write(config_str)
        config_handle.Close()
    }

    ; loads ini file data into a hash object
    ; FIXME: does not support ini with unnamed "default" section
    __ReadIni(ByRef ref_data, ByRef ref_sections) {
        ref_data := {}
        ref_sections := []

        ; loop through all sections
        IniRead, sections, % this.config_file
        try {
            loop, parse, sections, `n, `r
            {
                ; help build the object better
                section_name := A_LoopField
                ref_sections.Push(section_name)
                ref_data[section_name] := {}

                ; loop through the section's keys
                IniRead, section_keys, % this.config_file, % section_name
                loop, parse, section_keys, `n, `r
                {
                    property := StrSplit(A_LoopField, "=")
                    key := Trim(property[1])

                    ; find everything after the first '='
                    value := Trim(SubStr(A_LoopField, InStr(A_LoopField, property[2])))
                    if (value == A_LoopField) {
                        value := ""
                    }
                    ref_data[section_name][key] := value

                    this.log.debug("Adding property '{1}.{2}' = '{3}'", section_name, key, value)
                }
            }
        } catch err {
            this.log.err("Unable to read config file '{1}' (error: {2})", this.config_file, err)
            return false
        }

        return true
    }

    ; update an existing property if in a section, or create it if it doesn't exist
    __UpdateProperty(section_name, key, value) {
        return this.__InsertProperty(section_name, key, value, 1)
    }

    ; writes ini file data from a hash object
    ; FIXME: does not support ini with unnamed "default" section
    __WriteIni(dry_run := 0) {
        change_count := 0

        try {
            ; compare against the file on disk
            old_data := {}
            old_sections := []
            this.__ReadIni(old_data, old_sections)

            ; add and update new data
            for index, new_section in this.sections {
                for new_key, new_value in this.data[new_section] {
                    ; only count the change if the value is actually different
                    if (this.data[new_section][new_key] != old_data[new_section][new_key]) {
                        change_count++

                        if ! dry_run {
                            IniWrite, % new_value, % this.config_file, % new_section, % new_key
                            result := A_LastError

                            this.log.verb("Updating '{1}.{2}' to '{3}' (error: {4})", new_section, new_key, new_value, result)
                        }
                    }
                }
            }

            ; remove deleted data
            for index, old_section in old_sections {
                ; remove entire section if it doesn't exist
                ; important: do not use Length() use Count()
                if ! this.data[old_section].Count() {
                    change_count++

                    if ! dry_run {
                        IniDelete, % this.config_file, % old_section
                        result := A_LastError

                        this.log.verb("Removing deleted section '{1}' (error: {2})", old_section, result)
                    }
                }

                for old_key, old_value in old_data[old_section] {
                    if ! this.data[old_section].HasKey(old_key) {
                        change_count++

                        if ! dry_run {
                            IniDelete, % this.config_file, % old_section, % old_key
                            result := A_LastError

                            this.log.verb("Removing '{1}.{2}' from '{3}' (error: {4})", new_section, new_key, new_value, result)
                        }
                    }
                }
            }
        } catch err {
            this.log.err("Unable to write config file '{1}': (error: {2})", this.config_file, err)
            return false
        }

        if ! dry_run {
            this.__FormatIni()
        }
        return change_count
    }
}
