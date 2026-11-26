"""Checks the App Store text in appstore/PUBLISHING.md against Apple's character limits.

    python3 tools/check_listing.py

Each limited field is the first code block after a line containing its label.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "appstore", "PUBLISHING.md")

# label in the guide -> Apple's limit
LIMITS = {
    "Name (30 characters at most)": 30,
    "**Subtitle** (30)": 30,
    "**What's New in This Version** (4000": 4000,
    "**Promotional Text** (170)": 170,
    "**Description** (4000)": 4000,
    "**Keywords** (100": 100,
    "**Notes** (4000": 4000,
}


def main():
    text = open(DOC, encoding="utf-8").read()
    failed = False
    for label, limit in LIMITS.items():
        start = text.find(label)
        if start < 0:
            print(f"✗ label not found: {label}")
            failed = True
            continue
        block = re.search(r"```\n(.*?)\n\s*```", text[start:], re.S)
        value = "\n".join(line.strip() for line in block.group(1).split("\n")).strip()
        ok = len(value) <= limit
        failed |= not ok
        print(f"{'✓' if ok else '✗'} {label.strip('*')}: {len(value)}/{limit}")
        if label.startswith("**Keywords"):
            if ", " in value:
                print("✗ keywords: no spaces after commas")
                failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
