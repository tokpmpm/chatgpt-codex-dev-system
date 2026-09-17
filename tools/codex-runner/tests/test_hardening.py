import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runner import Config, GuardError, ModelResult, PromptBuilder, FakeLedger, ProviderError
from entrypoint import (
    GuardedDeveloperAdapter,
    HardenedWorkflowEngine,
    ValidatingPlannerAdapter,
)


ISSUE = {"number": 7, "title": "Persist dark mode", "body": "AC: toggle persists", "state": "OPEN"}
VALID_APPROVE = """REVIEW_MATRIX_BEGIN
Requirement | Real source/path | Positive evidence | Negative/guard evidence | Status
AC | x | yes | yes | PASS
REVIEW_MATRIX_END
REVIEW_RESULT_BEGIN
VERDICT: APPROVE
BLOCKER_COUNT: 0
REVIEW_RESULT_END"""


class FakeRepo:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "AGENTS.md").write_text("rules", encoding="utf-8")
        self._head = "a" * 40
        self._branch = "feature/7-dark-mode"
        self._dirty = False
        self.validation_runs = 0

    def ensure_clean(self):
        if self._dirty:
            raise GuardError("dirty")

    def head(self):
        return self._head

    def branch(self):
        return self._branch

    def merge_base(self, base, head):
        return "0" * 40

    def diff(self, base, head):
        return "diff --git a/x b/x\n+change"

    @contextmanager
    def detached_worktree(self, sha):
        d = Path(tempfile.mkdtemp())
        yield d


class FakeGitHub:
    def __init__(self):
        self.comments_data = []
        self.ci = {}
        self.wait_calls = 0

    def issue(self, n):
        return dict(ISSUE)

    def comment(self, n, body):
        self.comments_data.append({"body": body})

    def comments(self, n):
        return list(self.comments_data)

    def ci_status(self, sha, name):
        return self.ci.get(sha, "PASS")


class FakeAdapter:
    def __init__(self, outputs, mutate=None):
        self.outputs = list(outputs)
        self.calls = 0
        self.provider = "fake"
        self.model = "fake"
        self.mutate = mutate

    def run(self, prompt, cwd, timeout=3600):
        self.calls += 1
        if self.mutate:
            self.mutate()
        return self.outputs.pop(0)


class HardeningTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeRepo()
        self.gh = FakeGitHub()
        self.cfg = Config(ci_poll_seconds=0, ci_timeout_seconds=1)
        self.prompts = PromptBuilder(self.repo.root)
        self.ledger = FakeLedger()

    def engine(self, dev, rev, planner):
        return HardenedWorkflowEngine(
            self.repo, self.gh, self.prompts, dev, rev, planner, self.cfg, self.ledger
        )

    def test_review_dirty_guard_blocks_before_reviewer(self):
        self.repo._dirty = True
        rev = FakeAdapter([ModelResult(True, "unused")])
        eng = self.engine(FakeAdapter([]), rev, FakeAdapter([]))
        with self.assertRaises(GuardError):
            eng.review(7, self.repo.head())
        self.assertEqual(rev.calls, 0)

    def test_planner_dirty_guard_blocks_before_planner(self):
        self.repo._dirty = True
        planner = FakeAdapter([ModelResult(True, "unused")])
        eng = self.engine(FakeAdapter([]), FakeAdapter([]), planner)
        with self.assertRaises(GuardError):
            eng.create_repair_plan(7, self.repo.head(), "blocker")
        self.assertEqual(planner.calls, 0)

    def test_recovery_retries_fresh_reviewer_same_sha(self):
        sha = self.repo.head()
        self.gh.ci[sha] = "PASS"
        self.gh.comments_data.append({
            "body": f"AI_DEV_RUN_RECORD\nROLE: REVIEWER\nSTATUS: REVIEW_ERROR\nINPUT_SHA: {sha}"
        })
        rev = FakeAdapter([
            ModelResult(False, "", 1, "provider error"),
            ModelResult(True, VALID_APPROVE),
        ])
        dev = FakeAdapter([])
        eng = self.engine(dev, rev, FakeAdapter([]))
        out = eng.recover_review(7, sha)
        self.assertEqual(out.verdict, "APPROVE")
        self.assertEqual(rev.calls, 2)
        self.assertEqual(dev.calls, 0)
        self.assertEqual(self.repo.head(), sha)

    def test_malformed_reviewer_output_is_review_error(self):
        eng = self.engine(FakeAdapter([]), FakeAdapter([]), FakeAdapter([]))
        with self.assertRaises(ProviderError):
            eng._review_parse("REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END")

    def test_developer_cannot_change_head(self):
        def mutate():
            self.repo._head = "b" * 40
        inner = FakeAdapter([ModelResult(True, "done")], mutate=mutate)
        guarded = GuardedDeveloperAdapter(inner, self.repo)
        out = guarded.run("prompt", self.repo.root)
        self.assertFalse(out.ok)
        self.assertIn("Runner exclusively owns git delivery", out.error)

    def test_developer_cannot_change_branch(self):
        def mutate():
            self.repo._branch = "other"
        inner = FakeAdapter([ModelResult(True, "done")], mutate=mutate)
        guarded = GuardedDeveloperAdapter(inner, self.repo)
        out = guarded.run("prompt", self.repo.root)
        self.assertFalse(out.ok)
        self.assertIn("Runner exclusively owns git delivery", out.error)

    def test_planner_requires_all_repair_sections(self):
        inner = FakeAdapter([ModelResult(True, "ROOT_CAUSE:\nx\nCHANGES:\ny")])
        planner = ValidatingPlannerAdapter(inner)
        out = planner.run("prompt", self.repo.root)
        self.assertFalse(out.ok)
        self.assertIn("DO_NOT_CHANGE:", out.error)
        self.assertIn("VALIDATION:", out.error)


if __name__ == "__main__":
    unittest.main()
