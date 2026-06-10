package tpgen

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

type Template struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Path string `json:"path"`
}

func LoadSeedTemplates(seedDir string) ([]Template, error) {
	entries, err := os.ReadDir(seedDir)
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		if filepath.Ext(entry.Name()) != ".sql" {
			continue
		}
		paths = append(paths, filepath.Join(seedDir, entry.Name()))
	}
	sort.Strings(paths)
	if len(paths) == 0 {
		return nil, fmt.Errorf("no seed templates found in %s", seedDir)
	}
	templates := make([]Template, 0, len(paths))
	for index, path := range paths {
		templates = append(templates, Template{
			ID:   fmt.Sprintf("seed-%03d", index+1),
			Name: filepath.Base(path),
			Path: path,
		})
	}
	return templates, nil
}
