package app_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/urfave/cli/v3"

	"flume.dev/tool/internal/app"
	"flume.dev/tool/internal/engine"
)

// The migrated application must expose the v3 command type and run through the
// context-based API.
func TestHiddenV3CommandShape(t *testing.T) {
	cmd := app.Build()
	if cmd == nil {
		t.Fatal("Build returned nil")
	}
	// Compile-time: Build must return the v3 *cli.Command, not the v1 *cli.App.
	var _ *cli.Command = cmd
	if cmd.Name != "flume" {
		t.Fatalf("Name = %q, want flume", cmd.Name)
	}
	if len(cmd.Commands) < 4 {
		t.Fatalf("expected at least 4 subcommands, got %d", len(cmd.Commands))
	}
	for _, sub := range cmd.Commands {
		if sub == nil {
			t.Fatal("nil subcommand in Commands")
		}
	}
	if len(cmd.Flags) == 0 {
		t.Fatal("expected global flags on the root command")
	}
}

// The v3 API runs a command with a context.Context and writes to cmd.Writer.
func TestHiddenV3RunWithContext(t *testing.T) {
	dir := t.TempDir()
	cmd := app.Build()
	cmd.ExitErrHandler = func(context.Context, *cli.Command, error) {}
	var out bytes.Buffer
	cmd.Writer = &out
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "start", "alpha", "--input", "a.csv", "--output", "b.json", "--workers", "5"}); err != nil {
		t.Fatalf("start: %v", err)
	}
	if !strings.Contains(out.String(), "started run run-") {
		t.Fatalf("unexpected output %q", out.String())
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one run record, got %v (%v)", entries, err)
	}
	id := strings.TrimSuffix(entries[0].Name(), ".json")

	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "status", id}); err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out.String(), "status=running") {
		t.Fatalf("unexpected status output %q", out.String())
	}

	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "stop", id}); err != nil {
		t.Fatalf("stop: %v", err)
	}
	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "status", id}); err != nil {
		t.Fatalf("status after stop: %v", err)
	}
	if !strings.Contains(out.String(), "status=stopped") {
		t.Fatalf("unexpected status output %q", out.String())
	}
}

// Error paths surface as cli.ExitCoder values with the encoded exit code.
func TestHiddenV3ExitError(t *testing.T) {
	cmd := app.Build()
	cmd.ExitErrHandler = func(context.Context, *cli.Command, error) {}
	var out bytes.Buffer
	cmd.Writer = &out
	err := cmd.Run(context.Background(), []string{"flume", "--state-dir", t.TempDir(), "start"})
	if err == nil {
		t.Fatal("expected an error for a missing pipeline name")
	}
	var ec cli.ExitCoder
	if !errors.As(err, &ec) {
		t.Fatalf("expected cli.ExitCoder, got %T: %v", err, err)
	}
	if ec.ExitCode() != 1 {
		t.Fatalf("exit code = %d, want 1", ec.ExitCode())
	}
}

// The v3 API exposes Args with Slice() and flag accessors on the command.
func TestHiddenV3InspectJSON(t *testing.T) {
	dir := t.TempDir()
	cmd := app.Build()
	cmd.ExitErrHandler = func(context.Context, *cli.Command, error) {}
	var out bytes.Buffer
	cmd.Writer = &out
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "start", "gamma", "--input", "x.csv", "--output", "y.json", "--workers", "7"}); err != nil {
		t.Fatalf("start: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one run record, got %v (%v)", entries, err)
	}
	id := strings.TrimSuffix(entries[0].Name(), ".json")
	out.Reset()
	if err := cmd.Run(context.Background(), []string{"flume", "--state-dir", dir, "inspect", id, "--format", "json"}); err != nil {
		t.Fatalf("inspect: %v", err)
	}
	var run engine.Run
	if err := json.Unmarshal([]byte(out.String()), &run); err != nil {
		t.Fatalf("inspect json: %v\n%s", err, out.String())
	}
	if run.Workers != 7 || run.Input != "x.csv" || run.Status != engine.StatusRunning {
		t.Fatalf("unexpected run: %+v", run)
	}
	if run.ID != id {
		t.Fatalf("id = %q, want %q", run.ID, id)
	}
}
