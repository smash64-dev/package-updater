; transfer.ahk

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
            this.log.err(Format("Unable to find from directory '{1}'", src_dir))
            return false
        }

        if InStr(FileExist(dest_dir), "D") {
            this.dest_dir := dest_dir
        } else {
            this.log.err(Format("Unable to find from directory '{1}'", dest_dir))
            return false
        }
    }

    ; move unmanaged files or directories from one directory to another
    DoBasicFiles(ignore_list) {
        ; create every directory we might need
        ; if we want to delete a directory we will do it later

        from_pattern := Format("{1}\*.*", this.src_dir)
        loop files, % from_pattern, DR
        {
            relative_path := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")
            full_path := Format("{1}\{2}", this.dest_dir, relative_path)

            if ! InStr(FileExist(full_path), "D") {
                FileCreateDir % full_path
                this.log.info(Format("FileCreateDir '{1}' ({2})", full_path, A_LastError))
            }
        }

        ; transfer files over ONLY if they are not being watched
        loop files, % from_pattern, FR
        {
            relative_path := StrReplace(A_LoopFileFullPath, this.src_dir . "\", "")
            full_path := Format("{1}\{2}", this.dest_dir, relative_path)

            if ! ignore_list.HasKey(relative_path) {
                FileCopy, % A_LoopFileFullPath, % full_path, 1
                log.info(Format("FileCopy '{1}' '{2}' ({3})", A_LoopFileFullPath, full_path, A_LastError))
            }
        }
    }

    ; handle managed file or directory based on specification
    DoComplexFile(file_data) {
        action := file_data["Action"]

        switch action
        {
            ; "CRUD"
            case "Create":          return this.__doCreateAction(file_data)
            case "Read":            return true
            case "Update":          return this.__doUpdateAction(file_data)
            case "UpdatePartial":   return this.__doUpdatePartialAction(file_data)
            case "Delete":          return this.__doDeleteAction(file_data)
            
            default :
                this.log.error("Unknown action '{1}'", action)
                return false
        }
    }

    GetDestPath(relative_path) {
        return Format("{1}\{2}", this.dest_dir, relative_path)
    }

    GetSrcPath(relative_path) {
        return Format("{1}\{2}", this.src_dir, relative_path)
    }

    __doCreateAction(file_data) {
        if ! FileExist(this.GetDestPath(file_data["Path"])) {
            FileCopy, % this.GetSrcPath(file_data["Path"]), % this.GetDestPath(file_data["Path"])
            log.info(Format("FileCopy '{1}' '{2}' ({3})", this.GetSrcPath(file_data["Path"]), this.GetDestPath(file_data["Path"]), A_LastError))
        }
    }

    __doUpdateAction(file_data) {
        return true
    }

    __doUpdatePartialAction(file_data) {
        return true
    }

    __doDeleteAction(file_data) {
        return true
    }
}

