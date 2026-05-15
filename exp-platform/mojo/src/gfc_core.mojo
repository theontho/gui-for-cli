from std.python import Python, PythonObject

from gfc_bundle import all_controls, command_context, text
from gfc_common import builtins, items_or_empty, py_dict, py_list, py_str
from gfc_interpolation import (
    disabled_reason,
    display_command,
    is_action_visible,
)


def placeholder_labels(bundle: PythonObject) raises -> PythonObject:
    var labels = py_dict()
    for control in all_controls(bundle["manifest"]):
        var control_id = py_str(control.get("id") or "")
        if control_id:
            labels[control_id] = text(
                bundle["strings"], control.get("label") or control_id
            )
        if control.get("kind") == "configEditor":
            for setting in items_or_empty(control.get("settings")):
                var setting_id = py_str(setting.get("id") or "")
                if setting_id:
                    var label = text(
                        bundle["strings"], setting.get("label") or setting_id
                    )
                    labels[setting_id] = label
                    labels[control_id + "." + setting_id] = label
    return labels


def render_action(
    bundle: PythonObject, action: PythonObject, context: PythonObject
) raises -> PythonObject:
    var rendered = py_dict()
    var visible = is_action_visible(action, context)
    var command = action.get("command") or py_dict()
    var reason = disabled_reason(
        action,
        context,
        "This action is not available.",
        placeholder_labels(bundle),
    )
    rendered["id"] = py_str(action.get("id") or "action")
    rendered["title"] = text(
        bundle["strings"], action.get("title") or action.get("id") or "action"
    )
    rendered["visible"] = visible
    rendered["disabledReason"] = reason
    rendered["enabled"] = visible and reason is None
    rendered["commandDisplay"] = display_command(
        command, context
    ) if command else ""
    rendered["action"] = action
    return rendered


def action_key(section: PythonObject, action: PythonObject) raises -> String:
    return py_str(section.get("id")) + ":" + py_str(action.get("id"))


def hydrated_control(
    control: PythonObject, payload: PythonObject
) raises -> PythonObject:
    if not payload:
        return control
    var next_control = builtins().dict(control)
    if "options" in payload:
        next_control["options"] = payload["options"]
    if "rows" in payload:
        next_control["rows"] = payload["rows"]
        next_control["items"] = py_list()
    if "items" in payload:
        next_control["items"] = payload["items"]
    if "rowActions" in payload or "actions" in payload:
        next_control["rowActions"] = payload.get("rowActions") or payload.get(
            "actions"
        )
    return next_control


def hydrate_tag(tag: PythonObject, values: PythonObject) raises -> PythonObject:
    var hydrated = builtins().dict(tag)
    hydrated["id"] = interpolate_item(tag.get("id"), values)
    hydrated["title"] = interpolate_item(tag.get("title"), values)
    return hydrated


def merge_tags(
    first: PythonObject, second: PythonObject
) raises -> PythonObject:
    var seen = builtins().set()
    var merged = py_list()
    for tag in first:
        var title = py_str(builtins().str(tag.get("title") or "").strip())
        var key = py_str(tag.get("id") or "") + "|" + title
        if title and key not in seen:
            seen.add(key)
            merged.append(tag)
    for tag in second:
        var title = py_str(builtins().str(tag.get("title") or "").strip())
        var key = py_str(tag.get("id") or "") + "|" + title
        if title and key not in seen:
            seen.add(key)
            merged.append(tag)
    return merged


def interpolate_item(
    value: PythonObject, values: PythonObject
) raises -> String:
    var re = Python.import_module("re")
    var rendered = py_str(value or "")
    for placeholder_match in re.finditer("\\{\\{([^}]+)\\}\\}", rendered):
        var raw = placeholder_match.group(1).strip()
        var key = raw[5:] if raw.startswith("item.") else raw
        rendered = rendered.replace(
            py_str(placeholder_match.group(0)), py_str(values.get(key) or "")
        )
    return rendered


def non_empty(value: PythonObject) raises -> PythonObject:
    var text_value = py_str(value or "").strip()
    if text_value:
        return text_value
    return Python.none()


