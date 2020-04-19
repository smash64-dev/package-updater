/*
 * TaskDialogEx - based on code from MagicBox
 * https://sourceforge.net/projects/magicbox-factory/
 * https://www.autohotkey.com/boards/viewtopic.php?f=6&t=20983
 *
 * License: No portion of MagicBox or any code derived from it can be used in
 * any software that is sold/licensed commercially, except when otherwise noted.
 *
 */

TaskDialogDirect(Instruction, Content := "", Title := "", CustomButtons := "", DefaultButton := 101, MainIcon := 0, Flags := 0, CheckText := "", ExpandedText := "", ExpandedControlText := "", CollapsedControlText := "", Width := 0) {
    Static x64 := A_PtrSize == 8, Button := 0, Radio := 0, Checked := 0

    If (CustomButtons != "") {
        Buttons := StrSplit(CustomButtons, "|")
        cButtons := Buttons.Length()
        VarSetCapacity(pButtons, 4 * cButtons + A_PtrSize * cButtons, 0)
        Loop %cButtons% {
            iButtonText := &(b%A_Index% := Buttons[A_Index])
            NumPut(100 + A_Index, pButtons, (4 + A_PtrSize) * (A_Index - 1), "Int")
            NumPut(iButtonText, pButtons, (4 + A_PtrSize) * A_Index - A_PtrSize, "Ptr")
        }
    } Else {
        cButtons := 0
        pButtons := 0
    }

    ; TASKDIALOGCONFIG structure
    NumPut(VarSetCapacity(TDC, x64 ? 160 : 96, 0), TDC, 0, "UInt") ; cbSize
    NumPut(Flags, TDC, x64 ? 20 : 12, "Int") ; dwFlags
    NumPut(&Title, TDC, x64 ? 28 : 20, "Ptr") ; pszWindowTitle
    NumPut(MainIcon, TDC, x64 ? 36 : 24, "Ptr") ; pszMainIcon
    NumPut(&Instruction, TDC, x64 ? 44 : 28, "Ptr") ; pszMainInstruction
    NumPut(&Content, TDC, x64 ? 52 : 32, "Ptr") ; pszContent
    NumPut(cButtons, TDC, x64 ? 60 : 36, "UInt") ; cButtons
    NumPut(&pButtons, TDC, x64 ? 64 : 40, "Ptr") ; pButtons
    NumPut(DefaultButton, TDC, x64 ? 72 : 44, "Int") ; nDefaultButton
    NumPut(&CheckText, TDC, x64 ? 92 : 60, "Ptr") ; pszVerificationText
    NumPut(&ExpandedText, TDC, x64 ? 100 : 64, "Ptr") ; pszExpandedInformation
    NumPut(&ExpandedControlText, TDC, x64 ? 108 : 68, "Ptr") ; pszExpandedControlText
    NumPut(&CollapsedControlText, TDC, x64 ? 116 : 72, "Ptr") ; pszCollapsedControlText
    NumPut(Width, TDC, x64 ? 156 : 92, "UInt") ; cxWidth

    DllCall("Comctl32.dll\TaskDialogIndirect", "Ptr", &TDC, "Int*", Button, "Int*", Radio, "Int*", Checked)

    button_string := Buttons[Button-100]
    return (CheckText == "") ? [button_string, 0] : [button_string, Checked]
}
