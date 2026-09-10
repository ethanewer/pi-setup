package app_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/urfave/cli/v3"

	"flume.dev/tool/internal/app"
	"flume.dev/tool/internal/engine"
)

// fixtureDir resolves the hidden fixture state directory copied into the
// repository by the verifier (repo root /testdata/hidden2).
func fixtureDir(t *testing.T) string {
	t.Helper()
	dir := filepath.Join("..", "..", "testdata", "hidden2")
	if _, err := os.Stat(dir); err != nil {
		t.Fatalf("fixture dir %s missing: %v", dir, err)
	}
	return dir
}

func newCmd(t *testing.T) (*cli.Command, *bytes.Buffer) {
	t.Helper()
	cmd := app.Build()
	cmd.ExitErrHandler = func(context.Context, *cli.Command, error) {}
	var out bytes.Buffer
	cmd.Writer = &out
	return cmd, &out
}

// The migrated CLI must read pre-existing run records and filter them through
// the new context-based API.
func TestHiddenV3ListFilterOnFixture(t *testing.T) {
	cmd, out := newCmd(t)
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", fixtureDir(t), "list", "--status", "running", "--json"}); err != nil {
		t.Fatalf("list: %v", err)
	}
	var runs []engine.Run
	if err := json.Unmarshal([]byte(out.String()), &runs); err != nil {
		t.Fatalf("list --json: %v\n%s", err, out.String())
	}
	if len(runs) != 1 {
		t.Fatalf("expected 1 running run, got %d: %+v", len(runs), runs)
	}
	run := runs[0]
	if run.ID != "run-1001" || run.Pipeline != "nightly" {
		t.Fatalf("unexpected run: %+v", run)
	}
	if run.Workers != 2 || run.Input != "s3://in/1.csv" || run.Output != "s3://out/1.json" {
		t.Fatalf("unexpected run: %+v", run)
	}
}

// Inspect on a fixture record must return the full record through the new API.
func TestHiddenV3InspectFixtureRecord(t *testing.T) {
	cmd, out := newCmd(t)
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", fixtureDir(t), "inspect", "run-1003", "--format", "json"}); err != nil {
		t.Fatalf("inspect: %v", err)
	}
	var run engine.Run
	if err := json.Unmarshal([]byte(out.String()), &run); err != nil {
		t.Fatalf("inspect json: %v\n%s", err, out.String())
	}
	if run.ID != "run-1003" || run.Pipeline != "weekly" || run.Status != engine.StatusFailed {
		t.Fatalf("unexpected run: %+v", run)
	}
	if run.Error != "timeout" || run.Workers != 1 {
		t.Fatalf("unexpected run: %+v", run)
	}
}

// Starting a pipeline that already has a running record in the fixture must
// fail without --force and succeed with it, stopping the old run.
func TestHiddenV3ForceAgainstFixture(t *testing.T) {
	dir := t.TempDir()
	// copy the fixture into a scratch dir so the test can mutate it
	entries, err := os.ReadDir(fixtureDir(t))
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(fixtureDir(t), e.Name()))
		if err != nil {
			t.Fatalf("ReadFile: %v", err)
		}
		if err := os.WriteFile(filepath.Join(dir, e.Name()), data, 0o644); err != nil {
			t.Fatalf("WriteFile: %v", err)
		}
	}

	cmd, out := newCmd(t)
	err = cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "start", "nightly", "--input", "n.csv", "--output", "m.json"})
	if err == nil {
		t.Fatal("start without --force succeeded, want error")
	}
	var ec cli.ExitCoder
	if !errors.As(err, &ec) {
		t.Fatalf("expected cli.ExitCoder, got %T: %v", err, err)
	}

	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "start", "nightly", "--input", "n.csv", "--output", "m.json", "--force"}); err != nil {
		t.Fatalf("forced start: %v", err)
	}
	if !strings.Contains(out.String(), "started run run-") {
		t.Fatalf("unexpected output %q", out.String())
	}
	// the old running record must now be stopped
	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "status", "run-1001"}); err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out.String(), "status=stopped") {
		t.Fatalf("old run not stopped: %q", out.String())
	}
}
