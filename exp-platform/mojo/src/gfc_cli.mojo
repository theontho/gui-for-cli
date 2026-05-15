from std.python import Python, PythonObject

from gfc_bundle import load_bundle, runtime_state
from gfc_common import (
    builtins,
    find_repo_root,
    normalize_locale,
    parse_args,
    py_dict,
    py_str,
)
from gfc_core import build_core_state


def emit_metrics(metrics: PythonObject, benchmark_output: String) raises:
    var json = Python.import_module("json")
    for key in metrics:
        print("metric " + py_str(key) + "=" + py_str(metrics[key]))
    if benchmark_output:
        var pathlib = Python.import_module("pathlib")
        var path = pathlib.Path(benchmark_output).expanduser().resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")


def benchmark_summary(
    metrics: PythonObject, core: PythonObject
) raises -> String:
    return (
        "gfc-mojo benchmark bundle_loaded_ms="
        + py_str(metrics["bundleLoaded_ms"])
        + " ui_ready_ms="
        + py_str(metrics["uiReady_ms"])
        + " pages="
        + py_str(metrics["pages"])
        + " controls="
        + py_str(core["control_count"])
        + " actions="
        + py_str(core["action_count"])
        + " terminal_text_direction="
        + py_str(core["terminal_text_direction"])
    )


def describe_snapshot(
    bundle: PythonObject, core: PythonObject
) raises -> PythonObject:
    var snapshot = py_dict()
    snapshot["displayName"] = bundle["display_name"]
    snapshot["bundleRoot"] = py_str(bundle["bundle_root"])
    snapshot["workspaceRoot"] = py_str(bundle["workspace_root"])
    snapshot["pages"] = core["pages"].__len__()
    snapshot["controls"] = core["control_count"]
    snapshot["actions"] = core["action_count"]
    snapshot["rtlLayout"] = core["rtl_layout"]
    snapshot["terminalTextDirection"] = core["terminal_text_direction"]
    return snapshot


def run() raises:
    var args = parse_args()
    if args.get("help"):
        return

    var pathlib = Python.import_module("pathlib")
    var locale_module = Python.import_module("locale")
    var time = Python.import_module("time")
    var json = Python.import_module("json")

    var repo_root = find_repo_root(
        pathlib.Path(args["repo_root"]).expanduser() if args[
            "repo_root"
        ] else pathlib.Path.cwd()
    )
    var bundle_arg = py_str(args["bundle"] or "examples/WGSExtract")
    var locale = normalize_locale(
        py_str(args["locale"] or (locale_module.getlocale()[0] or "en"))
    )

    var started = time.perf_counter()
    var bundle = load_bundle(bundle_arg, repo_root, locale)
    var loaded = time.perf_counter()
    var state = runtime_state(bundle)
    var core = build_core_state(bundle, state)
    var ready = time.perf_counter()

    var metrics = py_dict()
    metrics["bundleLoaded_ms"] = builtins().round(
        (loaded - started) * 1000.0, 3
    )
    metrics["uiReady_ms"] = builtins().round((ready - started) * 1000.0, 3)
    metrics["pages"] = core["pages"].__len__()
    metrics["actions"] = core["action_count"]
    metrics["controls"] = core["control_count"]

    if args["describe"]:
        print(json.dumps(describe_snapshot(bundle, core), sort_keys=True))
        return
    if args["benchmark"]:
        print(benchmark_summary(metrics, core))
        emit_metrics(metrics, py_str(args["benchmark_output"] or ""))
        return
    if args["check"] or args["once"]:
        print(
            "Loaded "
            + py_str(core["pages"].__len__())
            + " pages, "
            + py_str(core["control_count"])
            + " controls, "
            + py_str(core["action_count"])
            + " actions from "
            + py_str(bundle["bundle_root"])
        )
        return

    print(
        "gui-for-cli-mojo: headless/core renderer loaded "
        + py_str(core["pages"].__len__())
        + " pages. Use --check, --describe, "
        + "or --benchmark --once for validation."
    )
