"""Check shared CTR dispatcher targets after regenerating the FIFA DLL."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
functions = {}
for path in (root / "generated/fifadllzf_xex").glob("fifastreet_recomp.*.cpp"):
    source = path.read_text()
    for match in re.finditer(r"DEFINE_REX_FUNC\((sub_8264B[0-9A-F]+)\).*?(?=DEFINE_REX_FUNC\(|\Z)", source, re.S):
        functions[match.group(1)] = match.group()
for address in ("8264B0AC", "8264B0E4"):
    routine = functions[f"sub_{address}"]
    assert "Unresolved" not in routine, address
    assert "outside function" not in routine, address
    for target in ("8264B024", "8264B0DC", "8264B0A4", "8264B02C", "8264B034", "8264B128", "8264B03C"):
        assert f"sub_{target}(ctx, base);" in routine, (address, target)
for address, value in (("8264B09C", 0), ("8264B0A4", 3), ("8264B0DC", 2), ("8264B128", 6)):
    routine = functions[f"sub_{address}"]
    assert f"ctx.r3.s64 = {value};" in routine, address
    assert "return;" in routine, address
print("CTR dispatchers verified: external jumps execute their shared return tails.")
