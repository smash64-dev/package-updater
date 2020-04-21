/*           ,---,                                          ,--,    
           ,--.' |                                        ,--.'|    
           |  |  :                      .--.         ,--, |  | :    
  .--.--.  :  :  :                    .--,`|       ,'_ /| :  : '    
 /  /    ' :  |  |,--.  ,--.--.       |  |.   .--. |  | : |  ' |    
|  :  /`./ |  :  '   | /       \      '--`_ ,'_ /| :  . | '  | |    
|  :  ;_   |  |   /' :.--.  .-. |     ,--,'||  ' | |  . . |  | :    
 \  \    `.'  :  | | | \__\/: . .     |  | '|  | ' |  | | '  : |__  
  `----.   \  |  ' | : ," .--.; |     :  | |:  | : ;  ; | |  | '.'| 
 /  /`--'  /  :  :_:,'/  /  ,.  |   __|  : ''  :  `--'   \;  :    ; 
'--'.     /|  | ,'   ;  :   .'   \.'__/\_: |:  ,      .-./|  ,   /  
  `--'---' `--''     |  ,     .-./|   :    : `--`----'     ---`-'   
                      `--`---'     \   \  /                         
                                    `--`-'  
Requires Autohotkey_L
http://www.autohotkey.com/forum/viewtopic.php?t=65401
*/

Zip(sDir, sZip)
{
    in_wine := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "ntdll", "Ptr"), "AStr", "wine_get_version", "Ptr")
    if in_wine {
        SplitPath, A_ScriptFullPath,, current_dir
        7zip_local := Format("{1}\7za.exe", current_dir)
        7zip_install := "C:\Program Files (x86)\7-Zip\7z.exe"

        if FileExist(7zip_local) {
            RunWait, "%7zip_local%" a "%sZip%" -t"zip" "%sDir%" -r -y,,hide
            return
        }

        if FileExist(7zip_install) {
            RunWait, "%7zip_install%" a "%sZip%" -t"zip" "%sDir%" -r -y,,hide
            return
        }

        ; wine only supports 32-bit
        MsgBox 0x10, Unable to find 7-Zip, Please install 7-Zip (32-bit) within Wine
        return
    }

   If Not FileExist(sZip)
   {
    Header1 := "PK" . Chr(5) . Chr(6)
    VarSetCapacity(Header2, 18, 0)
    file := FileOpen(sZip,"w")
    file.Write(Header1)
    file.RawWrite(Header2,18)
    file.close()
   }
    psh := ComObjCreate( "Shell.Application" )
    pzip := psh.Namespace( sZip )
    pzip.CopyHere( sDir, 4|16 )
    Loop {
        sleep 100
        zippedItems := pzip.Items().count
        ;ToolTip Zipping in progress..
    } Until zippedItems=1 ;because sDir is just one file or folder
    ;ToolTip
}

Unz(sZip, sUnz)
{
    in_wine := DllCall("GetProcAddress", "Ptr", DllCall("GetModuleHandle", "Str", "ntdll", "Ptr"), "AStr", "wine_get_version", "Ptr")
    if in_wine {
        SplitPath, A_ScriptFullPath,, current_dir
        7zip_local := Format("{1}\7za.exe", current_dir)
        7zip_install := "C:\Program Files (x86)\7-Zip\7z.exe"

        if FileExist(7zip_local) {
            RunWait, "%7zip_local%" x "%sZip%" -o"%sUnz%" -y,,hide
            return
        }

        if FileExist(7zip_install) {
            RunWait, "%7zip_install%" x "%sZip%" -o"%sUnz%" -y,,hide
            return
        }

        ; wine only supports 32-bit
        MsgBox 0x10, Unable to find 7-Zip, Please install 7-Zip (32-bit) within Wine
        return
    }

    fso := ComObjCreate("Scripting.FileSystemObject")
    If Not fso.FolderExists(sUnz)  ;http://www.autohotkey.com/forum/viewtopic.php?p=402574
       fso.CreateFolder(sUnz)
    psh  := ComObjCreate("Shell.Application")
    zippedItems := psh.Namespace( sZip ).items().count
    psh.Namespace( sUnz ).CopyHere( psh.Namespace( sZip ).items, 4|16 )
    Loop {
        sleep 100
        unzippedItems := psh.Namespace( sUnz ).items().count
        ;ToolTip Unzipping in progress..
        IfEqual,zippedItems,%unzippedItems%
            break
    }
    ;ToolTip
}