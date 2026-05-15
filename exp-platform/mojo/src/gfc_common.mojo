from std import sys
from std.python import Python, PythonObject


comptime VERSION = "0.1.0"


def builtins() raises -> PythonObject:
    return Python.import_module("builtins")


def py_str(value: PythonObject) raises -> String:
    return String(builtins().str(value))


def py_bool(value: PythonObject) raises -> Bool:
    return Bool(builtins().bool(value))


def py_list() raises -> PythonObject:
    return builtins().list()


def py_dict() raises -> PythonObject:
    return builtins().dict()


def items_or_empty(value: PythonObject) raises -> PythonObject:
    if value:
        return value
    return py_list()


def usage() -> String:
    return (
        "Usage: gui_for_cli_mojo.mojo [--repo-root PATH] [--bundle PATH] "
        "[--locale LOCALE] [--check] [--describe] [--once] [--benchmark] "
        "[--benchmark-full] [--benchmark-output PATH]"
    )


def parse_args() raises -> PythonObject:
    var args = sys.argv()
    var parsed = py_dict()
    parsed["repo_root"] = ""
    parsed["bundle"] = ""
    parsed["locale"] = ""
    parsed["check"] = False
    parsed["describe"] = False
    parsed["once"] = False
    parsed["benchmark"] = False
    parsed["benchmark_full"] = False
    parsed["benchmark_output"] = ""

    var i = 1
    while i < len(args):
        var arg = args[i]
        if arg == "--help" or arg == "-h":
            print(usage())
            parsed["help"] = True
            return parsed
        if arg == "--version" or arg == "-V":
            print("gui-for-cli-mojo " + VERSION)
            parsed["help"] = True
            return parsed
        if arg == "--check":
            parsed["check"] = True
        elif arg == "--describe":
            parsed["describe"] = True
        elif arg == "--once":
            parsed["once"] = True
        elif arg == "--benchmark":
            parsed["benchmark"] = True
        elif arg == "--benchmark-full":
            parsed["benchmark"] = True
            parsed["benchmark_full"] = True
        elif (
            arg == "--repo-root"
            or arg == "--bundle"
            or arg == "--locale"
            or arg == "--benchmark-output"
        ):
            if i + 1 >= len(args):
                raise Error("Missing value for " + arg)
            i += 1
            if arg == "--repo-root":
                parsed["repo_root"] = args[i]
            elif arg == "--bundle":
                parsed["bundle"] = args[i]
            elif arg == "--locale":
                parsed["locale"] = args[i]
            else:
                parsed["benchmark_output"] = args[i]
        else:
            raise Error("Unknown argument: " + arg)
        i += 1
    return parsed


def normalize_locale(value: String) raises -> String:
    var normalized = py_str(builtins().str(value).replace("_", "-").strip())
    if normalized:
        return normalized
    return "en"


def language_code(locale: String) raises -> String:
    var text = builtins().str(locale).replace("_", "-")
    return py_str(text.split("-", 1)[0].lower())


def find_repo_root(start: PythonObject) raises -> PythonObject:
    var pathlib = Python.import_module("pathlib")
    var current = pathlib.Path(start).expanduser().resolve()
    if (current / ".git").exists() and (current / "examples").is_dir():
        return current
    for parent in current.parents:
        if (parent / ".git").exists() and (parent / "examples").is_dir():
            return parent
    return current


def resolve_input_path(
    path_text: String, repo_root: PythonObject
) raises -> PythonObject:
    var pathlib = Python.import_module("pathlib")
    var path = pathlib.Path(path_text).expanduser()
    if not path.is_absolute():
        path = repo_root / path
    return path.resolve()
