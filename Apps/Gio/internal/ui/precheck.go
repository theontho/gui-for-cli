package ui

import (
	"math"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func (g *GioApp) evaluatePrecheck(spec *bundle.ActionPrecheck, context map[string]string) *precheckResult {
	if spec == nil || strings.TrimSpace(spec.DiskSpaceGB) == "" {
		return nil
	}
	requiredGB := evaluateNumeric(interpolate(spec.DiskSpaceGB, context))
	if math.IsNaN(requiredGB) || requiredGB <= 0 {
		return nil
	}
	pathExpression := spec.DiskSpacePath
	if strings.TrimSpace(pathExpression) == "" {
		pathExpression = "{{out_dir}}"
	}
	targetPath := strings.TrimSpace(interpolate(pathExpression, context))
	if targetPath == "" {
		targetPath = g.bundle.BundleWorkspaceRoot
	}
	availableGB, ok := volumeAvailableGB(expandUserPath(targetPath))
	if !ok {
		return nil
	}
	severity := "info"
	title := g.stringLabel("app.action.precheck.diskSpace.infoTitle", "Disk space estimate")
	format := g.stringLabel("app.action.precheck.diskSpace.infoFormat", "Estimated %{required} GB needed at %{path} (%{available} GB free).")
	if availableGB < requiredGB {
		severity = "warning"
		title = g.stringLabel("app.action.precheck.diskSpace.title", "Not enough free disk space")
		format = g.stringLabel("app.action.precheck.diskSpace.messageFormat", "Need %{required} GB free at %{path}, only %{available} GB available.")
		if spec.WarningMessage != "" {
			format = interpolate(spec.WarningMessage, context)
		}
	}
	message := strings.ReplaceAll(format, "%{required}", formatGB(requiredGB))
	message = strings.ReplaceAll(message, "%{available}", formatGB(availableGB))
	message = strings.ReplaceAll(message, "%{path}", filepathBaseOrPath(targetPath))
	return &precheckResult{severity: severity, title: title, message: title + ": " + message}
}

func volumeAvailableGB(path string) (float64, bool) {
	probe := path
	for strings.TrimSpace(probe) != "" {
		if _, err := os.Stat(probe); err == nil {
			break
		}
		parent := filepathDir(probe)
		if parent == probe {
			break
		}
		probe = parent
	}
	if runtime.GOOS == "windows" {
		return windowsVolumeAvailableGB(probe)
	}
	output, err := exec.Command("df", "-k", probe).Output()
	if err != nil {
		return 0, false
	}
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) < 2 {
		return 0, false
	}
	fields := strings.Fields(lines[len(lines)-1])
	if len(fields) < 4 {
		return 0, false
	}
	availableKB, err := strconv.ParseFloat(fields[3], 64)
	if err != nil {
		return 0, false
	}
	return availableKB * 1024 / 1_073_741_824, true
}

func windowsVolumeAvailableGB(path string) (float64, bool) {
	drive := filepathVolumeName(path)
	if drive == "" {
		return 0, false
	}
	command := exec.Command("powershell", "-NoProfile", "-Command", "(Get-PSDrive -Name "+strings.TrimRight(drive, ":")+" | Select-Object -ExpandProperty Free)")
	output, err := command.Output()
	if err != nil {
		return 0, false
	}
	bytes, err := strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
	if err != nil {
		return 0, false
	}
	return bytes / 1_073_741_824, true
}

func compareNumeric(left string, right string, op func(float64, float64) bool) bool {
	leftValue := evaluateNumeric(left)
	rightValue := evaluateNumeric(right)
	return !math.IsNaN(leftValue) && !math.IsNaN(rightValue) && op(leftValue, rightValue)
}

func evaluateNumeric(expression string) float64 {
	parser := numericParser{text: expression}
	return parser.parse()
}

type numericParser struct {
	text  string
	index int
}

func (p *numericParser) parse() float64 {
	value := p.expression()
	p.skipWhitespace()
	if p.index != len(p.text) {
		return math.NaN()
	}
	return value
}

func (p *numericParser) expression() float64 {
	value := p.term()
	for {
		p.skipWhitespace()
		switch {
		case p.consume('+'):
			value += p.term()
		case p.consume('-'):
			value -= p.term()
		default:
			return value
		}
	}
}

func (p *numericParser) term() float64 {
	value := p.factor()
	for {
		p.skipWhitespace()
		switch {
		case p.consume('*'):
			value *= p.factor()
		case p.consume('/'):
			value /= p.factor()
		default:
			return value
		}
	}
}

func (p *numericParser) factor() float64 {
	p.skipWhitespace()
	if p.consume('+') {
		return p.factor()
	}
	if p.consume('-') {
		return -p.factor()
	}
	if p.consume('(') {
		value := p.expression()
		if !p.consume(')') {
			return math.NaN()
		}
		return value
	}
	return p.number()
}

func (p *numericParser) number() float64 {
	p.skipWhitespace()
	start := p.index
	for p.index < len(p.text) && (p.text[p.index] == '.' || p.text[p.index] >= '0' && p.text[p.index] <= '9') {
		p.index++
	}
	if start == p.index {
		return math.NaN()
	}
	value, err := strconv.ParseFloat(p.text[start:p.index], 64)
	if err != nil {
		return math.NaN()
	}
	return value
}

func (p *numericParser) consume(token byte) bool {
	if p.index < len(p.text) && p.text[p.index] == token {
		p.index++
		return true
	}
	return false
}

func (p *numericParser) skipWhitespace() {
	for p.index < len(p.text) && (p.text[p.index] == ' ' || p.text[p.index] == '\t' || p.text[p.index] == '\n' || p.text[p.index] == '\r') {
		p.index++
	}
}

func formatGB(value float64) string {
	if value >= 100 {
		return strconv.FormatFloat(value, 'f', 0, 64)
	}
	if value >= 10 {
		return strconv.FormatFloat(value, 'f', 1, 64)
	}
	return strconv.FormatFloat(value, 'f', 2, 64)
}