def hydrate_row(
    template: PythonObject, item: PythonObject, index: Int
) raises -> PythonObject:
    var values = builtins().dict(item)
    values.update(item.get("values") or py_dict())
    var fallback_id = py_str(values.get("id") or ("row-" + String(index + 1)))
    var row = py_dict()
    row["id"] = (
        non_empty(interpolate_item(template.get("id"), values)) or fallback_id
    )
    row["title"] = non_empty(
        interpolate_item(template.get("title"), values)
    ) or item.get("title")
    row["status"] = non_empty(
        interpolate_item(template.get("status"), values)
    ) or item.get("status")
    var row_values = py_dict()
    for key in template.get("values") or py_dict():
        row_values[key] = interpolate_item(template["values"][key], values)
    row["values"] = row_values
    var tags = py_list()
    for tag in items_or_empty(template.get("tags")):
        tags.append(hydrate_tag(tag, values))
    row["tags"] = merge_tags(tags, items_or_empty(item.get("tags")))
    var tooltip = non_empty(
        interpolate_item(template.get("tooltip"), values)
    ) or item.get("tooltip")
    if tooltip:
        row["tooltip"] = tooltip
    return row


def hydrated_rows(control: PythonObject) raises -> PythonObject:
    var items = items_or_empty(control.get("items"))
    if not items:
        return builtins().list(items_or_empty(control.get("rows")))
    var template = control.get("rowTemplate")
    if not template:
        template = py_dict()
        template["id"] = "{{id}}"
        template["title"] = "{{name}}"
        template["status"] = "{{status}}"
        template["tags"] = py_list()
        var values = py_dict()
        for column in items_or_empty(control.get("columns")):
            var column_id = py_str(column.get("id"))
            values[column_id] = "{{" + column_id + "}}"
        template["values"] = values
    var rows = py_list()
    var index = 0
    for item in items:
        rows.append(hydrate_row(template, item, index))
        index += 1
    return rows


def row_context(base: PythonObject, row: PythonObject) raises -> PythonObject:
    var row_values = builtins().dict(row.get("values") or py_dict())
    row_values["id"] = row.get("id")
    row_values["title"] = row.get("title") or row.get("id")
    if row.get("status") is not None:
        row_values["status"] = row.get("status")
    var context = builtins().dict(base)
    context["row_values"] = row_values
    return context


def build_core_state(
    bundle: PythonObject, state: PythonObject
) raises -> PythonObject:
    var action_states = py_dict()
    var row_action_states = py_dict()
    var pages = py_list()
    var control_count = 0
    var action_count = 0
    var base_context = command_context(bundle, state, py_dict(), py_dict())
    for page in items_or_empty(bundle["manifest"].get("pages")):
        var rendered_sections = py_list()
        for section in items_or_empty(page.get("sections")):
            var section_values = (
                state["data_source_payloads"].get(
                    "section:" + py_str(section.get("id"))
                )
                or py_dict()
            ).get("values") or py_dict()
            var section_context = command_context(
                bundle, state, py_dict(), section_values
            )
            var rendered_controls = py_list()
            for control in items_or_empty(section.get("controls")):
                control_count += 1
                var rendered_control = hydrated_control(
                    control,
                    state["data_source_payloads"].get(
                        "control:" + py_str(control.get("id"))
                    ),
                )
                rendered_controls.append(rendered_control)
                for row in hydrated_rows(rendered_control):
                    var states = py_list()
                    for row_action in items_or_empty(
                        rendered_control.get("rowActions")
                    ):
                        action_count += 1
                        states.append(
                            render_action(
                                bundle,
                                row_action,
                                row_context(base_context, row),
                            )
                        )
                    if states:
                        row_action_states[
                            py_str(control.get("id"))
                            + ":"
                            + py_str(row.get("id"))
                        ] = states
            var rendered_actions = py_list()
            for action in items_or_empty(section.get("actions")):
                action_count += 1
                var rendered = render_action(bundle, action, section_context)
                action_states[action_key(section, action)] = rendered
                rendered_actions.append(rendered)
            var rendered_section = builtins().dict(section)
            rendered_section["controls"] = rendered_controls
            rendered_section["actionStates"] = rendered_actions
            rendered_sections.append(rendered_section)
        var rendered_page = builtins().dict(page)
        rendered_page["sections"] = rendered_sections
        pages.append(rendered_page)

    var core = py_dict()
    core["pages"] = pages
    core["action_states"] = action_states
    core["row_action_states"] = row_action_states
    core["control_count"] = control_count
    core["action_count"] = action_count
    core["rtl_layout"] = bundle["rtl_layout"]
    core["terminal_text_direction"] = bundle["terminal_text_direction"]
    return core
