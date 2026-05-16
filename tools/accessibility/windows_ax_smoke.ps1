param(
    [switch]$StaticOnly,
    [string]$ProcessName = "GUIForCLIWindows"
)

$ErrorActionPreference = "Stop"

function Test-StaticAutomationLabels {
    $sourceRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
    $windowsRoot = Join-Path $sourceRoot "exp-platform\windows\dotnet\GUIForCLIWindows"
    $files = Get-ChildItem $windowsRoot -Recurse -Include *.xaml,*.cs -File |
        Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
    $interactiveLines = foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in Get-Content $file.FullName) {
            $lineNumber += 1
            if ($line -match '\b(Button|TextBox|ComboBox|ToggleSwitch|CheckBox|ListView)\b') {
                [pscustomobject]@{
                    Path = Resolve-Path -Relative $file.FullName
                    Line = $lineNumber
                    Text = $line.Trim()
                }
            }
        }
    }

    $automationNameCount = ($files | ForEach-Object { Select-String -Path $_.FullName -Pattern 'AutomationProperties\.SetName|AutomationProperties.Name' }).Count
    $automationIdCount = ($files | ForEach-Object { Select-String -Path $_.FullName -Pattern 'AutomationProperties\.SetAutomationId|AutomationProperties.AutomationId' }).Count

    [pscustomobject]@{
        InteractiveDeclarationCount = @($interactiveLines).Count
        AutomationNameCount = $automationNameCount
        AutomationIdCount = $automationIdCount
    }

    if ($automationNameCount -eq 0 -or $automationIdCount -eq 0) {
        throw "Windows UI does not contain AutomationProperties names and IDs."
    }
}

function Test-RunningAppAutomationLabels {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    $process = Get-Process -Name $ProcessName -ErrorAction Stop | Select-Object -First 1
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $process.Id
    )
    $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    if ($null -eq $window) {
        throw "Could not find a UI Automation root window for process $($process.Id)."
    }

    $controlCondition = [System.Windows.Automation.Condition]::TrueCondition
    $nodes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $controlCondition)
    $missingNames = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $nodes.Count; $index += 1) {
        $node = $nodes.Item($index)
        $controlType = $node.Current.ControlType.ProgrammaticName
        if ($controlType -match 'Button|Edit|ComboBox|CheckBox|List|MenuItem|TabItem' -and [string]::IsNullOrWhiteSpace($node.Current.Name)) {
            $missingNames.Add("$controlType automationId=$($node.Current.AutomationId)")
        }
    }

    [pscustomobject]@{
        ProcessId = $process.Id
        NodeCount = $nodes.Count
        MissingInteractiveNames = $missingNames.Count
    }

    if ($missingNames.Count -gt 0) {
        $missingNames | ForEach-Object { Write-Error $_ }
        throw "Running Windows app has unlabeled interactive controls."
    }
}

Test-StaticAutomationLabels
if (-not $StaticOnly) {
    Test-RunningAppAutomationLabels
}
