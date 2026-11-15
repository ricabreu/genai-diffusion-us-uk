"""Check that each registered forecast file still matches its recorded MD5 checksum.

Run from the repository root:  python3 python/check_forecast_checksum.py
Exits with an error if a file was changed after it was recorded.
"""
import hashlib
import sys
from pathlib import Path

folder = Path(__file__).resolve().parents[1] / "output" / "forecasts"
files = sorted(folder.glob("forecasts_registered_*.csv"))
if not files:
    sys.exit("No registered forecast file found in output/forecasts/")
failed = False
for f in files:
    recorded = Path(str(f) + ".md5").read_text().split()[0].strip().lower()
    actual = hashlib.md5(f.read_bytes()).hexdigest()
    ok = recorded == actual
    failed |= not ok
    print(f"{'OK      ' if ok else 'MISMATCH'}  {f.name}  recorded {recorded}  actual {actual}")
sys.exit(1 if failed else 0)
