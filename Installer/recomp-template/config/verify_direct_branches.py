"""Fail if regenerated PPC code contains unresolved direct control flow."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
issues = set()
for path in (root / "generated").rglob("worldcup2010_recomp.*.cpp"):
    source = path.read_text()
    for site, target in re.findall(
        r"Unresolved (?:call|branch) from 0x([0-9A-F]+) to 0x([0-9A-F]+)", source
    ):
        issues.add((site, target))
    assert "/* branch to" not in source, f"Silently omitted branch in {path}"
    for routine in re.split(r"(?=DEFINE_REX_FUNC\()", source)[1:]:
        jumps = set(re.findall(r"goto (loc_[0-9A-F]+);", routine))
        labels = set(re.findall(r"^(loc_[0-9A-F]+):", routine, re.M))
        assert not jumps - labels, f"Missing local labels in {path}: {jumps - labels}"
if issues:
    for site, target in sorted(issues)[:20]:
        print(f"Unresolved direct branch: 0x{site} to 0x{target}")
assert not issues, f"{len(issues)} unresolved direct control-flow sites"
print("Direct branches verified: no unresolved calls, branches, or omitted CTR jumps.")
