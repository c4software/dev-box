#!/usr/bin/env python3
"""dev-box: helpers of `devbox ios xcode`, called by ios-xcode.sh, not by hand.

    ios-xcode.py package <Package.swift> <min iOS> [<identity>=<dependency> ...]
    ios-xcode.py binary-target <Package.swift> <name> <path in the package>

The package itself comes from xcodeproj2xtool.py of omarchy-apple-dev; these
only adjust it.
"""
import re
import sys


def identity(url):
    return re.sub(r"\.git$", "", url.rstrip("/").split("/")[-1]).lower()


def cmd_package(path, min_ios, *replacements):
    """Raise the iOS deployment target to min_ios, swap dependencies by identity."""
    text = open(path).read()

    def platform(match):
        current = match.group(1)
        if tuple(int(p) for p in current.split(".")) >= tuple(int(p) for p in min_ios.split(".")):
            return match.group(0)
        print(f"deployment target iOS {current} raised to {min_ios} in the generated package", file=sys.stderr)
        return f'.iOS("{min_ios}")'

    text = re.sub(r'\.iOS\("([0-9.]+)"\)', platform, text)
    for replacement in replacements:
        name, dependency = replacement.split("=", 1)
        pattern = re.compile(r'\.package\((?:url|path): "([^"]+)"[^\n]*\)')
        found = [m for m in pattern.finditer(text) if identity(m.group(1)) == name.lower()]
        if found:
            for match in reversed(found):
                text = text[:match.start()] + dependency + text[match.end():]
        else:
            # Not a direct dependency: declared at the root, it takes the place
            # of the one a dependency asks for (same identity).
            text = re.sub(r"(\n\s*dependencies: \[\n)", lambda m: f"{m.group(1)}        {dependency},\n", text, count=1)
    open(path, "w").write(text)


def cmd_binary_target(path, name, relative):
    """The app target of the generated package depends on a binary target."""
    text = open(path).read()
    if re.search(rf'\.binaryTarget\(name: "{re.escape(name)}"', text):
        print(f"{name}: already a binary target of the package", file=sys.stderr)
        return
    target = re.search(r'\.target\(\s*name: "([^"]+)",\s*dependencies: \[', text)
    if not target:
        sys.exit("no app target with dependencies in Package.swift")
    text = text[:target.end()] + f'\n                "{name}",' + text[target.end():]
    text = re.sub(r"(\n    targets: \[\n)", lambda m: f'{m.group(1)}        .binaryTarget(name: "{name}", path: "{relative}"),\n', text, count=1)
    open(path, "w").write(text)


COMMANDS = {
    "package": cmd_package,
    "binary-target": cmd_binary_target,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](*sys.argv[2:])
