from std.python import Python, PythonObject

from gfc_common import (
    builtins,
    items_or_empty,
    language_code,
    py_dict,
    py_list,
    py_str,
    resolve_input_path,
)


def find_manifest_root(root: PythonObject) raises -> PythonObject:
    if (root / "manifest.json").is_file():
        return root
    var candidates = py_list()
    for child in root.iterdir():
        if child.is_dir() and (child / "manifest.json").is_file():
            candidates.append(child)
    if candidates.__len__() == 1:
        return candidates[0]
    return root


def archive_extract_root(
    path: PythonObject, repo_root: PythonObject
) raises -> PythonObject:
    var hashlib = Python.import_module("hashlib")
    var re = Python.import_module("re")
    var digest = py_str(hashlib.sha256(path.read_bytes()).hexdigest()[0:12])
    var safe = py_str(re.sub(r"[^A-Za-z0-9_.-]+", "-", path.name).strip(".-"))
    if not safe:
        safe = "bundle"
    return (
        repo_root / "tmp" / "mojo-bundles" / (safe + "-" + digest)
    ).resolve()


def safe_destination(
    root: PythonObject, member_name: PythonObject
) raises -> PythonObject:
    var destination = (root / member_name).resolve()
    if (
        destination != root.resolve()
        and root.resolve() not in destination.parents
    ):
        raise Error(
            "Archive member escapes bundle root: " + py_str(member_name)
        )
    return destination


def extract_archive(
    path: PythonObject, repo_root: PythonObject
) raises -> PythonObject:
    var zipfile = Python.import_module("zipfile")
    var tarfile = Python.import_module("tarfile")
    var gzip = Python.import_module("gzip")
    var target = archive_extract_root(path, repo_root)
    if not (target / ".complete").is_file():
        target.mkdir(parents=True, exist_ok=True)
        if zipfile.is_zipfile(path):
            var archive = zipfile.ZipFile(path)
            try:
                for member in archive.infolist():
                    var destination = safe_destination(target, member.filename)
                    if member.is_dir():
                        destination.mkdir(parents=True, exist_ok=True)
                    else:
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(archive.read(member))
            finally:
                archive.close()
        elif tarfile.is_tarfile(path):
            var archive = tarfile.open(path)
            try:
                for member in archive.getmembers():
                    var destination = safe_destination(target, member.name)
                    if member.isdir():
                        destination.mkdir(parents=True, exist_ok=True)
                    elif member.isfile():
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        var source = archive.extractfile(member)
                        if source is not None:
                            destination.write_bytes(source.read())
            finally:
                archive.close()
        elif py_str(path.suffix) == ".gz":
            (target / "manifest.json").write_bytes(gzip.open(path, "rb").read())
        else:
            raise Error("Unsupported bundle archive: " + py_str(path))
        (target / ".complete").write_text("ok\n", encoding="utf-8")
    return find_manifest_root(target)


def load_manifest(
    bundle_path: PythonObject, repo_root: PythonObject
) raises -> PythonObject:
    var path = bundle_path.resolve()
    var result = py_dict()
    if path.is_file() and py_str(path.name) == "manifest.json":
        result["root"] = path.parent
        result["manifest_path"] = path
    elif path.is_dir():
        var root = find_manifest_root(path)
        result["root"] = root
        result["manifest_path"] = root / "manifest.json"
    elif path.is_file():
        var root = extract_archive(path, repo_root)
        result["root"] = root
        result["manifest_path"] = root / "manifest.json"
    else:
        raise Error(
            "Expected bundle directory, manifest.json, or supported archive,"
            " got "
            + py_str(bundle_path)
        )
    if not result["manifest_path"].is_file():
        raise Error(
            "Missing manifest.json at " + py_str(result["manifest_path"])
        )
    var json = Python.import_module("json")
    result["manifest"] = json.loads(
        result["manifest_path"].read_text(encoding="utf-8")
    )
    if not builtins().isinstance(result["manifest"], builtins().dict):
        raise Error("manifest.json must contain an object")
    return result


def flatten_strings_into(
    target: PythonObject, prefix: String, data: PythonObject
) raises:
    var collections = Python.import_module("collections.abc")
    for key in data:
        var full_key = py_str(key)
        if prefix:
            full_key = prefix + "." + full_key
        var value = data[key]
        if builtins().isinstance(value, collections.Mapping):
            flatten_strings_into(target, full_key, value)
        elif (
            builtins().isinstance(value, builtins().str)
            or builtins().isinstance(value, builtins().int)
            or builtins().isinstance(value, builtins().float)
            or builtins().isinstance(value, builtins().bool)
        ):
            target[full_key] = py_str(value)


def load_strings(
    bundle_root: PythonObject, locale: String
) raises -> PythonObject:
    var tomllib = Python.import_module("tomllib")
    var strings_dir = bundle_root / "strings"
    var candidates = py_list()
    candidates.append(strings_dir / ("strings." + locale + ".toml"))
    var lang = language_code(locale)
    if lang != locale:
        candidates.append(strings_dir / ("strings." + lang + ".toml"))
    candidates.append(strings_dir / "strings.toml")
    for candidate in candidates:
        if candidate.is_file():
            var loaded = tomllib.loads(candidate.read_text(encoding="utf-8"))
            var values = py_dict()
            flatten_strings_into(values, "", loaded)
            return values
    return py_dict()


