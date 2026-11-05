#!/usr/bin/env python3
"""Exercise pre-push decisions with disposable local Git repositories only."""
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("draft_push", ROOT / "scripts/check_draft_push.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class Terminal:
    def __init__(self, answer):
        self.answer = answer
    def write(self, text):
        return len(text)
    def readline(self):
        return self.answer + "\n"
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False


class PushTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cwd = Path.cwd()
        self.addCleanup(os.chdir, self.cwd)
        self.repo = Path(self.temp.name) / "repo"
        self.remote = Path(self.temp.name) / "remote.git"
        self.repo.mkdir()
        os.chdir(self.repo)
        self.env = patch.dict(os.environ, {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.git("init", "--bare", str(self.remote))
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Test User")
        self.git("config", "user.email", "test@example.invalid")
        self.git("remote", "add", "origin", str(self.remote))
        Path("docs").mkdir()
        Path("docs/existing.md").write_text('---\nstatus: "draft"\n---\nExisting draft\n')
        self.commit("base")
        self.git("push", "-u", "origin", "main")
        self.base = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.path = Path("docs/new article.md")
        self.original = ('---\nauthor: "Original Author"\nreviewed_by: "Previous Editor"\n'
                         'status: "draft"\ncreation_date: "2026-01-01"\nreview_date: "2026-01-01"\n'
                         'review_after_months: 60\n---\nArticle body\n')
        self.path.write_text(self.original)
        self.commit("new article")
        self.head = self.git("rev-parse", "HEAD").stdout.decode().strip()

    def git(self, *args):
        return subprocess.run(["git", *args], capture_output=True, check=True)

    def commit(self, message):
        self.git("add", "--all")
        self.git("commit", "-m", message)

    def protocol(self, old=None):
        return f"refs/heads/main {self.head} refs/heads/main {self.base if old is None else old}\n"

    def invoke(self, answer=None, old=None):
        with patch.object(sys, "stdin", io.StringIO(self.protocol(old))), patch.object(sys, "argv", ["hook", "origin"]), patch.object(sys, "stderr", io.StringIO()):
            if answer is None:
                with patch("builtins.open", side_effect=OSError("no terminal")):
                    return hook.main()
            with patch("builtins.open", return_value=Terminal(answer)):
                return hook.main()

    def test_new_ref_checks_only_outgoing_drafts(self):
        drafts = hook.candidates(io.StringIO(self.protocol("0" * 40)), "origin")
        self.assertEqual(set(drafts), {str(self.path)})

    def test_promote_stops_push_and_updates_only_working_tree(self):
        self.assertEqual(self.invoke("s"), 1)
        text = self.path.read_text()
        self.assertIn('status: "active"', text)
        self.assertIn('reviewed_by: "Test User"', text)
        self.assertIn('author: "Original Author"', text)
        self.assertIn('creation_date: "2026-01-01"', text)
        self.assertTrue(text.endswith("Article body\n"))
        self.assertEqual(self.git("show", f":{self.path}").stdout.decode(), self.original)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.decode().strip(), self.head)

    def test_no_allows_draft_without_changes(self):
        self.assertEqual(self.invoke("n"), 0)
        self.assertEqual(self.path.read_text(), self.original)

    def test_cancel_preserves_file(self):
        self.assertEqual(self.invoke("c"), 1)
        self.assertEqual(self.path.read_text(), self.original)

    def test_no_terminal_blocks_draft_push(self):
        self.assertEqual(self.invoke(), 1)

    def test_dirty_file_is_not_overwritten(self):
        dirty = self.original + "Uncommitted edit\n"
        self.path.write_text(dirty)
        self.assertEqual(self.invoke("s"), 1)
        self.assertEqual(self.path.read_text(), dirty)

    def test_dirty_index_is_not_overwritten(self):
        self.path.write_text(self.original + "Staged edit\n")
        self.git("add", "--", str(self.path))
        self.path.write_text(self.original)
        self.assertEqual(self.invoke("s"), 1)
        self.assertIn(b"Staged edit", self.git("show", f":{self.path}").stdout)

    def test_final_active_version_is_not_flagged(self):
        self.path.write_text(self.original.replace('"draft"', '"active"'))
        self.commit("activate")
        self.head = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.assertEqual(self.invoke(), 0)

    def test_deletion_is_ignored(self):
        protocol = f"(delete) {'0' * 40} refs/heads/main {self.head}\n"
        self.assertEqual(hook.candidates(io.StringIO(protocol), "origin"), {})

    def test_actual_git_push_executes_hook(self):
        (self.repo / ".githooks").mkdir()
        (self.repo / "scripts").mkdir()
        shutil.copy2(ROOT / ".githooks/pre-push", self.repo / ".githooks/pre-push")
        shutil.copy2(ROOT / "scripts/check_draft_push.py", self.repo / "scripts/check_draft_push.py")
        self.git("config", "core.hooksPath", ".githooks")
        result = subprocess.run(["git", "push", "origin", "main"], capture_output=True, start_new_session=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"terminal interactiu", result.stderr)
        remote_head = self.git("--git-dir", str(self.remote), "rev-parse", "refs/heads/main").stdout.decode().strip()
        self.assertEqual(remote_head, self.base)


if __name__ == "__main__":
    unittest.main()
