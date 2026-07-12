#!/usr/bin/env python3
"""Create a reviewed cohort-specific mapping variant.

The source mappings remain identical; only the immutable mapping version is
changed so each migration cohort receives its own receipt and replay scope.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("mapping_version")
    args = parser.parse_args()
    try:
        value = json.loads(args.mapping.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("mapping root must be an object")
        value["mapping_version"] = args.mapping_version
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps({"output": str(args.output), "mapping_version": args.mapping_version}, sort_keys=True))
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as error:
        print(f"mapping variant failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
