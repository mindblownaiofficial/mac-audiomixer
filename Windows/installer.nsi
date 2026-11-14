; Audio Mixer for Windows - per-user installer (no administrator rights needed).
; Driven by build.ps1, which passes VERSION, STAGE, ICON and OUTPUT.

Unicode true
!include "MUI2.nsh"

!define APP_NAME "Audio Mixer"
!define APP_EXE "AudioMixer.exe"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AudioMixer"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

Name "${APP_NAME}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\Audio Mixer"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey "CompanyName" "MindblownAI"
VIAddVersionKey "LegalCopyright" "MindblownAI"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${APP_NAME}"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
!ifdef UNINSTALLER_ONLY
  ; Build helper: emit the uninstaller next to this file so it can be signed, then stop.
  SetSilent silent
  WriteUninstaller "$EXEDIR\Uninstall.exe"
  Quit
!endif
FunctionEnd

Section "Install"
  ; A running copy keeps the file locked.
  nsExec::Exec 'taskkill /F /IM ${APP_EXE}'
  Sleep 400

  SetOutPath "$INSTDIR"
  File "${STAGE}\${APP_EXE}"
!ifndef UNINSTALLER_ONLY
  File "${STAGE}\Uninstall.exe"
!endif

  CreateShortCut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "MindblownAI"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" 400
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /F /IM ${APP_EXE}'
  Sleep 400

  ; Routes live in Windows itself, so they outlast the app unless they are cleared here.
  IfSilent skipReset
  MessageBox MB_YESNO|MB_ICONQUESTION "Also send every app back to the system default output?$\n$\nChoose No to keep the per-app devices you set. They stay in Windows under Settings > System > Sound > Volume mixer." IDNO skipReset
  ExecWait '"$INSTDIR\${APP_EXE}" --reset-routes'
  skipReset:

  DeleteRegValue HKCU "${RUN_KEY}" "AudioMixer"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir /r "$APPDATA\AudioMixer"
  RMDir /r "$LOCALAPPDATA\AudioMixer"
SectionEnd
