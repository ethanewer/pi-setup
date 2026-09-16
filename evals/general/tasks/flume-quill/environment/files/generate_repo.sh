#!/usr/bin/env bash
# Generates the flume fixture repository at /app/flume with a real git history,
# pins the CLI framework to an obsolete major (urfave/cli v1), proves the suite
# is green, and pre-populates the Go module cache with the v3 target graph so
# the dependency upgrade can be performed offline at trial time.
#
# This script is the reproducible source of the fixture: the repository it
# writes is the exact state the agent starts from.
set -euo pipefail

REPO=/app/flume
export GOPROXY=https://proxy.golang.org
export GOFLAGS=-mod=mod
export GOSUMDB=off

rm -rf "$REPO"
mkdir -p "$REPO/cmd/flume" "$REPO/internal/app" "$REPO/internal/engine" "$REPO/internal/state" "$REPO/docs"

write_file() { # path
  local path="$1"
  mkdir -p "$REPO/$(dirname "$path")"
  cat > "$REPO/$path"
}

write_file go.mod <<'FLUME_EOF'
module flume.dev/tool

go 1.22

require github.com/urfave/cli v1.22.14
FLUME_EOF

write_file internal/state/store.go <<'FLUME_EOF'
// Package state persists pipeline run records as JSON files in a directory.
package state

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ErrNotFound is returned when a run record does not exist in the store.
var ErrNotFound = errors.New("run not found")

// Store persists run records as JSON files in a directory.
type Store struct {
	Dir string
}

// New returns a Store rooted at dir, creating the directory if needed.
func New(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Store{Dir: dir}, nil
}

// Write serializes v to <id>.json in the store directory.
func (s *Store) Write(id string, v any) error {
	if id == "" || strings.Contains(id, "/") || strings.Contains(id, "..") {
		return fmt.Errorf("invalid run id %q", id)
	}
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(s.Dir, id+".json"), data, 0o644)
}

// Read deserializes <id>.json into v.
func (s *Store) Read(id string, v any) error {
	data, err := os.ReadFile(filepath.Join(s.Dir, id+".json"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ErrNotFound
		}
		return err
	}
	return json.Unmarshal(data, v)
}

// List returns the run ids present in the store, sorted lexically.
func (s *Store) List() ([]string, error) {
	entries, err := os.ReadDir(s.Dir)
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		ids = append(ids, strings.TrimSuffix(e.Name(), ".json"))
	}
	sort.Strings(ids)
	return ids, nil
}

// Exists reports whether a run record with the given id is present.
func (s *Store) Exists(id string) bool {
	_, err := os.Stat(filepath.Join(s.Dir, id+".json"))
	return err == nil
}
FLUME_EOF

write_file internal/state/store_test.go <<'FLUME_EOF'
package state

import (
	"errors"
	"testing"
)

func TestWriteReadRoundTrip(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	type rec struct {
		ID   string `json:"id"`
		Kind string `json:"kind"`
	}
	want := rec{ID: "run-1", Kind: "demo"}
	if err := s.Write("run-1", want); err != nil {
		t.Fatalf("Write: %v", err)
	}
	var got rec
	if err := s.Read("run-1", &got); err != nil {
		t.Fatalf("Read: %v", err)
	}
	if got != want {
		t.Fatalf("round trip = %+v, want %+v", got, want)
	}
}

func TestListSorted(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	for _, id := range []string{"run-b", "run-a", "run-c"} {
		if err := s.Write(id, map[string]any{"id": id}); err != nil {
			t.Fatalf("Write %s: %v", id, err)
		}
	}
	ids, err := s.List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	want := []string{"run-a", "run-b", "run-c"}
	if len(ids) != len(want) {
		t.Fatalf("List = %v, want %v", ids, want)
	}
	for i := range want {
		if ids[i] != want[i] {
			t.Fatalf("List = %v, want %v", ids, want)
		}
	}
}

func TestReadMissingReturnsErrNotFound(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	var v map[string]any
	if err := s.Read("nope", &v); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Read missing = %v, want ErrNotFound", err)
	}
}

