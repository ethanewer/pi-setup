#!/bin/bash
# Oracle for gale-meridian: write the provisioning script (this IS the work),
# then RUN it to leave the workbench provisioned and the report written.
# Never reads /tests.
set -eu

PROVISION="/app/provision.sh"

# ---- 1. Write the deliverable provisioning script.
cat > "$PROVISION" <<'SH'
#!/bin/bash
# Idempotent provisioning of the Meridian Basin causal workbench (offline).
set -eu

CONF="/app/workbench.conf"

read_conf() {
    awk -F= -v k="$1" '$1 == k { print $2 }' "$CONF"
}

KERNEL="$(read_conf kernel_name)"
DISPLAY="$(read_conf display_name)"
REPORT="$(read_conf report)"

# ---- 1) install the vendored R packages (data.table, jsonlite, IRkernel, deps)
pkgs_ok() {
    Rscript --vanilla -e 'quit(status = !(requireNamespace("data.table", quietly=TRUE) && requireNamespace("jsonlite", quietly=TRUE) && requireNamespace("IRkernel", quietly=TRUE)))' >/dev/null 2>&1
}
if ! pkgs_ok; then
    apt-get install -y -qq --no-install-recommends /app/vendor/*.deb \
        >/dev/null 2>&1 || true
    # dpkg fallback (dependency ordering may need two passes)
    if ! pkgs_ok; then
        dpkg -i /app/vendor/*.deb >/dev/null 2>&1 || true
        dpkg -i /app/vendor/*.deb >/dev/null 2>&1 || true
    fi
fi
if ! pkgs_ok; then
    echo "provision: vendored R packages failed to install" >&2
    exit 1
fi

# ---- 2) register the user-level R Jupyter kernelspec
kernel_registered() {
    python3 - "$KERNEL" <<'PY' >/dev/null 2>&1
import json, subprocess, sys
out = subprocess.run(["jupyter", "kernelspec", "list", "--json"],
                     capture_output=True, text=True)
specs = json.loads(out.stdout or "{}").get("kernelspecs", {})
sys.exit(0 if sys.argv[1] in specs else 1)
PY
}
if ! kernel_registered; then
    Rscript --vanilla -e "IRkernel::installspec(name=\"$KERNEL\", displayname=\"$DISPLAY\", user=TRUE)" >/dev/null
fi

# ---- 3) kernelspec integrity: every listed kernelspec argv[0] must exist+exec
python3 - "$KERNEL" "$DISPLAY" <<'PY'
import json, os, subprocess, sys
kernel, display = sys.argv[1], sys.argv[2]


def specs():
    out = subprocess.run(["jupyter", "kernelspec", "list", "--json"],
                         capture_output=True, text=True)
    return json.loads(out.stdout or "{}").get("kernelspecs", {})


def dead(name, spec):
    kdir = spec.get("resource_dir")
    kj = os.path.join(kdir, "kernel.json") if kdir else None
    try:
        argv0 = json.load(open(kj)).get("argv", [None])[0]
    except Exception:
        return True
    return not (argv0 and os.path.isfile(argv0) and os.access(argv0, os.X_OK))


for name, spec in list(specs().items()):
    if dead(name, spec):
        subprocess.run(["jupyter", "kernelspec", "remove", "-y", name],
                       capture_output=True, text=True)
        if spec.get("resource_dir"):
            subprocess.run(["rm", "-rf", spec["resource_dir"]],
                           capture_output=True, text=True)

if kernel not in specs():
    subprocess.run(["Rscript", "--vanilla", "-e",
                    'IRkernel::installspec(name="%s", displayname="%s", '
                    'user=TRUE)' % (kernel, display)],
                   capture_output=True, text=True)
PY

# ---- 4) write the machine-readable report from the live environment
python3 - "$KERNEL" "$REPORT" <<'PY'
import json, os, subprocess, sys

kernel, report_path = sys.argv[1], sys.argv[2]

out = subprocess.run(["jupyter", "kernelspec", "list", "--json"],
                     capture_output=True, text=True)
specs = json.loads(out.stdout or "{}").get("kernelspecs", {})
if kernel not in specs:
    raise SystemExit("kernelspec %r not registered" % kernel)
kj = os.path.join(specs[kernel]["resource_dir"], "kernel.json")
argv0 = json.load(open(kj))["argv"][0]
if not (os.path.isfile(argv0) and os.access(argv0, os.X_OK)):
    raise SystemExit("kernelspec argv[0] not executable: %r" % argv0)

packages = []
for p in ("data.table", "jsonlite", "IRkernel"):
    r = subprocess.run(
        ["Rscript", "--vanilla", "-e",
         'quit(status = !requireNamespace("%s", quietly=TRUE))' % p],
        capture_output=True, text=True)
    if r.returncode == 0:
        packages.append(p)
if not {"data.table", "jsonlite", "IRkernel"} <= set(packages):
    raise SystemExit("required R packages missing: %s" % packages)

r = subprocess.run(
    ["Rscript", "--vanilla", "-e",
     'cat(paste(R.version$major, R.version$minor, sep="."))'],
    capture_output=True, text=True)
r_version = r.stdout.strip()

report = {
    "kernel": kernel,
    "r_binary": argv0,
    "packages": packages,
    "r_version": r_version,
}
os.makedirs(os.path.dirname(report_path) or ".", exist_ok=True)
with open(report_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
PY

echo "provision: workbench ready (kernel=$KERNEL)"
SH
chmod +x "$PROVISION"

# ---- 2. Run the produced provisioning script (twice: must be idempotent).
bash "$PROVISION"
bash "$PROVISION"

echo "solve.sh done -> $PROVISION and /app/workbench_report.json"
ls -l "$PROVISION" /app/workbench_report.json
