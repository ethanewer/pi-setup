"""corbel-weir verifier helper: the wheel rebuilt from the agent's sdist must
be the click 8.5.0 release."""
import sys
import zipfile
from pathlib import Path

rb = Path(sys.argv[1])
wheels = sorted(rb.glob("click-*.whl"))
if len(wheels) != 1:
    print(f"expected exactly one rebuilt wheel, got {wheels}", file=sys.stderr)
    sys.exit(1)
with zipfile.ZipFile(wheels[0]) as z:
    dist_info = next(n for n in z.namelist() if n.endswith(".dist-info/METADATA"))
    fields = dict(
        line.split(": ", 1)
        for line in z.read(dist_info).decode().splitlines()
        if ": " in line
    )
for field, want in (("Name", "click"), ("Version", "8.5.0")):
    if fields.get(field) != want:
        print(f"sdist-rebuilt wheel {field} = {fields.get(field)!r}",
              file=sys.stderr)
        sys.exit(1)
print("check_sdist_rebuild: standalone sdist rebuild is the 8.5.0 release")