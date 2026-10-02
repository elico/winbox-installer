Unicode True
!include "MUI2.nsh"
!include "x64.nsh"
!include "WinMessages.nsh"
!include "Sections.nsh"

Name "MikroTik URL Handler"

!ifndef OutFile
    !define OutFile "..\dist\winbox-tools-setup.exe"
!endif
OutFile "${OutFile}"

InstallDir "$PROGRAMFILES64\winbox"
InstallDirRegKey HKLM "Software\MikroTik\WinboxTools" "InstallDir"

RequestExecutionLevel admin

; -------------------------------------------------------------
; Setup Types (InstType)
; -------------------------------------------------------------
; InstType 1 = Typical (Go engine default)
; InstType 2 = Custom
InstType "Typical"
InstType "Custom"

; UI Configuration
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS       ; Components page with InstType dropdown
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; -------------------------------------------------------------
; PATH Helper Macros
; -------------------------------------------------------------
!macro AddToPath Directory
    ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
    Push "$0"
    Push "${Directory}"
    Call StrContains
    Pop $1
    StrCmp $1 "true" +3 0
        WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$0;${Directory}"
        SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend

!macro RemoveFromPath Directory
    ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
    Push "$0"
    Push "${Directory};"
    Call un.StrReplace
    Pop $0
    Push "$0"
    Push ";${Directory}"
    Call un.StrReplace
    Pop $0
    Push "$0"
    Push "${Directory}"
    Call un.StrReplace
    Pop $0
    WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$0"
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend

; -------------------------------------------------------------
; 1. Core Section (Always Installed - Hidden with hyphen "-")
; -------------------------------------------------------------
Section "-Core" SecCore
    ${If} ${RunningX64}
        SetRegView 64
    ${EndIf}

    SetShellVarContext all
    SetOutPath "$INSTDIR"

    ; Base utilities
    File "WinBox.exe"
    File "connect-to-mt.ps1"

    ; Install BOTH binaries unconditionally so both reside on disk
    File "connect-to-mt-64-go.exe"
    File "connect-to-mt-64-c.exe"

    ; Assets
    SetOutPath "$INSTDIR\assets\img"
    File "assets\img\winbox.png"
    SetOutPath "$INSTDIR"

    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Register winbox:// Protocol Handler in Registry
    WriteRegStr HKLM "Software\Classes\winbox" "" "URL:MikroTik Protocol"
    WriteRegStr HKLM "Software\Classes\winbox" "URL Protocol" ""
    WriteRegStr HKLM "Software\Classes\winbox\shell\open\command" "" '"$INSTDIR\connect-to-mt-64.exe" "-url" "%1"'

    ; Add to System PATH
    !insertmacro AddToPath "$INSTDIR"

    ; Start Menu Shortcuts
    CreateDirectory "$SMPROGRAMS\MikroTik"
    CreateShortcut "$SMPROGRAMS\MikroTik\WinBox.lnk" "$INSTDIR\WinBox.exe" "" "$INSTDIR\WinBox.exe" 0 "" "" "Launch MikroTik WinBox"
    CreateShortcut "$SMPROGRAMS\MikroTik\Uninstall.lnk" "$INSTDIR\uninstall.exe"

    ; Add/Remove Programs
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "DisplayName" "MikroTik URL Handler & Winbox Tools"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "DisplayIcon" '"$INSTDIR\WinBox.exe",0'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "Publisher" "MikroTik Tools"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "NoRepair" 1
SectionEnd

; -------------------------------------------------------------
; 2. Choice of Active Engine (Configures connect-to-mt-64.exe)
; -------------------------------------------------------------
SectionGroup /e "Default URL Handler Engine" SecEngineGroup

    ; SectionIn 1 2 -> Enabled in both Typical (1) and Custom (2)
    Section "Go Engine (Default)" SecEngineGo
        SectionIn 1 2
        SetOutPath "$INSTDIR"
        CopyFiles /SILENT "$INSTDIR\connect-to-mt-64-go.exe" "$INSTDIR\connect-to-mt-64.exe"
        WriteRegStr HKLM "Software\MikroTik\WinboxTools" "ActiveEngine" "Go"
    SectionEnd

    ; SectionIn 2 -> Only available under Custom (2)
    Section "C Engine (Lightweight)" SecEngineC
        SectionIn 2
        SetOutPath "$INSTDIR"
        CopyFiles /SILENT "$INSTDIR\connect-to-mt-64-c.exe" "$INSTDIR\connect-to-mt-64.exe"
        WriteRegStr HKLM "Software\MikroTik\WinboxTools" "ActiveEngine" "C"
    SectionEnd

