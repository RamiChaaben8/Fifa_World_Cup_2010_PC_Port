"""Verify the allocation routine's internal branches after ReXGlue codegen."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
generated = root / "generated" / "fifadllzf_xex"
functions = []
for path in generated.glob("fifastreet_recomp.*.cpp"):
    source = path.read_text()
    match = re.search(r"DEFINE_REX_FUNC\(sub_8272ACE8\).*?(?=DEFINE_REX_FUNC\(|\Z)", source, re.S)
    if match:
        functions.append(match.group())
assert len(functions) == 1, "Expected exactly one allocation routine"
routine = functions[0]
assert "Unresolved call" not in routine and "Unresolved branch" not in routine
for address in ("8272B3CC", "8272B3E4", "8272B4FC", "8272B518", "8272B528"):
    assert f"loc_{address}:" in routine, f"Missing internal block {address}"
assert "goto loc_8272B518;" in routine
assert "sub_8272B3CC(ctx" not in routine
print("Allocation region verified: internal blocks and shared epilogue resolved.")
