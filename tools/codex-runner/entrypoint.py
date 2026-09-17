#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import runner as core


class StrictRunLedger(core.RunLedger):
    """Require a durable GitHub audit confirmation for every recorded model call."""

    def record(self, **kwargs):
        run_id = super().record(**kwargs)
        record_path = self.dir / f"{run_id}.json"
        data = json.loads(record_path.read_text(encoding="utf-8"))
        body = "AI_DEV_AUDIT_CONFIRMED\n" + "\n".join(f"{k}: {v}" for k, v in data.items())
        # Unlike the core best-effort comment, this confirmation is required.
        # If GitHub evidence cannot be written, fail closed before advancing workflow state.
        self.github.comment(int(data["ISSUE"]), body)
        return run_id


class HardenedWorkflowEngine(core.WorkflowEngine):
    """Adds guards that must hold before any planner/reviewer model call."""

    def review(
        self,
        issue_no: int,
        sha: str,
        *,
        repair_plan: str = "",
        previous_review: str = "",
        allow_retry: bool = True,
    ) -> core.ReviewOutcome:
        self.repo.ensure_clean()
        return super().review(
            issue_no,
            sha,
            repair_plan=repair_plan,
            previous_review=previous_review,
            allow_retry=allow_retry,
        )

    def create_repair_plan(self, issue_no: int, sha: str, review_text: str) -> str:
        self.repo.ensure_clean()
        return super().create_repair_plan(issue_no, sha, review_text)

    def recover_review(self, issue_no: int, sha: str) -> core.ReviewOutcome:
        self.repo.ensure_clean()
        if self.repo.head() != sha:
            raise core.GuardError("review recovery SHA does not match current HEAD")
        comments = self.github.comments(issue_no)
        had_review_error = any(
            "AI_DEV_RUN_RECORD" in c.get("body", "")
            and "ROLE: REVIEWER" in c.get("body", "")
            and "STATUS: REVIEW_ERROR" in c.get("body", "")
            and f"INPUT_SHA: {sha}" in c.get("body", "")
            for c in comments
        )
        if not had_review_error:
            raise core.GuardError("review-only recovery requires prior REVIEW_ERROR for the same SHA")
        if self.github.ci_status(sha, self.config.ci_check_name) != "PASS":
            raise core.GuardError("review-only recovery requires existing exact-SHA CI PASS")
        # Recovery itself gets one provider-error retry, still on the same immutable product SHA.
        return self.review(issue_no, sha, allow_retry=True)


def build_engine(root: Path) -> tuple[HardenedWorkflowEngine, core.Repo, core.GitHubCLI, core.Config]:
    repo = core.Repo(root)
    config = core.Config.load(repo.root)
    gh = core.GitHubCLI(repo.remote_repo(), repo.root, repo.shell)
    prompts = core.PromptBuilder(repo.root)
    developer = core.CommandModelAdapter(
        config.developer_command, config.developer_provider, config.developer_model, repo.shell
    )
    reviewer = core.CommandModelAdapter(
        config.reviewer_command, config.reviewer_provider, config.reviewer_model, repo.shell
    )
    planner = core.CommandModelAdapter(
        config.planner_command, config.planner_provider, config.planner_model, repo.shell
    )
    ledger = StrictRunLedger(repo, gh)
    return HardenedWorkflowEngine(
        repo, gh, prompts, developer, reviewer, planner, config, ledger
    ), repo, gh, config


def _latest_review_status(gh: Any, issue_no: int | None, sha: str) -> tuple[str, list[str]]:
    if issue_no is None:
        return "NONE", []
    status = "NONE"
    blockers: list[str] = []
    for comment in gh.comments(issue_no):
        body = comment.get("body", "")
        if "AI_DEV_REVIEW_RESULT" in body and f"INPUT_SHA: {sha}" in body:
            if "VERDICT: APPROVE" in body:
                status = "APPROVE"
                blockers = []
            elif "VERDICT: REQUEST_CHANGES" in body:
                status = "REQUEST_CHANGES"
                blockers = ["reviewer requested changes"]
        if (
            "AI_DEV_RUN_RECORD" in body
            and "ROLE: REVIEWER" in body
            and "STATUS: REVIEW_ERROR" in body
            and f"INPUT_SHA: {sha}" in body
        ):
            status = "REVIEW_ERROR"
            blockers = ["reviewer execution error"]
    return status, blockers


