"""Check owned addon sources; never rewrite user/server text or vendor libraries."""
import argparse
import html
import json
from pathlib import Path
import re
import sys
import unicodedata

POLICY = json.loads(Path(__file__).with_name("ui-text-policy.json").read_text(encoding="utf-8"))
MOJIBAKE = re.compile(r"(?:[\u0420\u0421][\u0400-\u04ff\u0080-\u00ff]){3,}")
BYTE_ESCAPES = re.compile(r"(?<!\\)(?:\\(?:[0-9]{1,3}|x[0-9a-fA-F]{2})){2,}")
UNICODE_ESCAPE = re.compile(r"(?<!\\)\\u\{([0-9a-fA-F]+)\}")


def allowed(char):
    value = ord(char)
    return value in POLICY["allowed_codepoints"] or any(
        low <= value <= high for low, high in POLICY["allowed_ranges"])


def inspect_text(text):
    issues = []
    for number, line in enumerate(text.split("\n"), 1):
        expanded = html.unescape(line)
        for match in BYTE_ESCAPES.finditer(line):
            try:
                values = re.findall(r"\\(x[0-9a-fA-F]{2}|[0-9]{1,3})", match[0])
                decoded = bytes(int(v[1:], 16) if v.startswith("x") else int(v) for v in values).decode("utf-8")
            except (ValueError, UnicodeDecodeError):
                continue  # Byte-oriented Lua patterns are not UTF-8 display strings.
            expanded += decoded
        for match in UNICODE_ESCAPE.finditer(line):
            value = int(match[1], 16)
            if value > 0x10FFFF:
                issues.append((number, "Invalid Unicode escape"))
            else:
                expanded += chr(value)
        for char in sorted(set(expanded), key=ord):
            if not allowed(char):
                code = f"U+{ord(char):04X}"
                replacement = POLICY["replacements"].get(code, "use supported text or a texture; review policy for a new locale")
                issues.append((number, f"{code} {unicodedata.name(char, 'UNKNOWN')}: {replacement}"))
        for match in MOJIBAKE.finditer(expanded):
            try:
                repaired = match[0].encode("cp1251").decode("utf-8")
            except (UnicodeEncodeError, UnicodeDecodeError):
                continue
            if any('\u0400' <= c <= '\u04ff' for c in repaired):
                issues.append((number, "Suspected UTF-8 text decoded as Windows-1251"))
    return issues


def check_file(path):
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as error:
        return [(1, f"Invalid UTF-8 at byte {error.start}")]
    return inspect_text(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors, count = 0, 0
    for package in POLICY["packages"]:
        folder = args.root / package
        if not folder.is_dir():
            print(f"Missing package: {folder}")
            errors += 1
            continue
        for path in sorted(folder.rglob("*")):
            if path.suffix.lower() not in POLICY["extensions"] or any(
                    part in POLICY["excluded_directories"] for part in path.relative_to(folder).parts):
                continue
            count += 1
            for line, message in check_file(path):
                print(f"{path.relative_to(args.root)}:{line}: {message}")
                errors += 1
    print(f"UI text: {count} files, {errors} errors")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
