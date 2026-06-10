package runtime

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Manifest struct {
	Values map[string]string
}

func LoadManifest(path string) (Manifest, error) {
	file, err := os.Open(path)
	if err != nil {
		return Manifest{}, err
	}
	defer file.Close()

	values := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.IndexRune(line, '=')
		if idx <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		value := strings.TrimSpace(line[idx+1:])
		value = strings.Trim(value, "\"'")
		values[key] = value
	}
	if err := scanner.Err(); err != nil {
		return Manifest{}, err
	}
	return Manifest{Values: values}, nil
}

func (m Manifest) Get(key string) string {
	if value, ok := m.Values[key]; ok {
		return value
	}
	return ""
}

func (m Manifest) Require(key string) (string, error) {
	value := m.Get(key)
	if value == "" {
		return "", fmt.Errorf("missing manifest key: %s", key)
	}
	return value, nil
}

func (m Manifest) Int(key string, fallback int) int {
	value := m.Get(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