def _self_test() -> int:
    here = Path(__file__).resolve().parent
    compile_proc = subprocess.run(
        [sys.executable, "-m", "py_compile", str(here / "runner.py"), str(here / "entrypoint.py")],
        cwd=str(here),
    )
    if compile_proc.returncode != 0:
        return compile_proc.returncode
    proc = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(here / "tests"), "-p", "test_*.py"],
        cwd=str(here),
    )
    return proc.returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="ai-dev", description="GitHub-centered automated Codex development runner"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    p = sub.add_parser("start"); p.add_argument("--issue", type=int, required=True)
    p = sub.add_parser("review"); p.add_argument("--sha", required=True); p.add_argument("--issue", type=int)
    p = sub.add_parser("approve-repair"); p.add_argument("--plan", required=True); p.add_argument("--issue", type=int); p.add_argument("--exceptional", action="store_true")
    p = sub.add_parser("repair"); p.add_argument("--plan", required=True); p.add_argument("--issue", type=int)
    p = sub.add_parser("recover-review"); p.add_argument("--sha", required=True); p.add_argument("--issue", type=int)
    sub.add_parser("self-test")
    args = parser.parse_args(argv)

    if args.cmd == "self-test":
        return _self_test()

    engine, repo, gh, config = build_engine(Path.cwd())
    issue = getattr(args, "issue", None) or core.parse_issue_from_branch(repo.branch())

    try:
        if args.cmd == "status":
            sha = repo.head()
            branch = repo.branch()
            inferred = core.parse_issue_from_branch(branch)
            ci = gh.ci_status(sha, config.ci_check_name)
            review_status, blockers = _latest_review_status(gh, inferred, sha)
            if repo.dirty():
                blockers = [*blockers, "dirty worktree"]
            next_action = "start/review according to Issue state"
            if review_status == "REVIEW_ERROR":
                next_action = f"ai-dev recover-review --sha {sha}"
            elif review_status == "REQUEST_CHANGES":
                next_action = "approve the generated Repair Plan, then run ai-dev repair --plan <id>"
            elif review_status == "APPROVE":
                next_action = "release gate: explicit user decision for merge/deploy"
            print(json.dumps({
                "CURRENT_STATE": "BLOCKED" if blockers else "READY",
                "CURRENT_ISSUE": inferred,
                "BRANCH": branch,
                "PRODUCT_SHA": sha,
                "CI_STATUS": ci,
                "REVIEW_STATUS": review_status,
                "KNOWN_BLOCKERS": blockers,
                "NEXT_ACTION": next_action,
            }, indent=2))
        elif args.cmd == "start":
            print(json.dumps(engine.start(args.issue), indent=2))
        elif args.cmd == "review":
            if issue is None:
                raise core.GuardError("cannot infer issue; pass --issue")
            out = engine.review(issue, args.sha)
            print(out.text if out.text else out.verdict)
        elif args.cmd == "approve-repair":
            if issue is None:
                raise core.GuardError("cannot infer issue; pass --issue")
            engine.approve_repair(issue, args.plan, args.exceptional)
            print(f"approved {args.plan}")
        elif args.cmd == "repair":
            if issue is None:
                raise core.GuardError("cannot infer issue; pass --issue")
            print(json.dumps(engine.repair(issue, args.plan), indent=2))
        elif args.cmd == "recover-review":
            if issue is None:
                raise core.GuardError("cannot infer issue; pass --issue")
            out = engine.recover_review(issue, args.sha)
            print(out.text if out.text else out.verdict)
        return 0
    except core.GuardError as exc:
        print(f"GUARD_BLOCKED: {exc}", file=sys.stderr)
        return 2
    except core.ProviderError as exc:
        print(f"REVIEW_OR_PROVIDER_ERROR: {exc}", file=sys.stderr)
        return 3
    except core.RunnerError as exc:
        print(f"RUNNER_ERROR: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