def resolve_workspace_root(
    repo_root: PythonObject, manifest: PythonObject
) raises -> PythonObject:
    var os = Python.import_module("os")
    var pathlib = Python.import_module("pathlib")
    var re = Python.import_module("re")
    var override = os.environ.get("GUI_FOR_CLI_BUNDLE_WORKSPACE_ROOT")
    var bundle_id = py_str(manifest.get("id") or "bundle")
    var safe = py_str(re.sub(r"[^A-Za-z0-9_.-]+", "-", bundle_id).strip(".-"))
    if not safe:
        safe = "bundle"
    var root = (
        pathlib.Path(override).expanduser() if override else repo_root
        / "tmp"
        / "mojo-workspaces"
    )
    return (root / safe).resolve()


def load_bundle(
    bundle_arg: String, repo_root: PythonObject, locale: String
) raises -> PythonObject:
    var json = Python.import_module("json")
    var bundle_path = resolve_input_path(bundle_arg, repo_root)
    var loaded = load_manifest(bundle_path, repo_root)
    var bundle_root = loaded["root"]
    var manifest = loaded["manifest"]
    var pages = py_list()
    var pages_root = (bundle_root / "pages").resolve()
    for page_ref in items_or_empty(manifest.get("pages")):
        if builtins().isinstance(page_ref, builtins().str):
            var page_path = (pages_root / page_ref).resolve()
            if not page_path.is_relative_to(pages_root):
                raise Error("Page reference escapes bundle pages directory: " + py_str(page_ref))
            pages.append(json.loads(page_path.read_text(encoding="utf-8")))
        elif builtins().isinstance(page_ref, builtins().dict):
            pages.append(page_ref)
        else:
            raise Error("Unsupported page reference: " + py_str(page_ref))
    manifest["pages"] = pages
    var workspace_root = resolve_workspace_root(repo_root, manifest)
    workspace_root.mkdir(parents=True, exist_ok=True)

    var bundle = py_dict()
    bundle["repo_root"] = repo_root
    bundle["bundle_root"] = bundle_root
    bundle["workspace_root"] = workspace_root
    bundle["locale"] = locale
    bundle["manifest"] = manifest
    bundle["strings"] = load_strings(bundle_root, locale)
    bundle["display_name"] = text(
        bundle["strings"],
        manifest.get("displayName") or manifest.get("id") or "Bundle",
    )
    bundle["terminal_text_direction"] = py_str(
        manifest.get("terminalTextDirection") or "ltr"
    ).lower()
    bundle["rtl_layout"] = language_code(locale) in ("ar", "fa", "he", "ur")
    return bundle


def text(strings: PythonObject, key_or_text: PythonObject) raises -> String:
    var key = py_str(key_or_text or "")
    if not key:
        return ""
    return py_str(strings.get(key, key))


def all_controls(manifest: PythonObject) raises -> PythonObject:
    var controls = py_list()
    for page in items_or_empty(manifest.get("pages")):
        for section in items_or_empty(page.get("sections")):
            for control in items_or_empty(section.get("controls")):
                controls.append(control)
    return controls


def default_control_value(
    control: PythonObject, fallback: PythonObject
) raises -> PythonObject:
    if control.get("kind") == "dropdown":
        var options = items_or_empty(control.get("options"))
        for option in options:
            if option.get("selected"):
                return option.get("id", fallback)
        if options:
            return options[0].get("id", fallback)
    return fallback


def initial_field_values(manifest: PythonObject) raises -> PythonObject:
    var values = py_dict()
    for control in all_controls(manifest):
        var kind = control.get("kind")
        if (
            kind == "text"
            or kind == "path"
            or kind == "dropdown"
            or kind == "toggle"
        ):
            var control_id = py_str(control.get("id"))
            values[control_id] = control.get(
                "value",
                default_control_value(control, values.get(control_id, "")),
            )
    return values


def initial_checked_options(manifest: PythonObject) raises -> PythonObject:
    var values = py_dict()
    for control in all_controls(manifest):
        if control.get("kind") == "checkboxGroup":
            var selected = builtins().set()
            for option in items_or_empty(control.get("options")):
                if option.get("selected"):
                    selected.add(py_str(option.get("id")))
            values[py_str(control.get("id"))] = selected
    return values


def initial_config_values(manifest: PythonObject) raises -> PythonObject:
    var values = py_dict()
    for control in all_controls(manifest):
        if control.get("kind") == "configEditor":
            var control_id = py_str(control.get("id"))
            for setting in items_or_empty(control.get("settings")):
                var setting_id = py_str(setting.get("id"))
                values[control_id + "." + setting_id] = setting.get("value", "")
                if setting_id not in values:
                    values[setting_id] = setting.get("value", "")
    return values


def runtime_state(bundle: PythonObject) raises -> PythonObject:
    var state = py_dict()
    var manifest = bundle["manifest"]
    var pages = items_or_empty(manifest.get("pages"))
    state["field_values"] = initial_field_values(manifest)
    state["checked_options"] = initial_checked_options(manifest)
    state["config_values"] = initial_config_values(manifest)
    state["data_source_payloads"] = py_dict()
    state["data_source_errors"] = py_dict()
    state["selected_page_id"] = pages[0].get("id") if pages else Python.none()
    return state


def command_context(
    bundle: PythonObject,
    state: PythonObject,
    row_values: PythonObject,
    section_values: PythonObject,
) raises -> PythonObject:
    var os = Python.import_module("os")
    var fields = builtins().dict(state["field_values"])
    fields.update(section_values or py_dict())
    var configs = builtins().dict(state["config_values"])
    configs.update(state["field_values"])
    configs.update(section_values or py_dict())

    var context = py_dict()
    context["field_values"] = fields
    context["checked_options"] = state["checked_options"]
    context["config_values"] = configs
    context["row_values"] = row_values or py_dict()
    context["bundle_root_path"] = py_str(bundle["bundle_root"])
    context["bundle_workspace_path"] = py_str(bundle["workspace_root"])
    context["home_path"] = os.path.expanduser("~")
    context["file_state_values"] = py_dict()
    return context
