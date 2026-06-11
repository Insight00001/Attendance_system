"""
clear_cache.py — deletes all __pycache__ folders and .pyc files
under the backend directory so Python recompiles from source.

Run once:
    python clear_cache.py
"""
import os, shutil, pathlib

root = pathlib.Path(__file__).parent

removed = 0
for p in list(root.rglob("__pycache__")):
    # skip the venv
    if "venv" in p.parts:
        continue
    shutil.rmtree(p, ignore_errors=True)
    print(f"  removed {p}")
    removed += 1

for p in list(root.rglob("*.pyc")):
    if "venv" in p.parts:
        continue
    p.unlink(missing_ok=True)
    removed += 1

print(f"\nDone — {removed} cache entries removed. Restart the Flask server now.")
