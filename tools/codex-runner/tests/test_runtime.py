import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runner import Config, GuardError, ModelResult, PromptBuilder, WorkflowEngine, FakeLedger


ISSUE = {"number": 7, "title": "Persist dark mode", "body": "AC: toggle persists after refresh", "state": "OPEN"}


class FakeRepo:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "AGENTS.md").write_text("rules", encoding="utf-8")
        self._head = "a" * 40
        self._branch = "feature/7-dark-mode"
        self._dirty = False
        self.validation_runs = 0
        self.commits = 0
    def ensure_clean(self):
        if self._dirty: raise GuardError("dirty")
    def ensure_issue_branch(self, issue, title, base):
        if not self._branch.startswith(f"feature/{issue}-"): raise GuardError("wrong branch")
    def head(self): return self._head
    def has_changes(self): return self._dirty
    def validate_local(self): self.validation_runs += 1
    def commit_and_push(self, issue, kind):
        self.commits += 1; self._head = ("b" if self.commits == 1 else "c") * 40; self._dirty = False; return self._head
    def merge_base(self, base, head): return "0" * 40
    def diff(self, base, head): return "diff --git a/x b/x\n+change"
    @contextmanager
    def detached_worktree(self, sha):
        d = Path(tempfile.mkdtemp()); yield d


class FakeGitHub:
    def __init__(self):
        self.comments_data = []
        self.ci = {}
        self.wait_calls = 0
        self.ci_queries = 0
    def issue(self, n): return dict(ISSUE)
    def comment(self, n, body): self.comments_data.append({"body": body})
    def comments(self, n): return list(self.comments_data)
    def wait_for_ci(self, sha, name, timeout, poll): self.wait_calls += 1; self.ci[sha] = "PASS"; return "PASS"
    def ci_status(self, sha, name): self.ci_queries += 1; return self.ci.get(sha, "PASS")


