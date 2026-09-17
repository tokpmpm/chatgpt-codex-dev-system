import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import runner as core
from entrypoint import (
    HardenedPromptBuilder,
    StrictRunLedger,
    guard_expected_repo,
    normalize_adapter_defaults,
)


class PromptRepo:
    def __init__(self, root):
        self.root = root
    def branch(self): return "feature/7-dark-mode"
    def merge_base(self, base, sha): return "0" * 40
    def remote_repo(self): return "acme/product"


class LedgerRepo:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / ".git").mkdir()
    def git(self, *args):
        if args == ("rev-parse", "--git-dir"):
            return ".git"
        raise AssertionError(args)
    def branch(self): return "feature/7-dark-mode"


class LedgerGitHub:
    repo_full_name = "acme/product"
    def __init__(self): self.comments_data = []
    def comment(self, issue, body): self.comments_data.append((issue, body))
    def _gh(self, *args): return '[{"number": 42}]'


class StartRepo:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "AGENTS.md").write_text("rules", encoding="utf-8")
        self._dirty = False
        self._branch = "feature/999-wrong"
        self._head = "a" * 40
    def ensure_clean(self):
        if self._dirty: raise core.GuardError("dirty")
    def ensure_issue_branch(self, issue, title, base):
        if not self._branch.startswith(f"feature/{issue}-"):
            raise core.GuardError("wrong branch")
    def head(self): return self._head


class IssueGitHub:
    def issue(self, n): return {"number": n, "title": "Task", "body": "AC", "state": "OPEN"}


class NeverAdapter:
    provider = "fake"
    model = "fake"
    def __init__(self): self.calls = 0
    def run(self, prompt, cwd):
        self.calls += 1
        return core.ModelResult(True, "unexpected")


class ContractTests(unittest.TestCase):
    def test_prompt_contains_explicit_repo_branch_base_and_input_sha(self):
        root = Path(tempfile.mkdtemp())
        (root / "AGENTS.md").write_text("rules", encoding="utf-8")
        repo = PromptRepo(root)
        cfg = core.Config()
        builder = HardenedPromptBuilder(root, repo, cfg)
        sha = "a" * 40
        text = builder.developer({"number": 7, "title": "Task", "body": "AC"}, sha)
        self.assertIn("REPOSITORY: acme/product", text)
        self.assertIn("BRANCH: feature/7-dark-mode", text)
        self.assertIn("BASE_BRANCH: main", text)
        self.assertIn(f"BASE_SHA: {'0' * 40}", text)
        self.assertIn(f"INPUT_SHA: {sha}", text)

    def test_direct_entrypoint_normalizes_core_codex_defaults(self):
        cfg = normalize_adapter_defaults(core.Config())
        self.assertEqual(cfg.developer_command[:4], ["codex", "--ask-for-approval", "never", "exec"])
        self.assertIn("workspace-write", cfg.developer_command)
        self.assertIn("read-only", cfg.reviewer_command)
        self.assertIn("read-only", cfg.planner_command)

    def test_expected_repo_mismatch_blocks(self):
        with patch.dict(os.environ, {"AI_DEV_EXPECTED_REPO": "acme/expected"}, clear=False):
            with self.assertRaises(core.GuardError):
                guard_expected_repo("acme/wrong")

    def test_audit_record_contains_pr_branch_prompt_hash_and_input_sha(self):
        repo = LedgerRepo()
        gh = LedgerGitHub()
        ledger = StrictRunLedger(repo, gh)
        sha = "a" * 40
        run_id = ledger.record(
            role="DEVELOPER", issue=7, input_sha=sha, prompt="hello",
            provider="fake", model="fake", status="SUCCESS", result_summary="ok"
        )
        data = json.loads((ledger.dir / f"{run_id}.json").read_text(encoding="utf-8"))
        self.assertEqual(data["PR"], "42")
        self.assertEqual(data["BRANCH"], "feature/7-dark-mode")
        self.assertEqual(data["INPUT_SHA"], sha)
        self.assertEqual(len(data["PROMPT_SHA256"]), 64)
        self.assertTrue(any("AI_DEV_AUDIT_CONFIRMED" in body for _, body in gh.comments_data))

    def test_wrong_branch_blocks_before_developer_model(self):
        repo = StartRepo()
        dev = NeverAdapter()
        eng = core.WorkflowEngine(
            repo, IssueGitHub(), core.PromptBuilder(repo.root), dev, NeverAdapter(), NeverAdapter(), core.Config(), None
        )
        with self.assertRaises(core.GuardError):
            eng.start(7)
        self.assertEqual(dev.calls, 0)

    def test_dirty_start_blocks_before_developer_model(self):
        repo = StartRepo()
        repo._branch = "feature/7-task"
        repo._dirty = True
        dev = NeverAdapter()
        eng = core.WorkflowEngine(
            repo, IssueGitHub(), core.PromptBuilder(repo.root), dev, NeverAdapter(), NeverAdapter(), core.Config(), None
        )
        with self.assertRaises(core.GuardError):
            eng.start(7)
        self.assertEqual(dev.calls, 0)


if __name__ == "__main__":
    unittest.main()