SectionGroupEnd

; Enforce radio button exclusivity between Go and C engines in Custom mode
Function .onSelChange
    !insertmacro StartRadioButtons $1
        !insertmacro RadioButton ${SecEngineGo}
        !insertmacro RadioButton ${SecEngineC}
    !insertmacro EndRadioButtons
FunctionEnd

; Component Descriptions
LangString DESC_SecEngineGo ${LANG_ENGLISH} "Sets the Go implementation as the active connect-to-mt-64.exe."
LangString DESC_SecEngineC  ${LANG_ENGLISH} "Sets the lightweight C implementation as the active connect-to-mt-64.exe."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecEngineGo} $(DESC_SecEngineGo)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecEngineC}  $(DESC_SecEngineC)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; -------------------------------------------------------------
; Uninstall Section
; -------------------------------------------------------------
Section "Uninstall"
    ${If} ${RunningX64}
        SetRegView 64
    ${EndIf}

    SetShellVarContext all

    Delete "$SMPROGRAMS\MikroTik\WinBox.lnk"
    Delete "$SMPROGRAMS\MikroTik\Uninstall.lnk"
    RMDir "$SMPROGRAMS\MikroTik"

    DeleteRegKey HKLM "Software\Classes\winbox"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools"
    DeleteRegKey HKLM "Software\MikroTik\WinboxTools"

    !insertmacro RemoveFromPath "$INSTDIR"

    ; Delete active executable and both stored variants
    Delete "$INSTDIR\connect-to-mt-64.exe"
    Delete "$INSTDIR\connect-to-mt-64-go.exe"
    Delete "$INSTDIR\connect-to-mt-64-c.exe"
    Delete "$INSTDIR\WinBox.exe"
    Delete "$INSTDIR\connect-to-mt.ps1"
    Delete "$INSTDIR\assets\img\winbox.png"
    Delete "$INSTDIR\uninstall.exe"

    RMDir "$INSTDIR\assets\img"
    RMDir "$INSTDIR\assets"
    RMDir "$INSTDIR"
SectionEnd

; -------------------------------------------------------------
; Helper Functions
; -------------------------------------------------------------
Function StrContains
    Exch $1 ; needle
    Exch
    Exch $0 ; haystack
    Push $2
    Push $3
    Push $4
    StrCpy $2 -1
    StrLen $3 $1
    loop:
        IntOp $2 $2 + 1
        StrCpy $4 $0 $3 $2
        StrCmp $4 "" notfound
        StrCmp $4 $1 found loop
    found:
        StrCpy $1 "true"
        Goto done
    notfound:
        StrCpy $1 "false"
    done:
        Pop $4
        Pop $3
        Pop $2
        Pop $0
        Exch $1
FunctionEnd

Function un.StrReplace
    Exch $R0 ; needle
    Exch
    Exch $R1 ; haystack
    Push $R2
    Push $R3
    Push $R4
    Push $R5
    StrLen $R2 $R0
    StrCpy $R3 ""
    loop:
        StrCpy $R4 $R1 $R2
        StrCmp $R4 $R0 found
        StrCmp $R1 "" done
        StrCpy $R4 $R1 1
        StrCpy $R3 "$R3$R4"
        StrCpy $R1 $R1 "" 1
        Goto loop
    found:
        StrCpy $R1 $R1 "" $R2
        Goto loop
    done:
        StrCpy $R1 $R3
        Pop $R5
        Pop $R4
        Pop $R3
        Pop $R2
        Pop $R0
        Exch $R1
FunctionEnd