func TestWriteRejectsPathTraversal(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if err := s.Write("../escape", map[string]any{}); err == nil {
		t.Fatal("Write with ../ id succeeded, want error")
	}
	if err := s.Write("a/b", map[string]any{}); err == nil {
		t.Fatal("Write with slash id succeeded, want error")
	}
}

func TestExists(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if err := s.Write("run-1", map[string]any{"id": "run-1"}); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if !s.Exists("run-1") {
		t.Fatal("Exists(run-1) = false, want true")
	}
	if s.Exists("run-2") {
		t.Fatal("Exists(run-2) = true, want false")
	}
}
FLUME_EOF

write_file internal/engine/engine.go <<'FLUME_EOF'
// Package engine implements the pipeline run state machine.
package engine

import (
	"fmt"
	"time"

	"flume.dev/tool/internal/state"
)

// Status is the lifecycle state of a pipeline run.
type Status string

const (
	StatusPending Status = "pending"
	StatusRunning Status = "running"
	StatusDone    Status = "done"
	StatusFailed  Status = "failed"
	StatusStopped Status = "stopped"
)

// Run is a single pipeline execution record.
type Run struct {
	ID         string    `json:"id"`
	Pipeline   string    `json:"pipeline"`
	Status     Status    `json:"status"`
	Input      string    `json:"input"`
	Output     string    `json:"output"`
	Workers    int       `json:"workers"`
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at,omitempty"`
	Error      string    `json:"error,omitempty"`
}

// Manager coordinates pipeline runs backed by a state store.
type Manager struct {
	store *state.Store
	now   func() time.Time
}

// NewManager returns a Manager persisting runs in store.
func NewManager(store *state.Store) *Manager {
	return &Manager{store: store, now: time.Now}
}

// Start begins a run of pipeline. If a run for the same pipeline is already
// running, it fails unless force is true, in which case the previous run is
// marked stopped first.
func (m *Manager) Start(pipeline, input, output string, workers int, force bool) (*Run, error) {
	if pipeline == "" {
		return nil, fmt.Errorf("pipeline name required")
	}
	if workers < 1 {
		workers = 1
	}
	existing, err := m.findRunning(pipeline)
	if err != nil {
		return nil, err
	}
	if existing != nil && !force {
		return nil, fmt.Errorf("pipeline %q already running as %s", pipeline, existing.ID)
	}
	if existing != nil {
		if err := m.Stop(existing.ID); err != nil {
			return nil, err
		}
	}
	now := m.now()
	run := &Run{
		ID:        fmt.Sprintf("run-%d", now.UnixNano()),
		Pipeline:  pipeline,
		Status:    StatusRunning,
		Input:     input,
		Output:    output,
		Workers:   workers,
		StartedAt: now,
	}
	if err := m.store.Write(run.ID, run); err != nil {
		return nil, err
	}
	return run, nil
}

// Stop marks a run stopped. Runs that already finished cannot be stopped.
func (m *Manager) Stop(id string) error {
	run, err := m.get(id)
	if err != nil {
		return err
	}
	if run.Status == StatusDone || run.Status == StatusFailed {
		return fmt.Errorf("run %s already finished (%s)", id, run.Status)
	}
	run.Status = StatusStopped
	run.FinishedAt = m.now()
	return m.store.Write(id, run)
}

// Status returns the current run record for id.
func (m *Manager) Status(id string) (*Run, error) {
	return m.get(id)
}

// List returns all runs, optionally filtered by status ("" means all).
func (m *Manager) List(status string) ([]*Run, error) {
	ids, err := m.store.List()
	if err != nil {
		return nil, err
	}
	var runs []*Run
	for _, id := range ids {
		run, err := m.get(id)
		if err != nil {
			return nil, err
		}
		if status == "" || string(run.Status) == status {
			runs = append(runs, run)
		}
	}
	return runs, nil
}

// Inspect returns the full run record for id.
func (m *Manager) Inspect(id string) (*Run, error) {
	return m.get(id)
}

func (m *Manager) get(id string) (*Run, error) {
	var run Run
	if err := m.store.Read(id, &run); err != nil {
		return nil, err
	}
	return &run, nil
}

