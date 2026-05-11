package ui

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"
)

type pathPickerSpec struct {
	ID          string
	Key         string
	Label       string
	Tooltip     string
	PathType    string
	PathKind    string
	PathMode    string
	ButtonID    string
	InitialPath string
	OnChoose    func(string)
}

func (g *GioApp) layoutPathEditor(gtx layout.Context, spec pathPickerSpec, editor *widget.Editor, hint string) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, spec.Label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutPathInputRow(gtx, spec, editor, hint)
		}),
	)
}

func (g *GioApp) layoutPathInputRow(gtx layout.Context, spec pathPickerSpec, editor *widget.Editor, hint string) layout.Dimensions {
	button := g.pathPickerButtonFor(spec.ButtonID)
	for button.Clicked(gtx) {
		spec.InitialPath = editor.Text()
		path, err := pickPath(spec, g.bundle.BundleRoot)
		if err != nil {
			if errors.Is(err, errPathPickerCancelled) {
				continue
			}
			g.appendLog(fmt.Sprintf("Choose path failed: %v", err))
			continue
		}
		editor.SetText(path)
		if spec.OnChoose != nil {
			spec.OnChoose(path)
		}
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(
		gtx,
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return material.Editor(g.theme, editor, hint).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, button, g.stringLabel("app.pathPicker.chooseButton.title", "Choose...")).Layout(gtx)
		}),
	)
}

var errPathPickerCancelled = errors.New("path picker cancelled")

func pickPath(spec pathPickerSpec, bundleRoot string) (string, error) {
	kind := pathPickerKind(spec)
	title := pathPickerTitle(spec, kind)
	defaultLocation := defaultLocationForPath(spec.InitialPath, bundleRoot)
	switch runtime.GOOS {
	case "darwin":
		return pickPathMacOS(kind, title, defaultLocation)
	case "windows":
		return pickPathWindows(kind, title, defaultLocation)
	default:
		return pickPathUnix(kind, title, defaultLocation)
	}
}

func pathPickerTitle(spec pathPickerSpec, kind string) string {
	if strings.TrimSpace(spec.Label) != "" {
		return "Choose " + spec.Label
	}
	if kind == "directory" {
		return "Choose directory"
	}
	return "Choose file"
}

func pathPickerKind(spec pathPickerSpec) string {
	for _, explicit := range []string{spec.PathType, spec.PathKind, spec.PathMode} {
		switch strings.ToLower(strings.TrimSpace(explicit)) {
		case "directory", "folder":
			return "directory"
		case "file":
			return "file"
		}
	}
	searchable := strings.ToLower(strings.Join([]string{spec.ID, spec.Key, spec.Label, spec.Tooltip}, " "))
	if strings.ToLower(spec.ID) == "ref_path" || strings.ToLower(spec.Key) == "reference_library" {
		return "directory"
	}
	if pathPickerDirectoryToken(searchable, "out", "dir") ||
		pathPickerDirectoryToken(searchable, "out", "directory") ||
		containsPathPickerWord(searchable, "dir") ||
		containsPathPickerWord(searchable, "directory") ||
		containsPathPickerWord(searchable, "folder") ||
		containsPathPickerWord(searchable, "library") ||
		containsPathPickerWord(searchable, "cache") {
		return "directory"
	}
	return "file"
}

func pathPickerDirectoryToken(value string, first string, second string) bool {
	normalized := normalizePathPickerWords(value)
	return strings.Contains(normalized, " "+first+" "+second+" ")
}

func containsPathPickerWord(value string, word string) bool {
	return strings.Contains(normalizePathPickerWords(value), " "+word+" ")
}

func normalizePathPickerWords(value string) string {
	var builder strings.Builder
	builder.WriteByte(' ')
	for _, r := range strings.ToLower(value) {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			builder.WriteRune(r)
		} else {
			builder.WriteByte(' ')
		}
	}
	builder.WriteByte(' ')
	return builder.String()
}

func defaultLocationForPath(rawPath string, bundleRoot string) string {
	candidate := normalizeDefaultPath(rawPath, bundleRoot)
	if candidate == "" {
		return existingDirectory(bundleRoot)
	}
	if directory := existingDirectory(candidate); directory != "" {
		return directory
	}
	if parent := existingParentDirectory(candidate); parent != "" {
		return parent
	}
	return existingDirectory(bundleRoot)
}

