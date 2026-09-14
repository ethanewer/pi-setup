#!/bin/bash
# Oracle for yaw-roadstead.
#
# Applies the minimal upstream fix to the cobra checkout at /app/src
# (YAML see_also entries for child subcommands must carry the full command
# path, `child.CommandPath()`, not the bare leaf name, `child.Name()`),
# first writing the reproduction deliverable /app/repro.sh exactly as the
# instruction requires: an executable script that drives the tree's own Go
# tooling from the repository root and exits 0 iff a nested subcommand is
# listed in see_also under its full command path. The repro's own test file
# is left in the tree (the verifier replays the script against a pristine
# copy of the tree, so its files must persist).
set -eu

# 1) reproduction deliverable: a test file added to the tree (package doc
#    reuses the project's own GenYaml machinery), left in place.
cat > /app/src/doc/task_repro_seealso_test.go <<'GOGO'
package doc

// Authored reproduction for the YAML see_also bug: the see_also entry for a
// nested subcommand must carry the full command path, not the bare leaf name.

import (
	"bytes"
	"testing"

	"github.com/spf13/cobra"
)

func TestTaskReproSeeAlso(t *testing.T) {
	echoSub := &cobra.Command{Use: "echo-sub [arg]", Short: "sub command", Run: emptyRun}
	echo := &cobra.Command{Use: "echo [arg]", Short: "echo command"}
	root := &cobra.Command{Use: "rootcmd [arg]", Short: "root command"}

	echo.AddCommand(echoSub)
	root.AddCommand(echo)

	buf := new(bytes.Buffer)
	if err := GenYaml(echo, buf); err != nil {
		t.Fatal(err)
	}
	output := buf.String()

	checkStringContains(t, output, "- rootcmd echo echo-sub - sub command")
	checkStringOmits(t, output, "- echo-sub - sub command")
}
GOGO

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Reproduction for the yaw-roadstead YAML see_also symptom.
# Run from the repository root. Exits 0 iff YAML doc generation lists a
# nested subcommand in see_also under its full command path; non-zero
# otherwise (the buggy tree).
set -u
go test -v ./... -run TestTaskReproSeeAlso
SH
chmod +x /app/repro.sh

# 2) the fix: see_also entries for children use the fully qualified path.
cd /app/src
sed -i 's/child.Name()+" - "+child.Short/child.CommandPath()+" - "+child.Short/' doc/yaml_docs.go
grep -q 'child.CommandPath()+" - "+child.Short' doc/yaml_docs.go

# 3) prove the fix: the reproduction now exits 0 on this tree.
cd /app/src && /app/repro.sh

echo "oracle: fix applied and /app/repro.sh passes on the repaired tree"