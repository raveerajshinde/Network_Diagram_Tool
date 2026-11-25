; NetArch Designer 1.0.0 (fix 4) installer
; fix 4: setup wizard no longer asks for RBI entity types; Users & Roles shows only diagram roles/permissions.
; fix 3: diagrams-only UI (inventory, compliance, governance and dashboard tabs removed).
; fix 1: SQL Server-fixed server.  fix 2: server runs with no cmd window (NetArchServer.exe is now a
; window-less starter for the console program NetArchServerCore.exe); clearer finish page.
;   Silent:  /S   /S /FIREWALL   /S /CLIENT=http://host:8765   /S /D=D:\Apps\NetArch (last)

Unicode true
Target amd64-unicode
SetCompressor /SOLID lzma
RequestExecutionLevel admin
ManifestDPIAware true

!define PRODUCT     "NetArch Designer"
!define VERSION     "1.0.0.4"
!define VERSION_TXT "1.0.0 (fix 4)"
!define PUBLISHER   "NetArch Designer"
!define TASKNAME    "NetArch Designer Server"
!define UNINSTKEY   "Software\Microsoft\Windows\CurrentVersion\Uninstall\NetArchDesigner"
!define APPKEY      "Software\NetArchDesigner"
!define PS          '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File'

Name "${PRODUCT}"
Caption "${PRODUCT} ${VERSION_TXT} Setup"
OutFile "NetArchDesigner-Setup-1.0.0-fix4.exe"
InstallDir "$PROGRAMFILES64\NetArch Designer"
InstallDirRegKey HKLM "${APPKEY}" "InstallDir"
BrandingText "${PRODUCT} ${VERSION_TXT}"
ShowInstDetails hide
ShowUninstDetails hide

VIProductVersion "${VERSION}"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "ProductVersion" "${VERSION_TXT}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${PRODUCT} Setup"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "LegalCopyright" "${PUBLISHER}"

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!include "Sections.nsh"

!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "modern-wizard.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "modern-wizard.bmp"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "modern-header.bmp"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC

Var ClientUrl
Var UrlField
Var ProgData

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "payload\LICENSE.txt"
!insertmacro MUI_PAGE_COMPONENTS
Page custom ClientPageShow ClientPageLeave
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\NetArchDesigner.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${PRODUCT} now"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\docs\README.html"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Show the administrator guide"
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------- sections

Section "-Stop running server"
  SetRegView 64
  IfFileExists "$INSTDIR\tools\service.ps1" 0 +3
    DetailPrint "Stopping the running server..."
    nsExec::ExecToLog '${PS} "$INSTDIR\tools\service.ps1" -Action stop'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchServer.exe /T'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchServerCore.exe /T'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchDesigner.exe /T'
  Sleep 1500
SectionEnd

Section "Client launcher (required)" SEC_CLIENT
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "payload\NetArchDesigner.exe"
  File "payload\LICENSE.txt"
  SetOutPath "$INSTDIR\docs"
  File /r "payload\docs\*"
  SetOutPath "$INSTDIR\tools"
  File "payload\tools\service.ps1"
SectionEnd

Section "Server" SEC_SERVER
  ; remove the previous server build first so no stale files are left behind
  RMDir /r "$INSTDIR\server"
  SetOutPath "$INSTDIR\server"
  File /r "payload\server\*"
SectionEnd

Section "Desktop shortcut" SEC_DESKTOP
SectionEnd

Section /o "Allow LAN access (firewall rule, TCP 8765)" SEC_FW
SectionEnd

