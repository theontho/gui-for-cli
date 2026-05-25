#!/usr/bin/env python3
"""Build the static project site from Markdown sources."""

from __future__ import annotations

import html
import json
import re
import shlex
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "site_src"
OUTPUT_DIR = ROOT / "site"
BASE_URL = "https://theontho.github.io/gui-for-cli"
GITHUB_URL = "https://github.com/theontho/gui-for-cli"

NAV_ITEMS = (
    ("index.html", "Home"),
    ("frontends.html", "Frontends"),
    ("experiments.html", "Experiments"),
    ("wgsextract.html", "WGSExtract"),
    ("docs.html", "Docs"),
)


@dataclass(frozen=True)
class Page:
    source: Path
    output_name: str
    title: str
    description: str
    eyebrow: str
    heading: str
    lede: str
    footer_title: str
    footer_text: str
    body: str
    actions: tuple[tuple[str, str, str], ...]
    auto_hero: bool


def main() -> None:
    if not SOURCE_DIR.is_dir():
        raise SystemExit(f"Missing site source directory: {SOURCE_DIR}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / ".nojekyll").write_text("", encoding="utf-8")
    for source in sorted(SOURCE_DIR.glob("*.md")):
        page = load_page(source)
        (OUTPUT_DIR / page.output_name).write_text(render_page(page), encoding="utf-8")


def load_page(source: Path) -> Page:
    metadata, body = parse_front_matter(source.read_text(encoding="utf-8"))
    return Page(
        source=source,
        output_name=require(metadata, "output"),
        title=require(metadata, "title"),
        description=require(metadata, "description"),
        eyebrow=require(metadata, "eyebrow"),
        heading=require(metadata, "heading"),
        lede=require(metadata, "lede"),
        footer_title=metadata.get("footer_title", "GUI for CLI"),
        footer_text=metadata.get(
            "footer_text",
            "Turn CLI bundles into desktop apps without rewriting the tool.",
        ),
        actions=parse_actions(metadata.get("actions", "")),
        auto_hero=parse_bool(metadata.get("auto_hero", "true"), source, "auto_hero"),
        body=body,
    )


def parse_front_matter(text: str) -> tuple[dict[str, str], str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("Markdown source must start with front matter")

    metadata: dict[str, str] = {}
    index = 1
    while index < len(lines):
        line = lines[index]
        index += 1
        if line.strip() == "---":
            break
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition(":")
        if not separator:
            raise ValueError(f"Invalid front matter line: {line}")
        metadata[key.strip()] = unquote_scalar(value.strip())
    else:
        raise ValueError("Unterminated front matter")

    return metadata, "\n".join(lines[index:]).strip()


def unquote_scalar(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            return json.loads(value)
        except json.JSONDecodeError as error:
            raise ValueError(f"Invalid double-quoted scalar: {value}") from error
    return value


def require(metadata: dict[str, str], key: str) -> str:
    value = metadata.get(key, "")
    if not value:
        raise ValueError(f"Missing required front matter key: {key}")
    return value


def parse_bool(value: str, source: Path, key: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1", "yes", "on"}:
        return True
    if normalized in {"false", "0", "no", "off"}:
        return False
    relative = source.relative_to(ROOT)
    raise ValueError(f"{relative}: {key} must be a boolean value")


def parse_actions(value: str) -> tuple[tuple[str, str, str], ...]:
    if not value:
        return ()
    actions: list[tuple[str, str, str]] = []
    for item in value.split(";"):
        parts = [part.strip() for part in item.split("|")]
        if len(parts) not in {2, 3}:
            raise ValueError(f"Expected label|href or label|href|class action: {item}")
        label, href = parts[:2]
        css_class = parts[2] if len(parts) == 3 else ""
        actions.append((label, href, css_class))
    return tuple(actions)


def render_page(page: Page) -> str:
    canonical = (
        f"{BASE_URL}/"
        if page.output_name == "index.html"
        else f"{BASE_URL}/{page.output_name}"
    )
    body = MarkdownRenderer(page.body).render()
    hero = render_hero(page) if page.auto_hero else ""
    return "\n".join(
        [
            "<!doctype html>",
            '<html lang="en">',
            "  <head>",
            '    <meta charset="utf-8" />',
            '    <meta name="viewport" content="width=device-width, initial-scale=1" />',
            f'    <meta name="description" content="{escape_attr(page.description)}" />',
            f"    <title>{escape_text(page.title)}</title>",
            '    <meta property="og:site_name" content="GUI for CLI" />',
            '    <meta property="og:type" content="website" />',
            f'    <meta property="og:title" content="{escape_attr(page.title)}" />',
            f'    <meta property="og:description" content="{escape_attr(page.description)}" />',
            f'    <meta property="og:url" content="{escape_attr(canonical)}" />',
            f'    <link rel="canonical" href="{escape_attr(canonical)}" />',
            "    <link rel=\"icon\" href='data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text y=\".82em\" font-size=\"84\">%E2%8C%98</text></svg>' />",
            '    <link rel="stylesheet" href="assets/site.css" />',
            "  </head>",
            "  <body>",
            render_nav(page.output_name),
            "    <main>",
            hero,
            body,
            "    </main>",
            render_footer(page),
            "  </body>",
            "</html>",
            "",
        ]
    )


def render_nav(active_output: str) -> str:
    links = []
    for href, label in NAV_ITEMS:
        active = ' class="active"' if href == active_output else ""
        links.append(f'<a{active} href="{href}">{escape_text(label)}</a>')
    links.append(
        f'<a href="{GITHUB_URL}" target="_blank" rel="noopener noreferrer">GitHub</a>'
    )
    return "\n".join(
        [
            '    <nav class="nav" aria-label="Primary navigation">',
            '      <div class="wrap nav-inner">',
            '        <a class="brand" href="index.html"><span class="brand-mark" aria-hidden="true"></span><span>GUI for CLI</span></a>',
            f'        <div class="nav-links">{"".join(links)}</div>',
            "      </div>",
            "    </nav>",
        ]
    )


def render_hero(page: Page) -> str:
    actions = "".join(render_button(*action) for action in page.actions)
    action_block = f'\n          <div class="actions">{actions}</div>' if actions else ""
    return "\n".join(
        [
            '      <header class="page-hero">',
            '        <div class="wrap">',
            f'          <p class="eyebrow"><span class="pulse" aria-hidden="true"></span> {escape_text(page.eyebrow)}</p>',
            f"          <h1>{render_inline(page.heading)}</h1>",
            f'          <p class="lede">{render_inline(page.lede)}</p>{action_block}',
            "        </div>",
            "      </header>",
        ]
    )


def render_button(label: str, href: str, css_class: str = "") -> str:
    classes = "btn"
    if css_class:
        classes = f"{classes} {css_class}"
    return f'<a class="{escape_attr(classes)}" href="{escape_attr(href)}">{escape_text(label)}</a>'


def render_footer(page: Page) -> str:
    return "\n".join(
        [
            '    <footer class="footer">',
            '      <div class="wrap">',
            f"        <div><strong>{escape_text(page.footer_title)}</strong><p>{render_inline(page.footer_text)}</p></div>",
            f'        <p><a href="{GITHUB_URL}">Source on GitHub</a></p>',
            "      </div>",
            "    </footer>",
        ]
    )


class MarkdownRenderer:
    def __init__(self, markdown: str) -> None:
        self.lines = markdown.splitlines()
        self.index = 0
        self.output: list[str] = []
        self.paragraph: list[str] = []
        self.closers: list[str] = []

    def render(self) -> str:
        while self.index < len(self.lines):
            line = self.lines[self.index]
            stripped = line.strip()
            if not stripped:
                self.flush_paragraph()
                self.index += 1
            elif stripped == ":::":
                self.flush_paragraph()
                if not self.closers:
                    raise ValueError("Unexpected container close")
                self.output.append(self.closers.pop())
                self.index += 1
            elif stripped == "::: raw":
                self.flush_paragraph()
                self.output.append(self.read_raw_block())
            elif stripped.startswith(":::"):
                self.flush_paragraph()
                self.open_container(stripped[3:].strip())
                self.index += 1
            elif stripped.startswith("```"):
                self.flush_paragraph()
                self.output.append(self.read_code_block())
            elif heading := parse_heading(stripped):
                self.flush_paragraph()
                level, text = heading
                self.output.append(f"<h{level}>{render_inline(text)}</h{level}>")
                self.index += 1
            elif stripped.startswith("- "):
                self.flush_paragraph()
                self.output.append(self.read_list())
            elif is_table_start(self.lines, self.index):
                self.flush_paragraph()
                self.output.append(self.read_table())
            elif shortcode := render_shortcode(stripped):
                self.flush_paragraph()
                self.output.append(shortcode)
                self.index += 1
            elif is_raw_html(stripped):
                self.flush_paragraph()
                self.output.append(line)
                self.index += 1
            else:
                self.paragraph.append(stripped)
                self.index += 1

        self.flush_paragraph()
        if self.closers:
            raise ValueError("Unclosed containers in Markdown source")
        return "\n".join(self.output)

    def flush_paragraph(self) -> None:
        if self.paragraph:
            self.output.append(f"<p>{render_inline(' '.join(self.paragraph))}</p>")
            self.paragraph = []

    def open_container(self, spec: str) -> None:
        opener, closer = render_container(spec)
        self.output.append(opener)
        self.closers.append(closer)

    def read_raw_block(self) -> str:
        self.index += 1
        raw_lines: list[str] = []
        while self.index < len(self.lines):
            line = self.lines[self.index]
            self.index += 1
            if line.strip() == ":::":
                return "\n".join(raw_lines)
            raw_lines.append(line)
        raise ValueError("Unterminated raw block")

    def read_code_block(self) -> str:
        language = self.lines[self.index].strip()[3:].strip()
        self.index += 1
        code_lines: list[str] = []
        while self.index < len(self.lines):
            line = self.lines[self.index]
            self.index += 1
            if line.strip().startswith("```"):
                code = "\n".join(html.escape(item) for item in code_lines)
                return f'<pre data-language="{escape_attr(language)}"><code>{code}</code></pre>'
            code_lines.append(line)
        raise ValueError("Unterminated code block")

    def read_list(self) -> str:
        items: list[str] = []
        while self.index < len(self.lines):
            stripped = self.lines[self.index].strip()
            if not stripped.startswith("- "):
                break
            items.append(f"<li>{render_inline(stripped[2:].strip())}</li>")
            self.index += 1
        return "<ul>\n" + "\n".join(items) + "\n</ul>"

    def read_table(self) -> str:
        header = split_table_row(self.lines[self.index])
        self.index += 2
        rows: list[list[str]] = []
        while self.index < len(self.lines):
            stripped = self.lines[self.index].strip()
            if not stripped.startswith("|"):
                break
            rows.append(split_table_row(stripped))
            self.index += 1

        header_html = "".join(f"<th>{render_inline(cell)}</th>" for cell in header)
        row_html = "\n".join(
            "<tr>" + "".join(f"<td>{render_inline(cell)}</td>" for cell in row) + "</tr>"
            for row in rows
        )
        return (
            '<div class="table-wrap"><table>\n'
            f"<thead><tr>{header_html}</tr></thead>\n"
            f"<tbody>\n{row_html}\n</tbody>\n"
            "</table></div>"
        )


def parse_heading(line: str) -> tuple[int, str] | None:
    match = re.match(r"^(#{1,3})\s+(.+)$", line)
    if not match:
        return None
    return len(match.group(1)), match.group(2)


def is_table_start(lines: list[str], index: int) -> bool:
    if index + 1 >= len(lines):
        return False
    current = lines[index].strip()
    separator = lines[index + 1].strip()
    return current.startswith("|") and bool(re.match(r"^\|[\s:-]+\|", separator))


def split_table_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def is_raw_html(line: str) -> bool:
    return bool(re.match(r"^<[A-Za-z/!]", line)) and line.endswith(">")


def render_shortcode(line: str) -> str | None:
    match = re.match(r"^\{\{\s*([a-z-]+):\s*(.*?)\s*\}\}$", line)
    if not match:
        return None
    name, value = match.groups()
    if name == "kicker":
        return f'<div class="kicker">{render_inline(value)}</div>'
    if name == "tag":
        return f'<span class="tag">{render_inline(value)}</span>'
    if name == "button":
        label, href, css_class = parse_link_shortcode(value)
        return render_button(label, href, css_class)
    if name == "link":
        label, href, css_class = parse_link_shortcode(value)
        class_attr = f' class="{escape_attr(css_class)}"' if css_class else ""
        return f'<a{class_attr} href="{escape_attr(href)}">{escape_text(label)}</a>'
    raise ValueError(f"Unknown shortcode: {name}")


def parse_link_shortcode(value: str) -> tuple[str, str, str]:
    parts = [part.strip() for part in value.split("|")]
    if len(parts) not in {2, 3}:
        raise ValueError(f"Expected label|href or label|href|class: {value}")
    label, href = parts[:2]
    css_class = parts[2] if len(parts) == 3 else ""
    return label, href, css_class


def render_container(spec: str) -> tuple[str, str]:
    parts = shlex.split(spec)
    if not parts:
        raise ValueError("Empty container")
    name, values = parts[0], parts[1:]
    attrs = parse_attrs(values)
    if name == "section":
        id_attr = f' id="{escape_attr(attrs.pop("id"))}"' if "id" in attrs else ""
        return f"<section{id_attr}>", "</section>"
    if name == "wrap":
        return div_with_class("wrap", values, attrs)
    if name == "grid":
        return div_with_class("grid", values, attrs)
    if name == "card":
        return article_with_class("card", values, attrs)
    if name == "split":
        return div_with_class("wrap split", values, attrs)
    if name == "section-head":
        return div_with_class("section-head", values, attrs)
    if name == "timeline":
        return div_with_class("timeline", values, attrs)
    if name == "node":
        return div_with_class("node", values, attrs)
    if name == "callout":
        return div_with_class("callout", values, attrs)
    raise ValueError(f"Unknown container: {name}")


def parse_attrs(values: list[str]) -> dict[str, str]:
    attrs: dict[str, str] = {}
    remaining: list[str] = []
    for value in values:
        key, separator, attr_value = value.partition("=")
        if separator:
            attrs[key] = attr_value
        else:
            remaining.append(value)
    values[:] = remaining
    return attrs


def div_with_class(
    base_class: str, extra_classes: list[str], attrs: dict[str, str]
) -> tuple[str, str]:
    classes = " ".join([base_class, *extra_classes]).strip()
    attrs_text = render_attrs({"class": classes, **attrs})
    return f"<div{attrs_text}>", "</div>"


def article_with_class(
    base_class: str, extra_classes: list[str], attrs: dict[str, str]
) -> tuple[str, str]:
    classes = " ".join([base_class, *extra_classes]).strip()
    attrs_text = render_attrs({"class": classes, **attrs})
    return f"<article{attrs_text}>", "</article>"


def render_attrs(attrs: dict[str, str]) -> str:
    attrs = {key: value for key, value in attrs.items() if value}
    return "".join(f' {key}="{escape_attr(value)}"' for key, value in attrs.items())


def render_inline(text: str) -> str:
    tokens: list[str] = []

    def stash(token: str) -> str:
        tokens.append(token)
        return f"\0{len(tokens) - 1}\0"

    text = re.sub(r"`([^`]+)`", lambda m: stash(f"<code>{html.escape(m.group(1))}</code>"), text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)(\{([^}]+)\})?", replace_link, text)
    for index, token in enumerate(tokens):
        text = text.replace(f"\0{index}\0", token)
    return text


def replace_link(match: re.Match[str]) -> str:
    label = match.group(1)
    href = html.unescape(match.group(2))
    attrs = match.group(4) or ""
    classes = " ".join(part[1:] for part in attrs.split() if part.startswith("."))
    class_attr = f' class="{escape_attr(classes)}"' if classes else ""
    return f'<a{class_attr} href="{escape_attr(href)}">{label}</a>'


def escape_text(value: str) -> str:
    return html.escape(value, quote=False)


def escape_attr(value: str) -> str:
    return html.escape(value, quote=True)


if __name__ == "__main__":
    main()
