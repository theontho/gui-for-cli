!macro NSIS_HOOK_POSTUNINSTALL
  ${If} $UpdateMode <> 1
    SetShellVarContext current

    Delete /REBOOTOK "$INSTDIR\uninstall.exe"
    RmDir /REBOOTOK "$INSTDIR"
    RmDir /REBOOTOK "$LOCALAPPDATA\${PRODUCTNAME}"
    RmDir /REBOOTOK "$LOCALAPPDATA\Programs\${PRODUCTNAME}"

    ${If} $DeleteAppDataCheckboxState = 1
      RmDir /r "$PROFILE\.local\share\${BUNDLEID}"
      RmDir /r "$LOCALAPPDATA\${BUNDLEID}"
      RmDir /r "$APPDATA\${BUNDLEID}"
      RmDir /r "$LOCALAPPDATA\${PRODUCTNAME}"
      RmDir /r "$APPDATA\${PRODUCTNAME}"
      ReadEnvStr $0 "XDG_DATA_HOME"
      ${If} $0 != ""
        RmDir /r "$0\${BUNDLEID}"
      ${EndIf}
    ${EndIf}
  ${EndIf}
!macroend
