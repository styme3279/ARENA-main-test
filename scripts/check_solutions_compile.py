#!/usr/bin/env python
"""
Byte-compile every solutions*.py across all chapters to catch syntax errors.

This only *compiles* the files (parse -> bytecode); it does not import or run
them, so it needs none of the ARENA dependencies (torch, transformer_lens, …)
and no GPU/API keys. It's a fast guard that the committed/generated solution
files are at least valid Python.

Exit code 0 if all compile, 1 if any fail (or none are found).
"""

import sys
import traceback
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    files = sorted(REPO_ROOT.glob("chapter*/exercises/**/solutions*.py"))
    if not files:
        print("ERROR: no solutions*.py files found", file=sys.stderr)
        return 1

    failures: list[tuple[Path, str]] = []
    for f in files:
        try:
            # Built-in compile(): parse + byte-compile in memory, no .pyc written
            # and no imports/execution (so no dependencies needed).
            compile(f.read_text(encoding="utf-8"), str(f), "exec")
            print(f"  ok    {f.relative_to(REPO_ROOT)}")
        except SyntaxError:
            failures.append((f, traceback.format_exc(limit=0)))
            print(f"  FAIL  {f.relative_to(REPO_ROOT)}", file=sys.stderr)

    print(f"\n{len(files) - len(failures)}/{len(files)} solutions files compiled cleanly.")

    if failures:
        print("\nFailures:", file=sys.stderr)
        for f, msg in failures:
            print(f"\n### {f.relative_to(REPO_ROOT)}\n{msg}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
