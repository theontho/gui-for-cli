!macro NSIS_HOOK_POSTUNINSTALL
  ${If} $DeleteAppDataCheckboxState = 1
  ${AndIf} $UpdateMode <> 1
    SetShellVarContext current
    RmDir /r "$PROFILE\.local\share\${BUNDLEID}"
    RmDir /r "$LOCALAPPDATA\${BUNDLEID}"
    RmDir /r "$APPDATA\${BUNDLEID}"
    ReadEnvStr $0 "XDG_DATA_HOME"
    ${If} $0 != ""
      RmDir /r "$0\${BUNDLEID}"
    ${EndIf}
  ${EndIf}
!macroend
