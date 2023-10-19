aliased_import = "@import(\"raylib\")"
unaliased_import = "@import(\"../lib/raylib/raylib.zig\")"

with open("src/main.zig", "r") as fd:
    lines = fd.readlines()
    newlines = [
        line.replace(unaliased_import, aliased_import) for line in lines
    ]
    print(newlines[:3])