class FakeAdapter:
    def __init__(self, outputs):
        self.outputs = list(outputs); self.calls = 0; self.provider = "fake"; self.model = "fake"
    def run(self, prompt, cwd):
        self.calls += 1
        out = self.outputs.pop(0) if self.outputs else ModelResult(False, "", 1, "no fake output")
        return out


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.repo = FakeRepo(); self.gh = FakeGitHub(); self.cfg = Config(ci_poll_seconds=0, ci_timeout_seconds=1)
        self.prompts = PromptBuilder(self.repo.root); self.ledger = FakeLedger()

    def engine(self, dev, rev, planner):
        return WorkflowEngine(self.repo, self.gh, self.prompts, dev, rev, planner, self.cfg, self.ledger)

    def test_success_flow_zero_manual_prompt_relay(self):
        dev = FakeAdapter([ModelResult(True, "done")]); rev = FakeAdapter([ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END")]); planner = FakeAdapter([])
        orig = dev.run
        def run(prompt, cwd):
            r = orig(prompt, cwd); self.repo._dirty = True; return r
        dev.run = run
        st = self.engine(dev, rev, planner).start(7)
        self.assertEqual(st["review"], "APPROVE")
        self.assertEqual(dev.calls, 1); self.assertEqual(rev.calls, 1); self.assertEqual(planner.calls, 0)
        self.assertEqual(self.repo.validation_runs, 1); self.assertEqual(self.gh.wait_calls, 1)

    def test_request_changes_creates_plan_then_approved_repair_delta_review(self):
        dev = FakeAdapter([ModelResult(True, "impl"), ModelResult(True, "repair")])
        rev = FakeAdapter([
            ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: REQUEST_CHANGES\nBLOCKER_COUNT: 1\nREVIEW_RESULT_END"),
            ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END"),
        ])
        planner = FakeAdapter([ModelResult(True, "ROOT_CAUSE:\nx\nCHANGES:\ny\nDO_NOT_CHANGE:\nz\nVALIDATION:\nt")])
        orig = dev.run
        def run(prompt, cwd):
            r = orig(prompt, cwd); self.repo._dirty = True; return r
        dev.run = run
        eng = self.engine(dev, rev, planner)
        st = eng.start(7)
        self.assertEqual(st["review"], "REQUEST_CHANGES")
        plan_id = eng.state["repair_plan"]
        eng.approve_repair(7, plan_id)
        st2 = eng.repair(7, plan_id)
        self.assertEqual(st2["review"], "APPROVE")
        self.assertEqual(dev.calls, 2); self.assertEqual(rev.calls, 2); self.assertEqual(planner.calls, 1)

    def test_reviewer_provider_error_retries_same_sha_without_developer_or_ci_rerun(self):
        dev = FakeAdapter([])
        rev = FakeAdapter([ModelResult(False, "", 1, "provider error"), ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END")])
        planner = FakeAdapter([])
        sha = self.repo.head(); self.gh.ci[sha] = "PASS"
        out = self.engine(dev, rev, planner).review(7, sha)
        self.assertEqual(out.verdict, "APPROVE"); self.assertEqual(rev.calls, 2); self.assertEqual(dev.calls, 0); self.assertEqual(self.repo.validation_runs, 0); self.assertEqual(self.gh.wait_calls, 0); self.assertEqual(self.repo.head(), sha)

    def test_repeated_reviewer_error_stops_without_repair(self):
        dev = FakeAdapter([]); rev = FakeAdapter([ModelResult(False,"",1,"x"), ModelResult(False,"",1,"y")]); planner = FakeAdapter([])
        sha = self.repo.head(); self.gh.ci[sha] = "PASS"
        out = self.engine(dev, rev, planner).review(7, sha)
        self.assertEqual(out.verdict, "REVIEW_ERROR"); self.assertEqual(rev.calls, 2); self.assertEqual(dev.calls, 0); self.assertEqual(planner.calls, 0)

    def test_review_guard_blocks_before_model_when_ci_not_pass(self):
        dev = FakeAdapter([]); rev = FakeAdapter([]); planner = FakeAdapter([])
        sha = self.repo.head(); self.gh.ci[sha] = "PENDING"
        with self.assertRaises(GuardError): self.engine(dev, rev, planner).review(7, sha)
        self.assertEqual(rev.calls, 0)

    def test_repair_requires_approval_and_round_cap(self):
        dev = FakeAdapter([]); rev = FakeAdapter([]); planner = FakeAdapter([]); eng = self.engine(dev, rev, planner)
        sha = self.repo.head(); self.gh.comments_data.append({"body": f"AI_DEV_REPAIR_PLAN\nPLAN_ID: RP-7-1\nSTATUS: AWAITING_APPROVAL\nTARGET_SHA: {sha}"})
        with self.assertRaises(GuardError): eng.repair(7, "RP-7-1")
        self.assertEqual(dev.calls, 0)

    def test_review_only_recovery_no_developer_regression_or_ci_rerun(self):
        dev = FakeAdapter([]); rev = FakeAdapter([ModelResult(True, "REVIEW_RESULT_BEGIN\nVERDICT: APPROVE\nBLOCKER_COUNT: 0\nREVIEW_RESULT_END")]); planner = FakeAdapter([])
        sha = self.repo.head(); self.gh.ci[sha] = "PASS"; self.gh.comments_data.append({"body": f"AI_DEV_RUN_RECORD\nROLE: REVIEWER\nSTATUS: REVIEW_ERROR\nINPUT_SHA: {sha}"})
        out = self.engine(dev, rev, planner).recover_review(7, sha)
        self.assertEqual(out.verdict, "APPROVE"); self.assertEqual(dev.calls, 0); self.assertEqual(self.repo.validation_runs, 0); self.assertEqual(self.gh.wait_calls, 0); self.assertEqual(self.repo.head(), sha)

    def test_third_normal_repair_plan_stops_before_planner_model_call(self):
        dev = FakeAdapter([]); rev = FakeAdapter([]); planner = FakeAdapter([ModelResult(True, "should-not-run")]); eng = self.engine(dev, rev, planner)
        sha = self.repo.head()
        for r in (1, 2):
            self.gh.comments_data.append({"body": f"AI_DEV_RUN_RECORD\nROLE: REPAIR\nSTATUS: SUCCESS\nREPAIR_ROUND: {r}"})
        plan_id = eng.create_repair_plan(7, sha, "still blocked")
        self.assertEqual(plan_id, "NEEDS_HUMAN")
        self.assertEqual(planner.calls, 0)
        self.assertTrue(any("AI_DEV_NEEDS_HUMAN" in c["body"] for c in self.gh.comments_data))


if __name__ == "__main__": unittest.main()
