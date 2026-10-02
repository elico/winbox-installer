Unicode True
!include "MUI2.nsh"
!include "x64.nsh"
!include "WinMessages.nsh"

Name "MikroTik URL Handler"

!ifndef OutFile
    OutFile "winbox-tools-setup.exe"
!endif

InstallDir "$PROGRAMFILES64\winbox"
InstallDirRegKey HKLM "Software\MikroTik\WinboxTools" "InstallDir"

RequestExecutionLevel admin

; UI Configuration
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
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
; Install Section
; -------------------------------------------------------------
Section "Install" SecInstall
    ${If} ${RunningX64}
        SetRegView 64
    ${EndIf}

    SetOutPath "$INSTDIR"

    ; Primary executables and helper scripts from src/
    File "connect-to-mt-64.exe"
    File "WinBox.exe"
    File "connect-to-mt.ps1"

    ; Asset files
    SetOutPath "$INSTDIR\assets\img"
    File "assets\img\winbox.png"

    ; Reset working directory to base install directory
    SetOutPath "$INSTDIR"

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; URI Protocol Registration (winbox://)
    WriteRegStr HKLM "Software\Classes\winbox" "" "URL:MikroTik Protocol"
    WriteRegStr HKLM "Software\Classes\winbox" "URL Protocol" ""
    WriteRegStr HKLM "Software\Classes\winbox\shell\open\command" "" '"$INSTDIR\connect-to-mt-64.exe" "-url" "%1"'

    ; Add installation folder to System PATH
    !insertmacro AddToPath "$INSTDIR"

    ; Register in Windows "Installed apps" / "Add or Remove Programs"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "DisplayName" "MikroTik URL Handler & Winbox Tools"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "Publisher" "MikroTik Tools"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools" "NoRepair" 1
SectionEnd

; -------------------------------------------------------------
; Uninstall Section
; -------------------------------------------------------------
Section "Uninstall"
    ${If} ${RunningX64}
        SetRegView 64
    ${EndIf}

    ; Clean Registry
    DeleteRegKey HKLM "Software\Classes\winbox"
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\MikroTikWinboxTools"
    DeleteRegKey HKLM "Software\MikroTik\WinboxTools"

    ; Remove from System PATH
    !insertmacro RemoveFromPath "$INSTDIR"

    ; Clean Files and Directories
    Delete "$INSTDIR\connect-to-mt-64.exe"
    Delete "$INSTDIR\WinBox.exe"
    Delete "$INSTDIR\connect-to-mt.ps1"
    Delete "$INSTDIR\assets\img\winbox.png"
    Delete "$INSTDIR\uninstall.exe"

    RMDir "$INSTDIR\assets\img"
    RMDir "$INSTDIR\assets"
    RMDir "$INSTDIR"
SectionEnd

; -------------------------------------------------------------
; Installer Functions
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

; -------------------------------------------------------------
; Uninstaller Functions (Prefix with un.)
; -------------------------------------------------------------
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
