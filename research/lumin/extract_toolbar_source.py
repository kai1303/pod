#!/usr/bin/env python3
"""Inspect the downloaded viewer without executing vendor JavaScript or HTML."""
from collections import Counter
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent / "toolbar-source"
OUT = ROOT / "extracted"
OUT.mkdir(exist_ok=True)


class Capture(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack = []
        self.styles = []
        self.style = None
        self.fragments = {}
        self.active = None
        self.parts = []
        self.depth = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "style":
            self.style = []
        if attrs.get("id") in ("ToolbarInner", "leftSideBar") and self.active is None:
            self.active = attrs["id"]
            self.depth = len(self.stack)
            self.parts = []
        if self.active:
            self.parts.append(self.get_starttag_text())
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if self.active:
            self.parts.append(f"</{tag}>")
        if tag in self.stack:
            self.stack = self.stack[:len(self.stack) - 1 - self.stack[::-1].index(tag)]
        if self.active and len(self.stack) == self.depth:
            self.fragments[self.active] = "".join(self.parts)
            self.active = None
        if tag == "style" and self.style is not None:
            self.styles.append("".join(self.style))
            self.style = None

    def handle_data(self, data):
        if self.style is not None:
            self.style.append(data)
        if self.active:
            self.parts.append(data)

    def handle_entityref(self, name):
        self.handle_data(f"&{name};")

    def handle_charref(self, name):
        self.handle_data(f"&#{name};")


raw = ROOT / "markup.html"
capture = Capture()
capture.feed(raw.read_text())
assert "ToolbarInner" in capture.fragments, "Expected saved viewer toolbar"
for name, fragment in capture.fragments.items():
    # These fragments contain controls only; no document pages, account header or scripts.
    assert "<script" not in fragment
    (OUT / f"{name}.html").write_text(fragment)

styles = [(str(p.relative_to(ROOT)), p.read_text(errors="replace"))
          for p in sorted((ROOT / "markup_files").glob("*.css"))]
styles += [(f"markup.html:inline-style-{i}", s) for i, s in enumerate(capture.styles)]
(OUT / "inline-styles.css").write_text("\n".join(capture.styles))

# Retain each declaration's source and enclosing selector rather than flattening
# light/dark variants into a misleading single value. This is a lexical index,
# not a browser cascade evaluator; computed values live in lumin-observations.json.
tokens, glyphs, rules = [], {}, []
classes = set(re.findall(r'class="([^"]+)"', capture.fragments["ToolbarInner"]))
classes = {c for group in classes for c in group.split()}
for source, css in styles:
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        selector, body = match.groups()
        selector = selector.strip()
        for name, value in re.findall(r"(--kiwi-[\w-]+)\s*:\s*([^;}]+)", body):
            tokens.append({"name": name, "value": value.strip(), "selector": selector, "source": source})
        names = re.findall(r"\.((?:pdf-icon-|kiwi-icon-)[\w-]+)(?=::?before)", selector)
        content = re.search(r'content\s*:\s*[\"\']([^\"\']+)', body)
        if content:
            value = content.group(1)
            for name in names:
                glyphs.setdefault(name, {"content": value, "source": source})
        if "OrganizeToolbar" in selector or any(re.search(r"\." + re.escape(c) + r"(?![\w-])", selector) for c in classes):
            rules.append({"selector": selector, "declarations": body, "source": source})

js_source = ROOT / "markup_files/430os3-b8uoa3.js"
js = js_source.read_text()
enum = re.search(r'\{SQUIGGLY:"AnnotationCreateTextSquiggly".*?PAGE_NUMBERS:"PageNumbers"\}', js)
assert enum, "Expected toolbar tools enumeration"
tools = dict(re.findall(r'([A-Z_]+):"([^"]+)"', enum.group()))
styled = []
for path in sorted((ROOT / "markup_files").glob("*.js")):
    source = path.read_text(errors="replace")
    for match in re.finditer(r'componentId:"([^"]+)"\}\)\s*`([^`]+)`', source):
        component, template = match.groups()
        if component in classes or any(c.startswith(component + "-") for c in classes):
            styled.append({"component": component, "template": template,
                           "source": str(path.relative_to(ROOT))})
(OUT / "styled-toolbar-source.json").write_text(json.dumps(styled, indent=2) + "\n")
for name, value in (("css-token-declarations.json", tokens), ("icon-glyphs.json", glyphs),
                    ("toolbar-rules.json", rules), ("source-tools.json", tools)):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
(OUT / "toolbar-rules.css").write_text("\n".join(
    f"/* {r['source']} */\n{r['selector']} {{{r['declarations']}}}" for r in rules))

files = [raw, *sorted((ROOT / "markup_files").iterdir()), *sorted((ROOT / "assets").iterdir()),
         *sorted((ROOT / "brand").iterdir())]
manifest = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size,
             "sha256": sha256(p.read_bytes()).hexdigest()} for p in files if p.is_file()]
(OUT / "checksums.json").write_text(json.dumps(manifest, indent=2) + "\n")
summary = {"capture": "markup.html", "capture_bytes": raw.stat().st_size,
           "saved_resources": dict(Counter(p.suffix or "no extension" for p in (ROOT / "markup_files").iterdir())),
           "inline_styles": len(capture.styles), "token_declarations": len(tokens),
           "unique_tokens": len({t['name'] for t in tokens}), "icon_glyphs": len(glyphs),
           "toolbar_css_rules": len(rules), "source_tool_identifiers": len(tools),
           "styled_component_templates": len(styled),
           "method": "Lexical extraction of saved HTML/CSS/JS; no downloaded code executed"}
(OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
