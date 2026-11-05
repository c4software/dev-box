#!/usr/bin/env python3
"""dev-box: helpers of `devbox ios xcode`, called by ios-xcode.sh, not by hand.

    ios-xcode.py convert <project> <out> <configuration> [--target T] [--bundle-id ID]
    ios-xcode.py setting <project> <configuration> <target or -> <key>
    ios-xcode.py package <Package.swift> <min iOS> [<identity>=<dependency> ...]
    ios-xcode.py darwin-manifests <checkouts dir> <Package.swift>
    ios-xcode.py patch-manifests <package dir>
    ios-xcode.py symbols <out.swift> <catalog> [<catalog> ...]
    ios-xcode.py catalogs <Package.swift>
    ios-xcode.py xcframework <Name.framework> <Name.xcframework>
    ios-xcode.py binary-target <Package.swift> <name> <path in the package>

convert runs xcodeproj2xtool.py of omarchy-apple-dev (OAD_TOOLS) with the
settings of the given configuration instead of Release, the only one it
reads on its own.
"""
import os
import plistlib
import re
import sys

OAD_TOOLS = os.environ.get("OAD_TOOLS", os.path.expanduser("~/.local/share/omarchy-apple-dev/tools"))

# Manifest tests that answer for the machine SwiftPM runs on, not for the
# platform the package is built for: on a Mac they are true (Darwin, macOS)
# or false (Linux), and the iOS build expects that answer.
HOST_TESTS = {"canImport(Darwin)": "true", "os(macOS)": "true", "os(Linux)": "false"}
HOST_LINE = re.compile(r"^\s*#\s*(if|elseif)\b.*(" + "|".join(re.escape(t) for t in HOST_TESTS) + ")")

# Members the SDK already has: Xcode leaves an asset of that name out of the
# shortcuts it generates, so as not to hide them.
TAKEN = {
    "Color": {"accentColor", "black", "blue", "brown", "clear", "cyan", "gray", "green", "indigo", "mint",
              "orange", "pink", "primary", "purple", "red", "secondary", "teal", "white", "yellow"},
    "UIColor": {"black", "blue", "brown", "clear", "cyan", "darkGray", "darkText", "gray", "green", "label",
                "lightGray", "lightText", "link", "magenta", "orange", "placeholderText", "purple", "red",
                "separator", "tintColor", "white", "yellow"},
    "Image": set(),
    "UIImage": {"actions", "add", "checkmark", "remove", "strokedCheckmark"},
}


def converter():
    sys.path.insert(0, OAD_TOOLS)
    import xcodeproj2xtool  # noqa: E402

    return xcodeproj2xtool


def with_configuration(module, configuration):
    """Every setting the generator reads comes from `configuration`."""
    original = module.Generator.config_layers

    def config_layers(self, cfg_list_id, config="Release"):
        return original(self, cfg_list_id, configuration)

    module.Generator.config_layers = config_layers


def cmd_convert(project, out, configuration, *rest):
    module = converter()
    with_configuration(module, configuration)
    sys.argv = ["xcodeproj2xtool.py", project, "--out", out, *rest]
    module.main()


def cmd_setting(project, configuration, target, key):
    """One build setting of the target, expanded: target over project, pbxproj over xcconfig."""
    module = converter()
    with_configuration(module, configuration)
    generator = module.Generator(project, None if target == "-" else target)
    _oid, picked = generator.pick_target()
    layers = list(reversed(generator.target_merged(picked)))
    value = generator.setting(layers, key)
    if value is None:
        return
    if isinstance(value, list):
        value = " ".join(value)
    print(generator.expand(str(value), layers))


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


def host_test_lines(manifest):
    with open(manifest, errors="replace") as f:
        return [line for line in f if HOST_LINE.match(line)]


def cmd_darwin_manifests(checkouts, package):
    """Checkouts whose manifest answers differently on Linux, each followed by
    "direct" or "indirect": only a direct dependency of the package can be
    declared by path in its place, since xtool builds the app from a package
    of its own where this one is not the root."""
    if not os.path.isdir(checkouts):
        return
    direct = {identity(u) for u in re.findall(r'\.package\(url: "([^"]+)"', open(package).read())}
    for name in sorted(os.listdir(checkouts)):
        directory = os.path.join(checkouts, name)
        manifests = [f for f in os.listdir(directory) if re.fullmatch(r"Package(@swift-[0-9.]+)?\.swift", f)] \
            if os.path.isdir(directory) else []
        if any(host_test_lines(os.path.join(directory, m)) for m in manifests):
            print(name, "direct" if name.lower() in direct else "indirect")


def cmd_patch_manifests(directory):
    for name in os.listdir(directory):
        if not re.fullmatch(r"Package(@swift-[0-9.]+)?\.swift", name):
            continue
        path = os.path.join(directory, name)
        lines = open(path, errors="replace").read().split("\n")
        for i, line in enumerate(lines):
            if HOST_LINE.match(line):
                for test, answer in HOST_TESTS.items():
                    line = line.replace(test, answer)
                lines[i] = line + "  // devbox ios xcode: answered as on a Mac"
        open(path, "w").write("\n".join(lines))