Section "-Configure"
  SetRegView 64
  SetShellVarContext all
  ReadEnvStr $ProgData PROGRAMDATA
  StrCmp $ProgData "" 0 +2
    StrCpy $ProgData "C:\ProgramData"
  CreateDirectory "$ProgData\NetArchDesigner"
  CreateDirectory "$ProgData\NetArchDesigner\logs"
  CreateDirectory "$ProgData\NetArchDesigner\backups"

  ; client.ini: client-only installs always point at the given server;
  ; server installs keep an existing file (setup may have changed the port).
  ${If} ${SectionIsSelected} ${SEC_SERVER}
    IfFileExists "$ProgData\NetArchDesigner\client.ini" +2 0
      Call WriteLocalClientIni
  ${Else}
    Call WriteRemoteClientIni
  ${EndIf}

  ${If} ${SectionIsSelected} ${SEC_SERVER}
    DetailPrint "Restricting $ProgData\NetArchDesigner to SYSTEM and Administrators..."
    nsExec::ExecToLog '"$SYSDIR\icacls.exe" "$ProgData\NetArchDesigner" /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F /grant:r *S-1-5-32-544:(OI)(CI)F /T /C /Q'
    nsExec::ExecToLog '"$SYSDIR\icacls.exe" "$ProgData\NetArchDesigner" /grant *S-1-5-32-545:(RX)'
    nsExec::ExecToLog '"$SYSDIR\icacls.exe" "$ProgData\NetArchDesigner\client.ini" /grant *S-1-5-32-545:(R)'

    DetailPrint "Registering the '${TASKNAME}' scheduled task..."
    nsExec::ExecToLog '${PS} "$INSTDIR\tools\service.ps1" -Action install -Exe "$INSTDIR\server\NetArchServer.exe"'
    Pop $0
    ${If} $0 != 0
      DetailPrint "Scheduled task registration returned $0 - starting the server directly."
      Exec '"$INSTDIR\server\NetArchServer.exe" serve'
    ${EndIf}
    DetailPrint "Starting the server (this can take up to a minute)..."
    nsExec::ExecToLog '${PS} "$INSTDIR\tools\service.ps1" -Action wait'
    ${If} ${SectionIsSelected} ${SEC_FW}
      DetailPrint "Adding Windows Firewall rule for TCP 8765..."
      nsExec::ExecToLog '${PS} "$INSTDIR\tools\service.ps1" -Action firewall-open'
    ${EndIf}
    WriteRegDWORD HKLM "${APPKEY}" "Server" 1
  ${Else}
    WriteRegDWORD HKLM "${APPKEY}" "Server" 0
  ${EndIf}

  ; shortcuts
  CreateDirectory "$SMPROGRAMS\${PRODUCT}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT}\${PRODUCT}.lnk" "$INSTDIR\NetArchDesigner.exe"
  CreateShortCut "$SMPROGRAMS\${PRODUCT}\Administrator Guide.lnk" "$INSTDIR\docs\README.html"
  CreateShortCut "$SMPROGRAMS\${PRODUCT}\Uninstall ${PRODUCT}.lnk" "$INSTDIR\Uninstall.exe"
  ${If} ${SectionIsSelected} ${SEC_SERVER}
    CreateShortCut "$SMPROGRAMS\${PRODUCT}\Server Logs.lnk" "$ProgData\NetArchDesigner\logs"
    CreateShortCut "$SMPROGRAMS\${PRODUCT}\Server Folder.lnk" "$INSTDIR\server"
  ${EndIf}
  ${If} ${SectionIsSelected} ${SEC_DESKTOP}
    CreateShortCut "$DESKTOP\${PRODUCT}.lnk" "$INSTDIR\NetArchDesigner.exe"
  ${EndIf}

  ; uninstaller + Add/Remove Programs
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${APPKEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${APPKEY}" "Version" "${VERSION_TXT}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${PRODUCT}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION_TXT}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\NetArchDesigner.exe"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" "$0"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CLIENT} "Desktop launcher, Start Menu entries, documentation and uninstaller."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_SERVER} "Web/API server, database migrations and CLI tools. Runs as the '${TASKNAME}' scheduled task (SYSTEM, at startup). Untick on user workstations."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DESKTOP} "Put a ${PRODUCT} shortcut on the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_FW} "Allow other PCs on the LAN to reach this server (Windows Firewall, Domain/Private profiles). Only for a central server."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; ---------------------------------------------------------------- helpers