func (m *Manager) findRunning(pipeline string) (*Run, error) {
	runs, err := m.List("")
	if err != nil {
		return nil, err
	}
	for _, r := range runs {
		if r.Pipeline == pipeline && r.Status == StatusRunning {
			return r, nil
		}
	}
	return nil, nil
}
FLUME_EOF

write_file internal/engine/engine_test.go <<'FLUME_EOF'
package engine

import (
	"errors"
	"testing"
	"time"

	"flume.dev/tool/internal/state"
)

func newTestManager(t *testing.T) *Manager {
	t.Helper()
	store, err := state.New(t.TempDir())
	if err != nil {
		t.Fatalf("state.New: %v", err)
	}
	m := NewManager(store)
	// A mock clock that advances by one second per call so distinct runs get
	// distinct ids.
	base := time.Unix(1700000000, 0)
	step := 0
	m.now = func() time.Time {
		step++
		return base.Add(time.Duration(step) * time.Second)
	}
	return m
}

func TestStartCreatesRunningRun(t *testing.T) {
	m := newTestManager(t)
	run, err := m.Start("demo", "in.csv", "out.json", 3, false)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	if run.Status != StatusRunning {
		t.Fatalf("status = %s, want running", run.Status)
	}
	if run.Pipeline != "demo" || run.Input != "in.csv" || run.Output != "out.json" || run.Workers != 3 {
		t.Fatalf("unexpected run: %+v", run)
	}
	if run.ID == "" {
		t.Fatal("empty run id")
	}
	got, err := m.Status(run.ID)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if got.ID != run.ID {
		t.Fatalf("Status returned %+v", got)
	}
}

func TestStartRequiresPipelineName(t *testing.T) {
	m := newTestManager(t)
	if _, err := m.Start("", "in.csv", "out.json", 1, false); err == nil {
		t.Fatal("Start with empty pipeline succeeded, want error")
	}
}

func TestStartClampsWorkers(t *testing.T) {
	m := newTestManager(t)
	run, err := m.Start("demo", "in.csv", "out.json", 0, false)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	if run.Workers != 1 {
		t.Fatalf("workers = %d, want 1", run.Workers)
	}
}

func TestStartRejectsDuplicateWithoutForce(t *testing.T) {
	m := newTestManager(t)
	if _, err := m.Start("demo", "a", "b", 1, false); err != nil {
		t.Fatalf("first Start: %v", err)
	}
	if _, err := m.Start("demo", "c", "d", 1, false); err == nil {
		t.Fatal("second Start without force succeeded, want error")
	}
}

func TestStartForceStopsPrevious(t *testing.T) {
	m := newTestManager(t)
	first, err := m.Start("demo", "a", "b", 1, false)
	if err != nil {
		t.Fatalf("first Start: %v", err)
	}
	second, err := m.Start("demo", "c", "d", 1, true)
	if err != nil {
		t.Fatalf("forced Start: %v", err)
	}
	if second.ID == first.ID {
		t.Fatalf("forced Start reused id %s", first.ID)
	}
	old, err := m.Status(first.ID)
	if err != nil {
		t.Fatalf("Status(old): %v", err)
	}
	if old.Status != StatusStopped {
		t.Fatalf("old run status = %s, want stopped", old.Status)
	}
}

func TestStopAndStatus(t *testing.T) {
	m := newTestManager(t)
	run, err := m.Start("demo", "a", "b", 1, false)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	if err := m.Stop(run.ID); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	got, err := m.Status(run.ID)
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if got.Status != StatusStopped {
		t.Fatalf("status = %s, want stopped", got.Status)
	}
	if got.FinishedAt.IsZero() {
		t.Fatal("FinishedAt not set after Stop")
	}
}

func TestStopMissingRun(t *testing.T) {
	m := newTestManager(t)
	if err := m.Stop("run-nope"); !errors.Is(err, state.ErrNotFound) {
		t.Fatalf("Stop missing = %v, want ErrNotFound", err)
	}
}

