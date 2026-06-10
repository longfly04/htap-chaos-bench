package runtime

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadManifest(t *testing.T) {
	tempDir := t.TempDir()
	path := filepath.Join(tempDir, "manifest.env")
	content := "# comment\nRUN_ID=test-run\nSEED=7\nGO_PLATFORM_BIN=bin/htap-chaos-bench\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write manifest: %v", err)
	}

	manifest, err := LoadManifest(path)
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}
	if manifest.Get("RUN_ID") != "test-run" {
		t.Fatalf("unexpected RUN_ID: %q", manifest.Get("RUN_ID"))
	}
	if manifest.Int("SEED", 0) != 7 {
		t.Fatalf("unexpected SEED: %d", manifest.Int("SEED", 0))
	}
}