def words(name):
    return [w for w in re.split(r"[^0-9A-Za-z]+", name) if w]


def swift_name(name):
    """The name actool gives the symbol: "brand-blue" -> brandBlue, "URL" -> url."""
    parts = words(name)
    if not parts:
        return "_"
    first = parts[0]
    head = first.lower() if first == first.upper() else first[0].lower() + first[1:]
    out = head + "".join(p[0].upper() + p[1:] for p in parts[1:])
    return "_" + out if out[0].isdigit() else out


def provides_namespace(folder):
    try:
        import json

        with open(os.path.join(folder, "Contents.json")) as f:
            return bool(json.load(f).get("properties", {}).get("provides-namespace"))
    except (OSError, ValueError):
        return False


def collect(catalog):
    found = []

    def walk(directory, prefix):
        for child in sorted(os.listdir(directory)):
            path = os.path.join(directory, child)
            base, ext = os.path.splitext(child)
            if ext == ".colorset":
                found.append((prefix + base, True))
            elif ext == ".imageset":
                found.append((prefix + base, False))
            elif ext == "" and os.path.isdir(path):
                walk(path, prefix + (base + "/" if provides_namespace(path) else ""))

    walk(catalog, "")
    return found


def cmd_symbols(out, *catalogs):
    """The SwiftUI and UIKit shortcuts Xcode adds to the asset symbols
    (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS), which the
    actool of the box does not write."""
    assets = sorted({a for c in catalogs for a in collect(c)})
    colors = sorted({swift_name(n) for n, color in assets if color})
    images = sorted({swift_name(n) for n, color in assets if not color})
    lines = ["// Generated by devbox ios xcode: the asset symbol extensions Xcode writes", "import SwiftUI",
             "#if canImport(UIKit)", "import UIKit", "#endif", ""]

    def block(kind, resource, names, condition=None):
        names = [n for n in names if n not in TAKEN[kind]]
        if not names:
            return
        if condition:
            lines.append(f"#if {condition}")
        lines.append(f"@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)")
        lines.append(f"extension {kind} {{")
        init = {"Color": "Color({})", "UIColor": "UIColor(resource: {})",
                "Image": "Image({})", "UIImage": "UIImage(resource: {})"}[kind]
        for n in names:
            lines.append(f"    static var {n}: {kind} {{ {init.format(f'DeveloperToolsSupport.{resource}.{n}')} }}")
        lines.append("}")
        if condition:
            lines.append("#endif")
        lines.append("")

    block("Color", "ColorResource", colors)
    block("UIColor", "ColorResource", colors, "canImport(UIKit)")
    block("Image", "ImageResource", images)
    block("UIImage", "ImageResource", images, "canImport(UIKit)")
    open(out, "w").write("\n".join(lines))


def cmd_catalogs(path):
    """The asset catalogs the generated target processes, relative to the package."""
    text = open(path).read()
    for name in re.findall(r'\.process\("([^"]+\.xcassets)"\)', text):
        print(name)


def cmd_xcframework(framework, out):
    """A device framework wrapped as the .xcframework a SwiftPM binary target takes."""
    import shutil

    name = os.path.basename(framework)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "ios-arm64"))
    shutil.copytree(framework, os.path.join(out, "ios-arm64", name), symlinks=True)
    with open(os.path.join(out, "Info.plist"), "wb") as f:
        plistlib.dump({
            "AvailableLibraries": [{
                "LibraryIdentifier": "ios-arm64",
                "LibraryPath": name,
                "BinaryPath": f"{name}/{os.path.splitext(name)[0]}",
                "SupportedArchitectures": ["arm64"],
                "SupportedPlatform": "ios",
            }],
            "CFBundlePackageType": "XFWK",
            "XCFrameworkFormatVersion": "1.0",
        }, f)


def cmd_binary_target(path, name, relative):
    """The app target of the generated package depends on a binary target."""
    text = open(path).read()
    target = re.search(r'\.target\(\s*name: "([^"]+)",\s*dependencies: \[', text)
    if not target:
        sys.exit("no app target with dependencies in Package.swift")
    text = text[:target.end()] + f'\n                "{name}",' + text[target.end():]
    text = re.sub(r"(\n    targets: \[\n)", lambda m: f'{m.group(1)}        .binaryTarget(name: "{name}", path: "{relative}"),\n', text, count=1)
    open(path, "w").write(text)


COMMANDS = {
    "convert": cmd_convert,
    "setting": cmd_setting,
    "package": cmd_package,
    "darwin-manifests": cmd_darwin_manifests,
    "patch-manifests": cmd_patch_manifests,
    "symbols": cmd_symbols,
    "catalogs": cmd_catalogs,
    "xcframework": cmd_xcframework,
    "binary-target": cmd_binary_target,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](*sys.argv[2:])
