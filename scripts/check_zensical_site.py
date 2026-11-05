#!/usr/bin/env python3
"""Check the built KB's navigation, custom metadata and native search/diagrams."""
from html.parser import HTMLParser
import json
import re
from pathlib import Path
import sys
import tomllib
from urllib.parse import unquote, urlsplit

import yaml

ROOT = Path(__file__).resolve().parents[1]


class Page(HTMLParser):
    def __init__(self, content):
        super().__init__()
        self.meta = {}
        self.styles = []
        self.scripts = []
        self.lang = None
        self.diagrams = 0
        self.main_headings = 0
        self.heading_levels = []
        self.ids = set()
        self.article_links = []
        self.in_article = False
        self.feed(content)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "article":
            self.in_article = True
        if self.in_article:
            if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
                self.heading_levels.append(int(tag[1]))
                if tag == "h1":
                    self.main_headings += 1
            if tag in ("a", "img"):
                self.article_links.append(attrs.get("href") if tag == "a" else attrs.get("src"))
            if tag == "img" and not attrs.get("alt", "").strip():
                raise ValueError("Hi ha una imatge de contingut sense text alternatiu.")
        if tag == "html":
            self.lang = attrs.get("lang")
        if tag == "meta" and "name" in attrs:
            self.meta[attrs["name"]] = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "stylesheet":
            self.styles.append(attrs.get("href", ""))
        if tag == "script" and "src" in attrs:
            self.scripts.append(attrs["src"])
        if tag == "pre" and "mermaid" in attrs.get("class", "").split():
            self.diagrams += 1

    def handle_endtag(self, tag):
        if tag == "article":
            self.in_article = False


def source_heading_count(body):
    """Ignore fenced examples, including shorter fences inside Markdown demos."""
    fence = None
    count = 0
    for line in body.splitlines():
        marker = re.match(r"^[ \t]*(`{3,}|~{3,})(.*)$", line)
        if marker:
            token, rest = marker.groups()
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence) and not rest.strip():
                fence = None
        elif fence is None and re.match(r"^# ", line):
            count += 1
    if fence is not None:
        raise ValueError("Hi ha un bloc de codi sense tancar.")
    return count


def nav_paths(value):
    if isinstance(value, str):
        if value.endswith(".md"):
            yield value
    elif isinstance(value, list):
        for child in value:
            yield from nav_paths(child)
    elif isinstance(value, dict):
        for child in value.values():
            yield from nav_paths(child)


def main():
    config = tomllib.loads((ROOT / "zensical.toml").read_text())["project"]
    docs = ROOT / config["docs_dir"]
    site = ROOT / config["site_dir"]
    if not (site / "index.html").is_file():
        raise ValueError("Primer executeu zensical build --clean.")
    if config["theme"]["variant"] != "modern":
        raise ValueError("La KB ha d'utilitzar el tema modern.")
    for readme in docs.rglob("README.md"):
        if readme.with_name("index.md").exists():
            raise ValueError(f"README.md i index.md coincideixen a {readme.parent}.")
    pages = {}
    outputs = {}
    for source in docs.rglob("*.md"):
        relative = source.relative_to(docs)
        output = relative.with_name("index.md") if relative.name in ("index.md", "README.md") else relative.with_suffix("") / "index.md"
        target = site / output.with_suffix(".html")
        if not target.is_file():
            raise ValueError(f"No s'ha generat {relative}.")
        page = Page(target.read_text())
        pages[str(relative)] = page
        outputs[target.resolve()] = page
        if page.main_headings != 1:
            raise ValueError(f"Cal un únic h1 a {relative}.")
        if any(current > previous + 1 for previous, current in zip(page.heading_levels, page.heading_levels[1:])):
            raise ValueError(f"Hi ha un salt de nivell de títol a {relative}.")
        if page.lang != "ca" or not any("/modern/" in path for path in page.styles):
            raise ValueError(f"Llengua o tema incorrectes a {relative}.")
        if not page.meta.get("generator", "").startswith("zensical-"):
            raise ValueError(f"Generador incorrecte a {relative}.")
        text = source.read_text()
        metadata = yaml.safe_load(text.split("---", 2)[1]) if text.startswith("---\n") else {}
        body = text.split("---", 2)[2] if text.startswith("---\n") else text
        if source_heading_count(body) != 1:
            raise ValueError(f"Cal un únic títol # explícit al Markdown de {relative}.")
        for key in ("status", "review_date", "review_after_months"):
            expected = metadata.get(key)
            if key == "review_after_months" and expected is None:
                expected = metadata.get("review_period_months")
            if expected is not None and page.meta.get(key) != str(expected):
                raise ValueError(f"Metadada {key} incorrecta a {relative}.")
        if not any(path.endswith("status-warning.js") for path in page.scripts):
            raise ValueError(f"Falta l'script d'avisos a {relative}.")
        if any("mermaid-init" in path or "unpkg.com/mermaid" in path for path in page.scripts):
            raise ValueError(f"Inicialització duplicada de Mermaid a {relative}.")
    for output, page in outputs.items():
        for link in page.article_links:
            if not link:
                continue
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            target = (output.parent / unquote(url.path)).resolve() if url.path else output
            if target.is_dir():
                target = target / "index.html"
            if not target.is_relative_to(site.resolve()) or not target.is_file():
                raise ValueError(f"Enllaç intern invàlid a {output.relative_to(site.resolve())}: {link}")
            if url.fragment and target in outputs and unquote(url.fragment) not in outputs[target].ids:
                raise ValueError(f"Fragment inexistent a {output.relative_to(site.resolve())}: {link}")
    for path in nav_paths(config["nav"]):
        if path not in pages:
            raise ValueError(f"Entrada de navegació sense pàgina: {path}.")
    index = pages["index.md"]
    if not index.diagrams:
        raise ValueError("No s'han generat els blocs Mermaid de la guia.")
    search = json.loads((site / "search.json").read_text())
    if search["config"]["lang"] != ["ca"] or not search["items"]:
        raise ValueError("L'índex de cerca en català és buit o incorrecte.")
    if not any("restaurar" in item["title"].lower() for item in search["items"]):
        raise ValueError("La cerca no inclou el procediment de restauració.")
    print(f"OK: {len(pages)} pàgines, títols, enllaços interns, imatges, metadades, tema modern, cerca en català i Mermaid natiu.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
