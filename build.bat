:: build.bat
:: compiles package-updater using ahk2exe.exe
:: you may have to whitelist with antivirus to build this

@ECHO OFF
ECHO Building package-updater...

IF EXIST "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    SET "AHK=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
) ELSE (
    IF EXIST "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" (
        SET "AHK=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe"
    ) ELSE (
        ECHO - Unable to find Ahk2Exe.exe, please install AutoHotkey first (https://www.autohotkey.com/)
        EXIT 1
    )
)

if EXIST "build" (
    ECHO - Cleaning build environment...
    RMDIR /S /Q "build" >nul
)
MKDIR "build"

ECHO - Building to 'build' directory...
"%AHK%" /in "src\updater.ahk" /out "build\package-updater.exe" /icon "res\icon.ico" /cp 65001

ECHO - Creating config file...
COPY "src\updater.cfg" "build\updater.cfg" >nul
COPY "src\user.cfg" "build\user.cfg" >nul

ECHO - Copying Changelog...
COPY "CHANGELOG.md" "build\CHANGELOG.md" >nul

ECHO - Finshed
EXIT 0
