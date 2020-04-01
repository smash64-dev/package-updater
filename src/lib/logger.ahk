; logger.ahk

class Logger {
    ; helps build methods like log.crit() and log.warn()
    static loglevels := {crit: [1, "C"], err:[2, "E"], warn:[3, "W"], info:[4, "I"], verb:[5, "V"], debug:[6, "D"]}

    tag := ""
    verbosity := 6

    __New(tag := "") {
        this.tag := tag ? tag : A_ScriptName
        is_compiled := A_IsCompiled

        ; have a different verbosity level when compiled
        if is_compiled {
            this.verbosity := 6
        }
    }

    ; allows calling different log levels from the object
    __Call(method, ByRef arg, args*) {
        if Logger.loglevels[method]
            return this.__logger(Logger.loglevels[method], arg, args*)
    }

    ; log message to DebugView (https://docs.microsoft.com/en-us/sysinternals/downloads/debugview)
    __logger(level, message := "", args*) {
        if level[1] <= this.verbosity
            OutputDebug % Format("| {1} | {2} | {3}", level[2], this.tag, Format(message, args*))
    }
}
