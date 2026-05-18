package bundle

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func readOptionalStringTable(path string) (map[string]string, error) {
	if _, err := os.Stat(path); err != nil {
		if os.IsNotExist(err) {
			return map[string]string{}, nil
		}
		return nil, err
	}
	return readStringTable(path)
}

func readStringTable(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	table := map[string]string{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		index := strings.Index(line, "=")
		if index < 0 {
			return nil, fmt.Errorf("%s:%d: expected key=value", path, lineNumber)
		}

		key, err := parseQuotedTomlString(strings.TrimSpace(line[:index]))
		if err != nil {
			return nil, fmt.Errorf("%s:%d: %w", path, lineNumber, err)
		}

		valuePart := strings.TrimSpace(line[index+1:])
		commentIndex := strings.Index(valuePart, " #")
		if commentIndex >= 0 {
			valuePart = strings.TrimSpace(valuePart[:commentIndex])
		}

		value, err := parseTomlValue(valuePart)
		if err != nil {
			return nil, fmt.Errorf("%s:%d: %w", path, lineNumber, err)
		}
		table[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return table, nil
}

func parseTomlValue(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "true" || trimmed == "false" {
		return trimmed, nil
	}
	return parseQuotedTomlString(trimmed)
}

func parseQuotedTomlString(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", nil
	}
	unquoted, err := strconv.Unquote(trimmed)
	if err != nil {
		return "", fmt.Errorf("invalid quoted string %q: %w", trimmed, err)
	}
	return unquoted, nil
}
