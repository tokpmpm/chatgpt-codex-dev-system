import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runner import Config, GuardError, ModelResult, PromptBuilder, FakeLedger
from entrypoint import HardenedWorkflowEngine


ISSUE = {"number": 7, "title": "Persist dark mode", "body": "AC: toggle persists", "state": "OPEN"}


class FakeRepo:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "AGENTS.md").write_text("rules", encoding="utf-8")
        self._head = "a" * 40
        self._dirty = False
        self.validation_runs = 0

    def ensure_clean(self):
        if self._dirty:
            raise GuardError("dirty")

    def head(self):
        return self._head

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
    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.calls = 0
        self.provider = "fake"
        self.model = "fake"

    def run(self, prompt, cwd):
        self.calls += 1
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
            ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END"),
        ])
        dev = FakeAdapter([])
        eng = self.engine(dev, rev, FakeAdapter([]))
        out = eng.recover_review(7, sha)
        self.assertEqual(out.verdict, "APPROVE")
        self.assertEqual(rev.calls, 2)
        self.assertEqual(dev.calls, 0)
        self.assertEqual(self.repo.head(), sha)


if __name__ == "__main__":
    unittest.main()