func TestListFilter(t *testing.T) {
	m := newTestManager(t)
	a, err := m.Start("alpha", "a", "b", 1, false)
	if err != nil {
		t.Fatalf("Start alpha: %v", err)
	}
	b, err := m.Start("beta", "c", "d", 1, false)
	if err != nil {
		t.Fatalf("Start beta: %v", err)
	}
	if err := m.Stop(a.ID); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	all, err := m.List("")
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("List all = %d runs, want 2", len(all))
	}
	running, err := m.List(string(StatusRunning))
	if err != nil {
		t.Fatalf("List running: %v", err)
	}
	if len(running) != 1 || running[0].ID != b.ID {
		t.Fatalf("List running = %+v, want only %s", running, b.ID)
	}
}

func TestInspect(t *testing.T) {
	m := newTestManager(t)
	run, err := m.Start("demo", "in.csv", "out.json", 2, false)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	got, err := m.Inspect(run.ID)
	if err != nil {
		t.Fatalf("Inspect: %v", err)
	}
	if got.Workers != 2 || got.Input != "in.csv" {
		t.Fatalf("Inspect = %+v", got)
	}
}
FLUME_EOF

write_file internal/app/app.go <<'FLUME_EOF'
// Package app wires the flume engine to the urfave/cli command-line framework.
package app

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/urfave/cli"

	"flume.dev/tool/internal/engine"
	"flume.dev/tool/internal/state"
)

// Build assembles the flume command-line application.
func Build() *cli.App {
	app := cli.NewApp()
	app.Name = "flume"
	app.Usage = "manage data pipeline runs"
	app.Version = "1.4.2"
	app.Flags = []cli.Flag{
		cli.StringFlag{Name: "state-dir", Value: defaultStateDir(), Usage: "directory holding run records"},
	}
	app.Commands = []cli.Command{
		{
			Name:  "start",
			Usage: "start a pipeline run",
			Flags: []cli.Flag{
				cli.StringFlag{Name: "input", Usage: "input path"},
				cli.StringFlag{Name: "output", Usage: "output path"},
				cli.IntFlag{Name: "workers", Value: 1, Usage: "number of workers"},
				cli.BoolFlag{Name: "force", Usage: "stop an existing run of the same pipeline"},
			},
			Action: func(c *cli.Context) error {
				m, err := manager(c)
				if err != nil {
					return err
				}
				run, err := m.Start(c.Args().First(), c.String("input"), c.String("output"), c.Int("workers"), c.Bool("force"))
				if err != nil {
					return cli.NewExitError(err.Error(), 1)
				}
				fmt.Fprintf(c.App.Writer, "started run %s (pipeline %s)\n", run.ID, run.Pipeline)
				return nil
			},
		},
		{
			Name:  "stop",
			Usage: "stop a running pipeline run",
			Action: func(c *cli.Context) error {
				m, err := manager(c)
				if err != nil {
					return err
				}
				id := c.Args().First()
				if id == "" {
					return cli.NewExitError("run id required", 2)
				}
				if err := m.Stop(id); err != nil {
					return cli.NewExitError(err.Error(), 1)
				}
				fmt.Fprintf(c.App.Writer, "stopped run %s\n", id)
				return nil
			},
		},
		{
			Name:  "status",
			Usage: "show the status of a pipeline run",
			Action: func(c *cli.Context) error {
				m, err := manager(c)
				if err != nil {
					return err
				}
				id := c.Args().First()
				if id == "" {
					return cli.NewExitError("run id required", 2)
				}
				run, err := m.Status(id)
				if err != nil {
					return cli.NewExitError(err.Error(), 1)
				}
				fmt.Fprintf(c.App.Writer, "run %s status=%s\n", run.ID, run.Status)
				return nil
			},
		},
		{
			Name:  "list",
			Usage: "list pipeline runs",
			Flags: []cli.Flag{
				cli.StringFlag{Name: "status", Usage: "filter by status"},
				cli.BoolFlag{Name: "json", Usage: "emit JSON"},
			},
			Action: func(c *cli.Context) error {
				m, err := manager(c)
				if err != nil {
					return err
				}
				runs, err := m.List(c.String("status"))
				if err != nil {
					return cli.NewExitError(err.Error(), 1)
				}
				if c.Bool("json") {
					return writeJSON(c.App.Writer, runs)
				}
				for _, r := range runs {
					fmt.Fprintf(c.App.Writer, "run %s %s %s\n", r.ID, r.Pipeline, r.Status)
				}
				return nil
			},
		},
		{
			Name:  "inspect",
			Usage: "show full details of a pipeline run",
			Flags: []cli.Flag{
				cli.StringFlag{Name: "format", Value: "text", Usage: "output format: text or json"},
			},
			Action: func(c *cli.Context) error {
				m, err := manager(c)
				if err != nil {
					return err
				}
				id := c.Args().First()
				if id == "" {
					return cli.NewExitError("run id required", 2)
				}
				run, err := m.Inspect(id)
				if err != nil {
					return cli.NewExitError(err.Error(), 1)
				}
				if c.String("format") == "json" {
					return writeJSON(c.App.Writer, run)
				}
				fmt.Fprintf(c.App.Writer, "run %s\n", run.ID)
				fmt.Fprintf(c.App.Writer, "  pipeline: %s\n", run.Pipeline)
				fmt.Fprintf(c.App.Writer, "  status:   %s\n", run.Status)
				fmt.Fprintf(c.App.Writer, "  input:    %s\n", run.Input)
				fmt.Fprintf(c.App.Writer, "  output:   %s\n", run.Output)
				fmt.Fprintf(c.App.Writer, "  workers:  %d\n", run.Workers)
				return nil
			},
		},
	}
	return app
}

