!macro NSIS_HOOK_POSTUNINSTALL
  ${If} $UpdateMode <> 1
    SetShellVarContext current

    Delete /REBOOTOK "$INSTDIR\uninstall.exe"
    RmDir /REBOOTOK "$INSTDIR"
    RmDir /REBOOTOK "$LOCALAPPDATA\${PRODUCTNAME}"
    RmDir /REBOOTOK "$LOCALAPPDATA\Programs\${PRODUCTNAME}"

    ${If} $DeleteAppDataCheckboxState = 1
      ; The WebUI backend keeps bundle workspaces and state in %LOCALAPPDATA%\<identifier>.
      RmDir /r "$LOCALAPPDATA\${BUNDLEID}"
    ${EndIf}
  ${EndIf}
!macroend
