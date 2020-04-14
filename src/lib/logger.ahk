; logger.ahk

class Logger {
    ; helps build methods like log.crit() and log.warn()
    static loglevels := {crit: [1, "C"], err:[2, "E"], warn:[3, "W"], info:[4, "I"], verb:[5, "V"], debug:[6, "D"]}
    static verbosity := 0

    last_level := ""
    last_message := ""
    tag := ""

    __New(tag := "", verbosity := 0) {
        this.tag := tag ? tag : A_ScriptName
        is_compiled := A_IsCompiled

        for method, level in Logger.loglevels {
            if (level[2] == verbosity and ! Logger.verbosity) {
                Logger.verbosity := level[1]
            }
        }

        ; have a different verbosity level when compiled
        if (! verbosity and ! Logger.verbosity) {
            if is_compiled {
                Logger.verbosity := 3
            } else {
                Logger.verbosity := 4
            }
        }
    }

    ; allows calling different log levels from the object
    __Call(method, ByRef arg, args*) {
        if Logger.loglevels[method]
            return this.__logger(Logger.loglevels[method], arg, args*)
    }

    ; log message to DebugView (https://docs.microsoft.com/en-us/sysinternals/downloads/debugview)
    __logger(level, message := "", args*) {
        ; store the last message we sent in case we ever need it
        this.last_level := level[2]
        this.last_message := Format(message, args*)

        if level[1] <= this.verbosity
            OutputDebug % Format("| {1} | {2} | {3}", level[2], this.tag, Format(message, args*))
    }
}
