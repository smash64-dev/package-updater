:: build.bat
:: compiles package-updater using ahk2exe.exe
:: you may have to whitelist with antivirus to build this

@ECHO OFF
ECHO Building package-updater...

IF EXIST "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    RMDIR /S /Q "build"
    MKDIR "build"

    ECHO - Building to 'build' directory...
    "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" /in "src\updater.ahk" /out "build\package-updater.exe" /icon "res\icon.ico"

    ECHO - Creating config file...
    COPY "conf\example.cfg" "build\updater.cfg" >nul

    ECHO - Finshed
    EXIT 0
) ELSE (
    ECHO - Unable to find Ahk2Exe.exe, please install AutoHotkey first (https://www.autohotkey.com/)
    EXIT 1
)