func normalizeDefaultPath(rawPath string, bundleRoot string) string {
	value := strings.TrimSpace(rawPath)
	if value == "" {
		return ""
	}
	if value == "~" {
		return userHomeDir()
	}
	if strings.HasPrefix(value, "~/") {
		return filepath.Join(userHomeDir(), strings.TrimPrefix(value, "~/"))
	}
	if filepath.IsAbs(value) {
		return filepath.Clean(value)
	}
	if strings.TrimSpace(bundleRoot) == "" {
		if wd, err := os.Getwd(); err == nil {
			bundleRoot = wd
		}
	}
	return filepath.Clean(filepath.Join(bundleRoot, value))
}

func existingParentDirectory(candidate string) string {
	current := filepath.Dir(candidate)
	for strings.TrimSpace(current) != "" {
		if directory := existingDirectory(current); directory != "" {
			return directory
		}
		parent := filepath.Dir(current)
		if parent == current {
			return existingDirectory(current)
		}
		current = parent
	}
	return ""
}

func existingDirectory(candidate string) string {
	if strings.TrimSpace(candidate) == "" {
		return ""
	}
	info, err := os.Stat(candidate)
	if err != nil {
		return ""
	}
	if info.IsDir() {
		return candidate
	}
	return filepath.Dir(candidate)
}

func pickPathMacOS(kind string, title string, defaultLocation string) (string, error) {
	const script = `
on run argv
  set pickerKind to item 1 of argv
  set dialogTitle to item 2 of argv
  set defaultPath to item 3 of argv
  activate
  if defaultPath is not "" then
    set defaultLocation to POSIX file defaultPath as alias
    if pickerKind is "directory" then
      set chosenItem to choose folder with prompt dialogTitle default location defaultLocation
    else
      set chosenItem to choose file with prompt dialogTitle default location defaultLocation
    end if
  else
    if pickerKind is "directory" then
      set chosenItem to choose folder with prompt dialogTitle
    else
      set chosenItem to choose file with prompt dialogTitle
    end if
  end if
  return POSIX path of chosenItem
end run
`
	output, err := exec.Command("/usr/bin/osascript", "-e", script, kind, title, defaultLocation).CombinedOutput()
	if err != nil {
		text := strings.TrimSpace(string(output))
		if strings.Contains(strings.ToLower(text), "user canceled") || strings.Contains(strings.ToLower(text), "user cancelled") {
			return "", errPathPickerCancelled
		}
		return "", fmt.Errorf("%s", strings.TrimSpace(string(output)))
	}
	return strings.TrimSpace(string(output)), nil
}

func pickPathWindows(kind string, title string, defaultLocation string) (string, error) {
	script := windowsPickerScript(kind)
	output, err := exec.Command("powershell", "-NoProfile", "-STA", "-Command", script, title, defaultLocation).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s", strings.TrimSpace(string(output)))
	}
	path := strings.TrimSpace(string(output))
	if path == "" {
		return "", errPathPickerCancelled
	}
	return path, nil
}

func windowsPickerScript(kind string) string {
	if kind == "directory" {
		return `Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = $args[0]; if ($args[1]) { $d.SelectedPath = $args[1] }; if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $d.SelectedPath }`
	}
	return `Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Title = $args[0]; if ($args[1]) { $d.InitialDirectory = $args[1] }; if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $d.FileName }`
}

func pickPathUnix(kind string, title string, defaultLocation string) (string, error) {
	if path, err := pickPathWithZenity(kind, title, defaultLocation); err == nil || !errors.Is(err, exec.ErrNotFound) {
		return path, err
	}
	return "", fmt.Errorf("native file and directory picking is not available on this platform without zenity")
}

func pickPathWithZenity(kind string, title string, defaultLocation string) (string, error) {
	args := []string{"--file-selection", "--title", title}
	if kind == "directory" {
		args = append(args, "--directory")
	}
	if defaultLocation != "" {
		args = append(args, "--filename", defaultLocation+string(filepath.Separator))
	}
	output, err := exec.Command("zenity", args...).CombinedOutput()
	if err != nil {
		var execErr *exec.Error
		if errors.As(err, &execErr) && execErr.Err == exec.ErrNotFound {
			return "", exec.ErrNotFound
		}
		if len(output) == 0 {
			return "", errPathPickerCancelled
		}
		return "", fmt.Errorf("%s", strings.TrimSpace(string(output)))
	}
	return strings.TrimSpace(string(output)), nil
}