// Execute runs the application with the given arguments.
func Execute(args []string) error {
	return Build().Run(args)
}

func manager(c *cli.Context) (*engine.Manager, error) {
	store, err := state.New(c.GlobalString("state-dir"))
	if err != nil {
		return nil, err
	}
	return engine.NewManager(store), nil
}

func writeJSON(w io.Writer, v any) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

func defaultStateDir() string {
	if dir := os.Getenv("FLUME_STATE_DIR"); dir != "" {
		return dir
	}
	return "/tmp/flume-state"
}
FLUME_EOF

write_file internal/app/app_test.go <<'FLUME_EOF'
package app

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/urfave/cli"

	"flume.dev/tool/internal/engine"
)

func runApp(t *testing.T, args ...string) (string, error) {
	t.Helper()
	app := Build()
	// Keep error paths from calling os.Exit inside the test process.
	app.ExitErrHandler = func(c *cli.Context, err error) {}
	var out bytes.Buffer
	app.Writer = &out
	err := app.Run(args)
	return out.String(), err
}

func readRunRecord(t *testing.T, dir string) engine.Run {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected one run record, got %d", len(entries))
	}
	data, err := os.ReadFile(filepath.Join(dir, entries[0].Name()))
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var run engine.Run
	if err := json.Unmarshal(data, &run); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	return run
}

func TestStartCommand(t *testing.T) {
	dir := t.TempDir()
	out, err := runApp(t, "flume", "--state-dir", dir, "start", "demo", "--input", "in.csv", "--output", "out.json", "--workers", "3")
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	if !strings.Contains(out, "started run run-") {
		t.Fatalf("unexpected output %q", out)
	}
	run := readRunRecord(t, dir)
	if run.Pipeline != "demo" || run.Workers != 3 || run.Status != engine.StatusRunning {
		t.Fatalf("unexpected run record: %+v", run)
	}
	if run.Input != "in.csv" || run.Output != "out.json" {
		t.Fatalf("unexpected run record: %+v", run)
	}
}

func TestStartRequiresPipelineName(t *testing.T) {
	dir := t.TempDir()
	_, err := runApp(t, "flume", "--state-dir", dir, "start")
	if err == nil {
		t.Fatal("start without pipeline succeeded, want error")
	}
}

func TestStopAndStatusCommands(t *testing.T) {
	dir := t.TempDir()
	out, err := runApp(t, "flume", "--state-dir", dir, "start", "demo")
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	id := strings.TrimPrefix(strings.TrimSpace(out), "started run ")
	id = strings.TrimSuffix(id, " (pipeline demo)")
	if id == "" {
		t.Fatalf("could not parse run id from %q", out)
	}
	if _, err := runApp(t, "flume", "--state-dir", dir, "stop", id); err != nil {
		t.Fatalf("stop: %v", err)
	}
	out, err = runApp(t, "flume", "--state-dir", dir, "status", id)
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if !strings.Contains(out, "status=stopped") {
		t.Fatalf("unexpected status output %q", out)
	}
}

