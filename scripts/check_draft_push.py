#!/usr/bin/env python3
"""Interactive pre-push check for KB articles. No dependencies beyond Git/Python."""
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

FRONT_MATTER = re.compile(r"\A(?:\ufeff)?---\r?\n(?P<header>.*?)^(?:---|\.\.\.)[ \t]*\r?$", re.M | re.S)
DRAFT = re.compile(r'''^status:[ \t]*(?:"draft"|'draft'|draft)[ \t]*(?:\#[^\r\n]*)?\r?$''', re.M | re.I)


def git(*args, check=True):
    return subprocess.run(["git", *args], capture_output=True, check=check)


def draft_header(content):
    text = content.decode("utf-8-sig")
    match = FRONT_MATTER.search(text)
    return text, match if match and DRAFT.search(match["header"]) else None


def candidates(lines, remote):
    """Inspect final committed content for paths affected by each outgoing ref."""
    result = {}
    for line in lines:
        _, local, _, old = line.split()
        if set(local) == {"0"}:
            continue  # Ref deletion.
        commit = git("rev-parse", "--verify", f"{local}^{{commit}}", check=False)
        if commit.returncode:
            continue  # A tag pointing at something other than a commit.
        local = commit.stdout.decode().strip()
        if set(old) != {"0"} and git("cat-file", "-e", old, check=False).returncode == 0:
            names = git("diff", "--name-only", "--diff-filter=ACMRT", "-z", old, local, "--", "docs").stdout
        else:
            # A new ref: inspect commits not yet reachable on this remote.
            commits = git("rev-list", local, "--not", f"--remotes={remote}").stdout.splitlines()
            names = b"".join(git("diff-tree", "--root", "-m", "--no-commit-id", "--name-only", "-r", "-z", c.decode(), "--", "docs").stdout for c in commits)
        for raw in set(names.split(b"\0")) - {b""}:
            path = raw.decode("utf-8")
            if not path.endswith(".md"):
                continue
            blob = git("show", f"{local}:{path}", check=False)
            if blob.returncode:
                continue  # Deleted at the ref's final state.
            _, match = draft_header(blob.stdout)
            if match:
                result.setdefault(path, set()).add((local, blob.stdout))
    return result


def promote(drafts):
    root = Path(git("rev-parse", "--show-toplevel").stdout.decode().strip())
    head = git("rev-parse", "HEAD").stdout.decode().strip()
    user = git("config", "user.name", check=False).stdout.decode().strip()
    if not user:
        raise ValueError("Falta el nom d'usuari: configureu git config user.name abans de continuar.")
    updates = []
    for path, versions in sorted(drafts.items()):
        file = root / path
        if len(versions) != 1:
            raise ValueError(f"{path!r} té versions diferents en diverses referències; canvieu-les manualment.")
        commit, content = next(iter(versions))
        index = git("show", f":{path}", check=False)
        if (commit != head or file.is_symlink() or not file.is_file()
                or not file.resolve().is_relative_to(root)
                or file.read_bytes() != content or index.returncode or index.stdout != content):
            raise ValueError(f"No es modifica {path!r}: no correspon a HEAD o té canvis pendents. Feu el canvi manualment.")
        text, match = draft_header(content)
        header = match["header"]
        newline = "\r\n" if "\r\n" in header else "\n"
        fields = {
            "status": "active",
            "reviewed_by": user,
            "owner": "Equip de Tecnologia de L'Energètica",
            "review_date": datetime.date.today().isoformat(),
        }
        for key, value in fields.items():
            pattern = re.compile(rf"^{key}:[^\r\n]*", re.M)
            if len(pattern.findall(header)) > 1:
                raise ValueError(f"Camp duplicat {key!r} a {path!r}; corregiu-lo manualment.")
            replacement = f"{key}: {json.dumps(value, ensure_ascii=False)}"
            if pattern.search(header):
                header = pattern.sub(lambda _: replacement, header)
            else:
                header += replacement + newline
        updated = text[:match.start("header")] + header + text[match.end("header"):]
        if content.startswith(b"\xef\xbb\xbf"):
            updated = "\ufeff" + updated
        updates.append((file, updated.encode("utf-8")))
    # Check every file before writing any of them. Neither index nor commits change.
    for file, content in updates:
        file.write_bytes(content)
    print("Documents passats a active. Reviseu els canvis, feu git add i git commit, i repetiu git push.", file=sys.stderr)


def main():
    try:
        remote = sys.argv[1] if len(sys.argv) > 1 else "origin"
        drafts = candidates(sys.stdin, remote)
        if not drafts:
            return 0
        print("El push inclou documents amb status draft:", file=sys.stderr)
        for path in sorted(drafts):
            print(f"  {path!r}", file=sys.stderr)
        try:
            # Git uses stdin for ref updates; read the answer from the controlling
            # terminal. Separate streams avoid r+ requiring a seekable device.
            with open("/dev/tty", "r", encoding="utf-8") as terminal_input:
                with open("/dev/tty", "w", encoding="utf-8", buffering=1) as terminal_output:
                    terminal_output.write("Voleu canviar-los a active? [s] Sí (atura el push) / [n] No, enviar com a draft / [c] Cancel·lar [c]: ")
                    terminal_output.flush()
                    answer = terminal_input.readline().strip().lower()
        except OSError as error:
            print("Cal respondre des d'un terminal interactiu. Repetiu git push al terminal per decidir si voleu passar-los a active o enviar-los com a draft.", file=sys.stderr)
            print(f"Detall de l'error del terminal: {error}", file=sys.stderr)
            return 1
        if answer in {"n", "no"}:
            print("S'envien els documents com a draft per decisió de l'usuari.", file=sys.stderr)
            return 0
        if answer in {"s", "si", "sí"}:
            promote(drafts)
        else:
            print("Push cancel·lat; no s'ha modificat cap document.", file=sys.stderr)
        return 1
    except (ValueError, OSError, UnicodeError, subprocess.CalledProcessError) as error:
        print(f"No es pot completar la comprovació de drafts: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