Function WriteLocalClientIni
  FileOpen $0 "$ProgData\NetArchDesigner\client.ini" w
  FileWrite $0 "[client]$\r$\nserver_url = http://127.0.0.1:8765$\r$\n"
  FileClose $0
FunctionEnd

Function WriteRemoteClientIni
  FileOpen $0 "$ProgData\NetArchDesigner\client.ini" w
  FileWrite $0 "[client]$\r$\nserver_url = $ClientUrl$\r$\n"
  FileClose $0
FunctionEnd

Function ClientPageShow
  ${If} ${SectionIsSelected} ${SEC_SERVER}
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "Server address" "This PC is a workstation. Enter the address of the central ${PRODUCT} server."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 24u "Server URL (for example http://netarch-srv01:8765):"
  Pop $0
  ${NSD_CreateText} 0 26u 100% 12u "$ClientUrl"
  Pop $UrlField
  nsDialogs::Show
FunctionEnd

Function ClientPageLeave
  ${NSD_GetText} $UrlField $ClientUrl
  StrCpy $0 $ClientUrl 7
  StrCpy $1 $ClientUrl 8
  ${If} $0 != "http://"
  ${AndIf} $1 != "https://"
    MessageBox MB_ICONEXCLAMATION "Enter a URL that starts with http:// or https://"
    Abort
  ${EndIf}
FunctionEnd

Function .onSelChange
  ${IfNot} ${SectionIsSelected} ${SEC_SERVER}
    !insertmacro UnselectSection ${SEC_FW}
  ${EndIf}
FunctionEnd

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "${PRODUCT} requires 64-bit Windows."
    Abort
  ${EndIf}
  SetRegView 64
  StrCpy $ClientUrl "http://"

  ; previous client-only install -> keep it client-only by default
  ReadRegDWORD $0 HKLM "${APPKEY}" "Server"
  ReadRegStr $1 HKLM "${APPKEY}" "InstallDir"
  ${If} $1 != ""
  ${AndIf} $0 == 0
    !insertmacro UnselectSection ${SEC_SERVER}
    ReadEnvStr $2 PROGRAMDATA
    ReadINIStr $3 "$2\NetArchDesigner\client.ini" "client" "server_url"
    ${If} $3 != ""
      StrCpy $ClientUrl $3
    ${EndIf}
  ${EndIf}

  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/CLIENT=" $R1
  ${IfNot} ${Errors}
    ; strip optional quotes
    StrCpy $R2 $R1 1
    ${If} $R2 == '"'
      StrCpy $R1 $R1 "" 1
      StrCpy $R1 $R1 -1
    ${EndIf}
    StrCpy $ClientUrl $R1
    !insertmacro UnselectSection ${SEC_SERVER}
    !insertmacro UnselectSection ${SEC_FW}
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/FIREWALL" $R1
  ${IfNot} ${Errors}
    !insertmacro SelectSection ${SEC_FW}
  ${EndIf}
FunctionEnd

; ---------------------------------------------------------------- uninstaller

Function un.onInit
  SetRegView 64
FunctionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext all
  IfFileExists "$INSTDIR\tools\service.ps1" 0 +2
    nsExec::ExecToLog '${PS} "$INSTDIR\tools\service.ps1" -Action uninstall'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchServer.exe /T'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchServerCore.exe /T'
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /IM NetArchDesigner.exe /T'
  Sleep 1500

  RMDir /r "$INSTDIR\server"
  RMDir /r "$INSTDIR\docs"
  RMDir /r "$INSTDIR\tools"
  Delete "$INSTDIR\NetArchDesigner.exe"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  RMDir /r "$SMPROGRAMS\${PRODUCT}"
  Delete "$DESKTOP\${PRODUCT}.lnk"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "${APPKEY}"

  ${IfNot} ${Silent}
    ReadEnvStr $0 PROGRAMDATA
    MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 "Also delete the settings, logs and backups in $0\NetArchDesigner?$\r$\n$\r$\nThe SQL Server database is never deleted." IDNO keep
      RMDir /r "$0\NetArchDesigner"
    keep:
  ${EndIf}
SectionEnd