func TestListCommand(t *testing.T) {
	dir := t.TempDir()
	if _, err := runApp(t, "flume", "--state-dir", dir, "start", "alpha"); err != nil {
		t.Fatalf("start alpha: %v", err)
	}
	if _, err := runApp(t, "flume", "--state-dir", dir, "start", "beta"); err != nil {
		t.Fatalf("start beta: %v", err)
	}
	out, err := runApp(t, "flume", "--state-dir", dir, "list")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 2 {
		t.Fatalf("list output = %q, want 2 lines", out)
	}
	for _, line := range lines {
		if !strings.HasPrefix(line, "run run-") {
			t.Fatalf("unexpected list line %q", line)
		}
	}
}

func TestListJSONCommand(t *testing.T) {
	dir := t.TempDir()
	if _, err := runApp(t, "flume", "--state-dir", dir, "start", "alpha"); err != nil {
		t.Fatalf("start: %v", err)
	}
	out, err := runApp(t, "flume", "--state-dir", dir, "list", "--json")
	if err != nil {
		t.Fatalf("list --json: %v", err)
	}
	var runs []engine.Run
	if err := json.Unmarshal([]byte(out), &runs); err != nil {
		t.Fatalf("list --json is not valid JSON: %v\n%s", err, out)
	}
	if len(runs) != 1 || runs[0].Pipeline != "alpha" {
		t.Fatalf("unexpected runs: %+v", runs)
	}
}

func TestInspectJSONCommand(t *testing.T) {
	dir := t.TempDir()
	out, err := runApp(t, "flume", "--state-dir", dir, "start", "demo", "--input", "in.csv", "--output", "out.json", "--workers", "2")
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	id := strings.TrimPrefix(strings.TrimSpace(out), "started run ")
	id = strings.TrimSuffix(id, " (pipeline demo)")
	out, err = runApp(t, "flume", "--state-dir", dir, "inspect", id, "--format", "json")
	if err != nil {
		t.Fatalf("inspect: %v", err)
	}
	var run engine.Run
	if err := json.Unmarshal([]byte(out), &run); err != nil {
		t.Fatalf("inspect --format json is not valid JSON: %v\n%s", err, out)
	}
	if run.Workers != 2 || run.Input != "in.csv" || run.Status != engine.StatusRunning {
		t.Fatalf("unexpected run: %+v", run)
	}
}

func TestDuplicatePipelineRequiresForce(t *testing.T) {
	dir := t.TempDir()
	if _, err := runApp(t, "flume", "--state-dir", dir, "start", "demo"); err != nil {
		t.Fatalf("first start: %v", err)
	}
	if _, err := runApp(t, "flume", "--state-dir", dir, "start", "demo"); err == nil {
		t.Fatal("duplicate start without --force succeeded, want error")
	}
	out, err := runApp(t, "flume", "--state-dir", dir, "start", "demo", "--force")
	if err != nil {
		t.Fatalf("forced start: %v", err)
	}
	if !strings.Contains(out, "started run run-") {
		t.Fatalf("unexpected output %q", out)
	}
}
FLUME_EOF

write_file cmd/flume/main.go <<'FLUME_EOF'
// Command flume is a CLI for managing data pipeline runs.
package main

import (
	"fmt"
	"os"

	"flume.dev/tool/internal/app"
)

