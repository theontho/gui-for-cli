package ui

import "strings"

func (g *GioApp) appendLog(line string) {
	g.appendTerminalLine("main", line)
}

func (g *GioApp) stringLabel(key string, fallback string) string {
	if g != nil && g.bundle != nil {
		if value := g.bundle.Strings[key]; value != "" {
			return value
		}
	}
	if key != "" {
		return key
	}
	return fallback
}

func (g *GioApp) stringFormat(key string, fallback string, values map[string]string) string {
	value := g.stringLabel(key, fallback)
	for placeholder, replacement := range values {
		value = strings.ReplaceAll(value, "%{"+placeholder+"}", replacement)
	}
	return value
}

func (g *GioApp) readyStatus() string {
	return g.stringLabel("app.status.ready", "Ready")
}

func (g *GioApp) processErrorTitle() string {
	return g.stringLabel("app.terminal.processError.title", "Command failed")
}

func (g *GioApp) setupStepStatusLabel(status string) string {
	switch status {
	case "running":
		return g.stringLabel("app.setup.step.running", "Running")
	case "ok":
		return g.stringLabel("app.setup.step.ok", "OK")
	case "warning":
		return g.stringLabel("app.setup.step.warning", "Warning")
	case "failed":
		return g.stringLabel("app.setup.step.failed", "Failed")
	default:
		return g.stringLabel("app.setup.step.pending", "Pending")
	}
}

func stringIn(value string, values []string) bool {
	for _, candidate := range values {
		if value == candidate {
			return true
		}
	}
	return false
}

func cloneMap(values map[string]string) map[string]string {
	if values == nil {
		return nil
	}
	clone := map[string]string{}
	for key, value := range values {
		clone[key] = value
	}
	return clone
}

func filepathBaseOrPath(path string) string {
	base := filepathBase(path)
	if base == "" {
		return path
	}
	return base
}

func filepathDir(path string) string {
	index := strings.LastIndexAny(path, `/\`)
	if index <= 0 {
		return path
	}
	return path[:index]
}

func filepathBase(path string) string {
	index := strings.LastIndexAny(path, `/\`)
	if index < 0 || index == len(path)-1 {
		return path
	}
	return path[index+1:]
}

func filepathVolumeName(path string) string {
	if len(path) >= 2 && path[1] == ':' {
		return path[:2]
	}
	return ""
}
