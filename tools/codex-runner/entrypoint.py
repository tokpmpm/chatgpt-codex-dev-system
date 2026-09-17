#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import runner as core


OLD_DEVELOPER_DEFAULT = [
    "codex", "exec", "--sandbox", "workspace-write", "--ask-for-approval", "never", "--json", "--ephemeral"
]
OLD_REVIEWER_DEFAULT = [
    "codex", "exec", "--sandbox", "workspace-write", "--ask-for-approval", "never", "--json", "--ephemeral"
]
CURRENT_DEVELOPER_DEFAULT = [
    "codex", "--ask-for-approval", "never", "exec", "--sandbox", "workspace-write", "--json", "--ephemeral"
]
CURRENT_READ_ONLY_DEFAULT = [
    "codex", "--ask-for-approval", "never", "exec", "--sandbox", "read-only", "--json", "--ephemeral"
]


def normalize_adapter_defaults(config: core.Config) -> core.Config:
    """Keep direct entrypoint use safe even when core fallback defaults lag a CLI release."""
    if config.developer_command == OLD_DEVELOPER_DEFAULT:
        config.developer_command = list(CURRENT_DEVELOPER_DEFAULT)
    if config.reviewer_command == OLD_REVIEWER_DEFAULT:
        config.reviewer_command = list(CURRENT_READ_ONLY_DEFAULT)
    if config.planner_command == OLD_REVIEWER_DEFAULT:
        config.planner_command = list(CURRENT_READ_ONLY_DEFAULT)
    return config


def guard_expected_repo(actual_repo: str) -> None:
    expected = os.getenv("AI_DEV_EXPECTED_REPO", "").strip()
    if expected and actual_repo.lower() != expected.lower():
        raise core.GuardError(
            f"wrong repository: expected {expected}, got {actual_repo}; refusing model call"
        )


class HardenedPromptBuilder(core.PromptBuilder):
    """Make repository/branch/base/exact-SHA inputs explicit in every generated prompt."""

    def __init__(self, root: Path, repo: core.Repo, config: core.Config):
        super().__init__(root)
        self.repo = repo
        self.config = config

    def _refs(self, sha: str) -> str:
        branch = self.repo.branch()
        base_sha = self.repo.merge_base(self.config.base_branch, sha)
        return (
            "\nEXPLICIT INPUT REFS:\n"
            f"REPOSITORY: {self.repo.remote_repo()}\n"
            f"BRANCH: {branch}\n"
            f"BASE_BRANCH: {self.config.base_branch}\n"
            f"BASE_SHA: {base_sha}\n"
            f"INPUT_SHA: {sha}\n"
        )

    def developer(self, issue: dict[str, Any], sha: str) -> str:
        return self._refs(sha) + "\n" + super().developer(issue, sha)

    def reviewer(
        self,
        issue: dict[str, Any],
        sha: str,
        diff: str,
        ci_evidence: str,
        repair_plan: str = "",
        previous_review: str = "",
    ) -> str:
        return self._refs(sha) + "\n" + super().reviewer(
            issue, sha, diff, ci_evidence, repair_plan, previous_review
        )

    def planner(self, issue: dict[str, Any], sha: str, review_text: str, next_round: int) -> str:
        return self._refs(sha) + "\n" + super().planner(issue, sha, review_text, next_round)

    def repair(self, issue: dict[str, Any], sha: str, plan: str, round_no: int) -> str:
        return self._refs(sha) + "\n" + super().repair(issue, sha, plan, round_no)


class StrictRunLedger(core.RunLedger):
    """Require durable GitHub audit confirmation for every model execution."""

    def _current_pr_number(self) -> str:
        try:
            branch = self.repo.branch()
            raw = self.github._gh(
                "pr", "list",
                "--repo", self.github.repo_full_name,
                "--head", branch,
                "--state", "open",
                "--json", "number",
                "--limit", "1",
            )
            rows = json.loads(raw or "[]")
            if rows:
                return str(rows[0]["number"])
        except Exception:
            pass
        return "N/A"

    def record(self, **kwargs):
        run_id = super().record(**kwargs)
        record_path = self.dir / f"{run_id}.json"
        data = json.loads(record_path.read_text(encoding="utf-8"))
        data["PR"] = self._current_pr_number()
        data["BRANCH"] = self.repo.branch()
        record_path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
        body = "AI_DEV_AUDIT_CONFIRMED\n" + "\n".join(f"{k}: {v}" for k, v in data.items())
        # Unlike the core best-effort marker, this durable confirmation is required.
        # If GitHub evidence cannot be written, fail closed before advancing workflow state.
        self.github.comment(int(data["ISSUE"]), body)
        return run_id


class HardenedWorkflowEngine(core.WorkflowEngine):
    """Adds guards that must hold before planner/reviewer model calls."""

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
        # Recovery gets at most one fresh provider-error retry, still on the same product SHA.
        return self.review(issue_no, sha, allow_retry=True)


def build_engine(root: Path) -> tuple[HardenedWorkflowEngine, core.Repo, core.GitHubCLI, core.Config]:
    repo = core.Repo(root)
    actual_repo = repo.remote_repo()
    guard_expected_repo(actual_repo)
    config = normalize_adapter_defaults(core.Config.load(repo.root))
    gh = core.GitHubCLI(actual_repo, repo.root, repo.shell)
    prompts = HardenedPromptBuilder(repo.root, repo, config)
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

    try:
        engine, repo, gh, config = build_engine(Path.cwd())
        issue = getattr(args, "issue", None) or core.parse_issue_from_branch(repo.branch())

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