func main() {
	if err := app.Execute(os.Args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
FLUME_EOF

write_file README.md <<'FLUME_EOF'
# flume

`flume` is a small command-line tool for managing data pipeline runs. It keeps a
run record per execution as a JSON file in a state directory and exposes a
handful of subcommands to start, stop, inspect and list runs.

## Build

```sh
go build ./...
```

## Usage

```sh
flume start <pipeline> --input <path> --output <path> --workers <n> [--force]
flume stop <run-id>
flume status <run-id>
flume list [--status <status>] [--json]
flume inspect <run-id> [--format text|json]
```

All commands accept `--state-dir <dir>` (default: `$FLUME_STATE_DIR` or
`/tmp/flume-state`).

## Layout

- `cmd/flume` — entry point
- `internal/app` — command-line wiring
- `internal/engine` — pipeline run state machine
- `internal/state` — JSON file store for run records

## Tests

```sh
go test ./...
```
FLUME_EOF

write_file docs/UPGRADE.md <<'FLUME_EOF'
# Upgrading the CLI framework

`flume` is built on the `urfave/cli` command-line framework. We currently pin
`github.com/urfave/cli v1.22.14`, the last release of the v1 series.

Upstream has since shipped two further major series. The v2 series was a
transitional release; the current major is **v3** (module path
`github.com/urfave/cli/v3`, first released 2025, current release **v3.11.0**).
The v1 series is no longer maintained.

The v3 API is a breaking rewrite. The migration notes below are the ones that
matter for this repository; the upstream CHANGELOG has the full list.

## What changed

- `cli.NewApp()` is gone. A root command is now a `*cli.Command` value, built
  with a struct literal (`&cli.Command{...}`). The fields we use (`Name`,
  `Usage`, `Version`, `Flags`, `Commands`, `Writer`) keep their names.
- `App.Run(args)` became `Command.Run(ctx, args)`: the first argument is a
  `context.Context`.
- Subcommands are `[]*cli.Command` instead of `[]cli.Command`.
- Flag values are pointers: `cli.StringFlag{...}` becomes
  `&cli.StringFlag{...}` (same for `BoolFlag`, `IntFlag`, ...).
- Action functions take `(context.Context, *cli.Command)` instead of
  `(*cli.Context)`. Inside an action, `c.String("x")`, `c.Bool("x")`,
  `c.Int("x")` and `c.Args()` become `cmd.String("x")`, `cmd.Bool("x")`,
  `cmd.Int("x")` and `cmd.Args()`. Global flags are read the same way — there
  is no `GlobalString` anymore; a flag declared on the root command is visible
  from subcommands through the same accessors.
- `cli.NewExitError(msg, code)` became `cli.Exit(msg, code)`.
- `Command.Run` handles `ExitCoder` errors by calling `os.Exit` with the
  encoded code unless the root command sets an `ExitErrHandler`. Tests that
  exercise error paths must install one, e.g.
  `cmd.ExitErrHandler = func(context.Context, *cli.Command, error) {}`.

## Doing the upgrade

```sh
go get github.com/urfave/cli/v3@v3.11.0
# migrate every import and call site, then:
go mod tidy
go build ./...
go test ./...
```

The module cache in this image already contains v3.11.0 and its dependency
graph, so the upgrade works without network access.
FLUME_EOF

write_file Makefile <<'FLUME_EOF'
.PHONY: build test vet

build:
	go build ./...

test:
	go test ./...

vet:
	go vet ./...
FLUME_EOF

write_file .gitignore <<'FLUME_EOF'
/flume
*.test
FLUME_EOF

# ---- resolve dependencies and prove the suite is green ----
cd "$REPO"
go mod tidy
go test ./...

# ---- build the git history ----
git init -b main
git add go.mod go.sum internal/state internal/engine
git commit -q -m "scaffold state store and pipeline engine"
git add internal/app cmd/flume
git commit -q -m "add flume CLI commands on urfave/cli v1"
git add README.md docs Makefile .gitignore
git commit -q -m "add usage docs, upgrade notes and Makefile"
git log --oneline

# ---- pre-populate the module cache with the v3 target graph ----
# The trial container has no network; the agent must be able to resolve
# github.com/urfave/cli/v3@v3.11.0 (and run `go mod tidy` against it) purely
# from the module cache. Downloading the graph here, at build time, is what
# makes that possible.
SEED=/tmp/flume-seed
rm -rf "$SEED"
mkdir -p "$SEED"
cd "$SEED"
cat > go.mod <<'EOF'
module flume.dev/seed

go 1.22
EOF
cat > main.go <<'EOF'
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/urfave/cli/v3"
)

func main() {
	cmd := &cli.Command{Name: "seed"}
	if err := cmd.Run(context.Background(), os.Args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
EOF
go get github.com/urfave/cli/v3@v3.11.0
go mod tidy
go mod download all
rm -rf "$SEED"

echo "fixture repository ready at $REPO"
