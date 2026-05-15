from std.python import Python, PythonObject

from gfc_common import (
    builtins,
    items_or_empty,
    py_bool,
    py_dict,
    py_list,
    py_str,
)


def checked_options_value(value: PythonObject) raises -> String:
    if value is None:
        return ""
    if (
        builtins().isinstance(value, builtins().set)
        or builtins().isinstance(value, builtins().list)
        or builtins().isinstance(value, builtins().tuple)
    ):
        var parts = py_list()
        for item in value:
            var item_text = py_str(item).strip()
            if item_text:
                parts.append(item_text)
        return py_str(builtins().str(",").join(builtins().sorted(parts)))
    return py_str(value)


def computed_file_state_value(
    context: PythonObject, placeholder: PythonObject
) raises -> PythonObject:
    if (
        context["file_state_values"]
        and placeholder in context["file_state_values"]
    ):
        return builtins().str(context["file_state_values"][placeholder])
    if "." not in placeholder:
        return Python.none()
    var parts = placeholder.rsplit(".", 1)
    var field_id = parts[0]
    var prop = parts[1]
    var raw_path = context["field_values"].get(field_id) or context[
        "config_values"
    ].get(field_id)
    if prop == "pathExtension":
        var pathlib = Python.import_module("pathlib")
        var name = pathlib.PurePath(py_str(raw_path or "")).name
        if "." in name:
            return name.rsplit(".", 1)[1].lower()
        return ""
    return Python.none()


def context_value(
    context: PythonObject, placeholder: PythonObject
) raises -> PythonObject:
    if placeholder == "bundleRoot":
        return context["bundle_root_path"]
    if placeholder == "bundleWorkspace":
        return context["bundle_workspace_path"]
    if placeholder == "home":
        return context["home_path"]
    if placeholder.startswith("row."):
        return context["row_values"].get(placeholder[4:])
    if placeholder.startswith("config."):
        return context["config_values"].get(placeholder[7:])
    var computed = computed_file_state_value(context, placeholder)
    if computed is not None:
        return computed
    if placeholder in context["row_values"]:
        return context["row_values"][placeholder]
    if placeholder in context["checked_options"]:
        return checked_options_value(context["checked_options"][placeholder])
    if placeholder in context["field_values"]:
        return context["field_values"][placeholder]
    return context["config_values"].get(placeholder)


def interpolate(value: PythonObject, context: PythonObject) raises -> String:
    var re = Python.import_module("re")
    var rendered = py_str(value or "")
    for placeholder_match in re.finditer("\\{\\{([^}]+)\\}\\}", rendered):
        var placeholder = placeholder_match.group(1).strip()
        var replacement = py_str(context_value(context, placeholder) or "")
        rendered = rendered.replace(
            py_str(placeholder_match.group(0)), replacement
        )
    return rendered


def placeholders_in(values: PythonObject) raises -> PythonObject:
    var re = Python.import_module("re")
    var found = py_list()
    for value in values:
        for placeholder_match in re.finditer(
            "\\{\\{([^}]+)\\}\\}", py_str(value or "")
        ):
            var placeholder = placeholder_match.group(1).strip()
            if placeholder not in found:
                found.append(placeholder)
    return found


def missing_required_placeholders(
    values: PythonObject, context: PythonObject
) raises -> PythonObject:
    var missing = py_list()
    for placeholder in placeholders_in(values):
        if not py_str(context_value(context, placeholder) or "").strip():
            missing.append(placeholder)
    return missing


def missing_placeholders(
    command: PythonObject, context: PythonObject
) raises -> PythonObject:
    var values = py_list()
    values.append(command.get("executable"))
    for arg in items_or_empty(command.get("arguments")):
        values.append(arg)
    return missing_required_placeholders(values, context)


def rendered_command(
    command: PythonObject, context: PythonObject
) raises -> PythonObject:
    var optional = py_list()
    for group in items_or_empty(command.get("optionalArguments")):
        if not missing_required_placeholders(group, context):
            for item in group:
                optional.append(interpolate(item, context))
    var arguments = py_list()
    for item in items_or_empty(command.get("arguments")):
        arguments.append(interpolate(item, context))
    arguments.extend(optional)
    var rendered = py_dict()
    rendered["executable"] = interpolate(command.get("executable"), context)
    rendered["arguments"] = arguments
    return rendered


def shell_quote(value: PythonObject) raises -> String:
    var re = Python.import_module("re")
    var shlex = Python.import_module("shlex")
    var text = py_str(value or "")
    if re.fullmatch(r"[A-Za-z0-9_./-]+", text):
        return text
    return py_str(shlex.quote(text))


def display_command(
    command: PythonObject, context: PythonObject
) raises -> String:
    var rendered = rendered_command(command, context)
    var pieces = py_list()
    pieces.append(shell_quote(rendered["executable"]))
    for arg in rendered["arguments"]:
        pieces.append(shell_quote(arg))
    return py_str(builtins().str(" ").join(pieces))


def compare_numeric(
    left: PythonObject, right: PythonObject, op: String
) raises -> Bool:
    try:
        var left_value = builtins().float(left)
        var right_value = builtins().float(right)
        if op == "lessThan":
            return py_bool(left_value < right_value)
        if op == "lessThanOrEqual":
            return py_bool(left_value <= right_value)
        if op == "greaterThan":
            return py_bool(left_value > right_value)
        if op == "greaterThanOrEqual":
            return py_bool(left_value >= right_value)
    except e:
        return False
    return False


def condition_matches(
    condition: PythonObject, context: PythonObject
) raises -> Bool:
    var value = (
        builtins()
        .str(
            context_value(
                context, builtins().str(condition.get("placeholder") or "")
            )
            or ""
        )
        .strip()
    )
    if "exists" in condition and py_bool(condition["exists"]) != py_bool(value):
        return False
    if "equals" in condition and value != interpolate(
        condition["equals"], context
    ):
        return False
    if "notEquals" in condition and value == interpolate(
        condition["notEquals"], context
    ):
        return False
    if condition.get("in"):
        var matched = False
        for item in items_or_empty(condition.get("in")):
            if value == interpolate(item, context):
                matched = True
        if not matched:
            return False
    for item in items_or_empty(condition.get("notIn")):
        if value == interpolate(item, context):
            return False
    var comparison_keys = py_list()
    comparison_keys.append("lessThan")
    comparison_keys.append("lessThanOrEqual")
    comparison_keys.append("greaterThan")
    comparison_keys.append("greaterThanOrEqual")
    for key in comparison_keys:
        if key in condition and not compare_numeric(
            value, interpolate(condition[key], context), py_str(key)
        ):
            return False
    return True


def is_action_visible(
    action: PythonObject, context: PythonObject
) raises -> Bool:
    for condition in items_or_empty(action.get("visibleWhen")):
        if not condition_matches(condition, context):
            return False
    return True


def disabled_reason(
    action: PythonObject,
    context: PythonObject,
    fallback: String,
    placeholder_labels: PythonObject,
) raises -> PythonObject:
    for condition in items_or_empty(action.get("disabledWhen")):
        if condition_matches(condition, context):
            return interpolate(
                action.get("disabledTooltip") or fallback, context
            )
    var missing = missing_placeholders(
        action.get("command") or py_dict(), context
    )
    if missing:
        var labels = py_list()
        for placeholder in missing:
            labels.append(
                py_str(placeholder_labels.get(placeholder, placeholder))
            )
        return "Required: " + py_str(builtins().str(", ").join(labels))
    return Python.none()
