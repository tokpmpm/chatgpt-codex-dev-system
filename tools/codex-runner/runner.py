#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class RunnerError(RuntimeError):
    pass


class GuardError(RunnerError):
    pass


class ProviderError(RunnerError):
    pass


@dataclass
class Config:
    base_branch: str = "main"
    ci_check_name: str = "Exact SHA validation"
    ci_poll_seconds: int = 10
    ci_timeout_seconds: int = 600
    max_repair_rounds: int = 2
    developer_command: list[str] = field(default_factory=lambda: [
        "codex", "exec", "--sandbox", "workspace-write", "--ask-for-approval", "never", "--json", "--ephemeral"
    ])
    reviewer_command: list[str] = field(default_factory=lambda: [
        "codex", "exec", "--sandbox", "workspace-write", "--ask-for-approval", "never", "--json", "--ephemeral"
    ])
    planner_command: list[str] = field(default_factory=lambda: [
        "codex", "exec", "--sandbox", "workspace-write", "--ask-for-approval", "never", "--json", "--ephemeral"
    ])
    developer_provider: str = "codex-cli"
    reviewer_provider: str = "codex-cli"
    planner_provider: str = "codex-cli"
    developer_model: str = "configured-by-codex"
    reviewer_model: str = "configured-by-codex"
    planner_model: str = "configured-by-codex"

    @classmethod
    def load(cls, root: Path) -> "Config":
        cfg = cls()
        candidates = []
        if os.getenv("AI_DEV_CONFIG"):
            candidates.append(Path(os.environ["AI_DEV_CONFIG"]))
        candidates += [root / "ai-dev.config.json", root / ".ai-dev-system.json"]
        for p in candidates:
            if p.is_file():
                data = json.loads(p.read_text(encoding="utf-8"))
                git_cfg = data.get("git", {})
                ci_cfg = data.get("ci", {})
                repair_cfg = data.get("repair", {})
                cfg.base_branch = git_cfg.get("base_branch", cfg.base_branch)
                cfg.ci_check_name = ci_cfg.get("check_name", cfg.ci_check_name)
                cfg.ci_poll_seconds = int(ci_cfg.get("poll_seconds", cfg.ci_poll_seconds))
                cfg.ci_timeout_seconds = int(ci_cfg.get("timeout_seconds", cfg.ci_timeout_seconds))
                cfg.max_repair_rounds = int(repair_cfg.get("max_rounds", cfg.max_repair_rounds))
                for role in ("developer", "reviewer", "planner"):
                    block = data.get(role, {})
                    if block.get("command"):
                        setattr(cfg, f"{role}_command", list(block["command"]))
                    if block.get("provider"):
                        setattr(cfg, f"{role}_provider", str(block["provider"]))
                    if block.get("model"):
                        setattr(cfg, f"{role}_model", str(block["model"]))
                break
        for role in ("developer", "reviewer", "planner"):
            env = os.getenv(f"AI_DEV_{role.upper()}_CMD")
            if env:
                setattr(cfg, f"{role}_command", shlex.split(env))
            model = os.getenv(f"AI_DEV_{role.upper()}_MODEL")
            if model:
                setattr(cfg, f"{role}_model", model)
        return cfg


@dataclass
class ModelResult:
    ok: bool
    text: str
    exit_code: int = 0
    error: str = ""


@dataclass
class ReviewOutcome:
    verdict: str
    text: str
    blocker_count: int = 0


class Shell:
    def run(self, argv: list[str], *, cwd: Path, check: bool = True, input_text: str | None = None, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
        proc = subprocess.run(
            argv, cwd=str(cwd), text=True, input=input_text, capture_output=True, timeout=timeout
        )
        if check and proc.returncode != 0:
            raise RunnerError(f"command failed ({proc.returncode}): {' '.join(argv)}\n{proc.stderr.strip()}")
        return proc


class Repo:
    def __init__(self, root: Path | None = None, shell: Shell | None = None):
        self.shell = shell or Shell()
        if root is None:
            p = self.shell.run(["git", "rev-parse", "--show-toplevel"], cwd=Path.cwd()).stdout.strip()
            root = Path(p)
        self.root = root.resolve()

    def git(self, *args: str, check: bool = True) -> str:
        return self.shell.run(["git", *args], cwd=self.root, check=check).stdout.strip()

    def branch(self) -> str:
        return self.git("branch", "--show-current")

    def head(self) -> str:
        return self.git("rev-parse", "HEAD")

    def dirty(self) -> str:
        return self.git("status", "--porcelain")

    def ensure_clean(self) -> None:
        dirty = self.dirty()
        if dirty:
            raise GuardError("unexpected dirty worktree; refusing model call")

    def remote_repo(self) -> str:
        url = self.git("remote", "get-url", "origin")
        m = re.search(r"github\.com[:/]([^/]+/[^/.]+)(?:\.git)?$", url)
        if not m:
            raise GuardError(f"origin is not a supported GitHub repository: {url}")
        return m.group(1)

    def ensure_issue_branch(self, issue: int, title: str, base_branch: str) -> None:
        branch = self.branch()
        if branch == base_branch:
            self.ensure_clean()
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:48] or "work"
            new_branch = f"feature/{issue}-{slug}"
            self.git("switch", "-c", new_branch)
            return
        if not re.match(rf"^(feature|fix)/{issue}(?:-|$)", branch):
            raise GuardError(f"wrong branch '{branch}' for issue #{issue}; expected feature/{issue}-* or fix/{issue}-*")

    def validate_local(self) -> None:
        script = self.root / "ci" / "ai-verify.sh"
        if not script.is_file():
            raise GuardError("ci/ai-verify.sh missing; refusing delivery without repository validation")
        proc = self.shell.run(["bash", str(script)], cwd=self.root, check=False, timeout=1800)
        if proc.returncode != 0:
            raise RunnerError(f"local validation failed\n{proc.stdout}\n{proc.stderr}")

    def has_changes(self) -> bool:
        return bool(self.dirty())

    def commit_and_push(self, issue: int, kind: str) -> str:
        self.git("add", "-A")
        staged = self.git("diff", "--cached", "--name-only")
        if not staged:
            raise RunnerError("model completed but produced no staged product changes")
        self.git("commit", "-m", f"{kind}(issue #{issue}): automated ai-dev run")
        sha = self.head()
        self.git("push", "-u", "origin", "HEAD")
        return sha

    def diff(self, base: str, head: str) -> str:
        return self.git("diff", "--no-ext-diff", f"{base}..{head}")

    def merge_base(self, base_branch: str, head: str) -> str:
        self.git("fetch", "origin", base_branch)
        return self.git("merge-base", f"origin/{base_branch}", head)

    def detached_worktree(self, sha: str):
        return _DetachedWorktree(self, sha)


class _DetachedWorktree:
    def __init__(self, repo: Repo, sha: str):
        self.repo = repo
        self.sha = sha
        self.path: Path | None = None

    def __enter__(self) -> Path:
        self.path = Path(tempfile.mkdtemp(prefix="ai-dev-review-"))
        self.repo.git("worktree", "add", "--detach", str(self.path), self.sha)
        return self.path

    def __exit__(self, exc_type, exc, tb):
        if self.path:
            try:
                self.repo.git("worktree", "remove", "--force", str(self.path), check=False)
            finally:
                shutil.rmtree(self.path, ignore_errors=True)


class GitHubCLI:
    def __init__(self, repo_full_name: str, root: Path, shell: Shell | None = None):
        self.repo_full_name = repo_full_name
        self.root = root
        self.shell = shell or Shell()

    def _gh(self, *args: str, check: bool = True) -> str:
        if shutil.which("gh") is None:
            raise GuardError("GitHub CLI 'gh' is required and must be authenticated")
        return self.shell.run(["gh", *args], cwd=self.root, check=check).stdout.strip()

    def issue(self, number: int) -> dict[str, Any]:
        out = self._gh("issue", "view", str(number), "--repo", self.repo_full_name, "--json", "number,title,body,state,url")
        data = json.loads(out)
        if data.get("state") != "OPEN":
            raise GuardError(f"issue #{number} is not open")
        return data

    def comments(self, number: int) -> list[dict[str, Any]]:
        out = self._gh("api", f"repos/{self.repo_full_name}/issues/{number}/comments", "--method", "GET", "-f", "per_page=100")
        data = json.loads(out or "[]")
        return data if isinstance(data, list) else []

    def comment(self, number: int, body: str) -> None:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as f:
            f.write(body)
            path = f.name
        try:
            self._gh("issue", "comment", str(number), "--repo", self.repo_full_name, "--body-file", path)
        finally:
            Path(path).unlink(missing_ok=True)

    def ci_status(self, sha: str, check_name: str) -> str:
        out = self._gh("api", f"repos/{self.repo_full_name}/commits/{sha}/check-runs", "-H", "Accept: application/vnd.github+json")
        data = json.loads(out or "{}")
        matches = [c for c in data.get("check_runs", []) if c.get("name") == check_name]
        if not matches:
            return "MISSING"
        latest = sorted(matches, key=lambda c: c.get("started_at") or "")[-1]
        if latest.get("status") != "completed":
            return "PENDING"
        return "PASS" if latest.get("conclusion") == "success" else f"FAIL:{latest.get('conclusion')}"

    def wait_for_ci(self, sha: str, check_name: str, timeout_seconds: int, poll_seconds: int) -> str:
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            status = self.ci_status(sha, check_name)
            if status == "PASS" or status.startswith("FAIL:"):
                return status
            time.sleep(poll_seconds)
        return "TIMEOUT"


class PromptBuilder:
    DOCS = [
        "AGENTS.md",
        "docs/PROJECT_STATE.md",
        "docs/AI_WORKFLOW.md",
        "docs/REVIEW_PROTOCOL.md",
        "docs/ONE_SHOT_DELIVERY_PROTOCOL.md",
        "docs/REPAIR_PROTOCOL.md",
    ]

    def __init__(self, root: Path):
        self.root = root

    def _docs(self) -> str:
        blocks = []
        for rel in self.DOCS:
            p = self.root / rel
            if p.is_file():
                text = p.read_text(encoding="utf-8", errors="replace")
                blocks.append(f"\n===== {rel} =====\n{text[:24000]}")
        return "".join(blocks)

    def developer(self, issue: dict[str, Any], sha: str) -> str:
        return f"""You are the Developer in an audited AI development workflow.
Work non-interactively from the approved GitHub Issue. Do not ask the user to relay prompts.
Before editing, inspect source of truth, writer/reader/persistence paths, relevant tests, and failure cases.
Implement only the Issue scope. Do not merge, deploy, weaken tests, reset user changes, or modify golden baselines to hide regressions.
Run targeted tests, real-flow validation where required, negative cases, and relevant regression. Do not commit or push; the Runner owns git delivery.
If blocked, stop with a concise blocker and do not invent product decisions.

ISSUE #{issue['number']}: {issue['title']}
INPUT_SHA: {sha}

{issue.get('body','')}

REPOSITORY CONTRACT:
{self._docs()}
"""

    def reviewer(self, issue: dict[str, Any], sha: str, diff: str, ci_evidence: str, repair_plan: str = "", previous_review: str = "") -> str:
        delta = bool(repair_plan or previous_review)
        mode = "DELTA REVIEW" if delta else "FULL REVIEW"
        extra = ""
        if repair_plan:
            extra += f"\nAPPROVED REPAIR PLAN:\n{repair_plan}\n"
        if previous_review:
            extra += f"\nPREVIOUS REVIEW BLOCKERS:\n{previous_review}\n"
        return f"""You are an Independent Reviewer in a fresh isolated worktree. This is {mode}.
Review only; do not implement, commit, push, merge, deploy, or intentionally modify files.
Evaluate the exact SHA against the GitHub Issue and Acceptance Criteria using source, tests, diff, and CI evidence.
Do not lower requirements. Distinguish product blockers from reviewer/provider execution problems.
Return exactly one review matrix and one result block. If any acceptance criterion is not evidenced, mark it BLOCKER.

ISSUE #{issue['number']}: {issue['title']}
EXACT_SHA: {sha}
CI_EVIDENCE: {ci_evidence}
{extra}
ISSUE BODY:
{issue.get('body','')}

EXACT DIFF:
{diff[:90000]}

REPOSITORY CONTRACT:
{self._docs()}

Required final format:
REVIEW_MATRIX_BEGIN
Requirement | Real source/path | Positive evidence | Negative/guard evidence | Status
...
REVIEW_MATRIX_END
REVIEW_RESULT_BEGIN
VERDICT: APPROVE
BLOCKER_COUNT: 0
REVIEW_RESULT_END

For product blockers use VERDICT: REQUEST_CHANGES and a positive BLOCKER_COUNT.
"""

    def planner(self, issue: dict[str, Any], sha: str, review_text: str, next_round: int) -> str:
        return f"""You are the Repair Planner. Plan only; do not edit files.
Use the reviewer blockers and exact product SHA to produce the smallest repair that satisfies the existing Issue without scope expansion.
Do not weaken tests, change golden baselines to hide regression, merge, or deploy.

ISSUE #{issue['number']}: {issue['title']}
TARGET_SHA: {sha}
REPAIR_ROUND: {next_round}

ISSUE BODY:
{issue.get('body','')}

REVIEW BLOCKERS:
{review_text}

Return concise sections exactly named:
ROOT_CAUSE:
CHANGES:
DO_NOT_CHANGE:
VALIDATION:
"""

    def repair(self, issue: dict[str, Any], sha: str, plan: str, round_no: int) -> str:
        return f"""You are the Developer executing an already approved Repair Plan.
Do not invent a different repair plan or expand scope. Do not ask the user to relay prompts.
Inspect the exact blocker path before editing. Implement only the approved changes, then run targeted tests, negative cases, and relevant regression.
Do not commit or push; the Runner owns git delivery. Do not merge or deploy.

ISSUE #{issue['number']}: {issue['title']}
TARGET_SHA: {sha}
REPAIR_ROUND: {round_no}

APPROVED REPAIR PLAN:
{plan}

ISSUE BODY:
{issue.get('body','')}

REPOSITORY CONTRACT:
{self._docs()}
"""


class CommandModelAdapter:
    def __init__(self, command: list[str], provider: str, model: str, shell: Shell | None = None):
        self.command = command
        self.provider = provider
        self.model = model
        self.shell = shell or Shell()

    def run(self, prompt: str, cwd: Path, timeout: int = 3600) -> ModelResult:
        if not self.command:
            return ModelResult(False, "", 127, "empty model command")
        if shutil.which(self.command[0]) is None:
            return ModelResult(False, "", 127, f"model executable not found: {self.command[0]}")
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as f:
            output_path = f.name
        try:
            argv = [part.replace("{output}", output_path) for part in self.command]
            if self.command[0] == "codex" and self.model != "configured-by-codex" and "-m" not in argv and "--model" not in argv:
                argv += ["-m", self.model]
            if not any("{output}" in part for part in self.command):
                argv += ["--output-last-message", output_path]
            argv.append(prompt)
            proc = self.shell.run(argv, cwd=cwd, check=False, timeout=timeout)
            text = Path(output_path).read_text(encoding="utf-8", errors="replace").strip() if Path(output_path).exists() else ""
            if not text:
                text = (proc.stdout or "").strip()
            if proc.returncode != 0:
                return ModelResult(False, text, proc.returncode, (proc.stderr or "").strip())
            return ModelResult(True, text, 0, "")
        except subprocess.TimeoutExpired:
            return ModelResult(False, "", 124, "provider timeout")
        finally:
            Path(output_path).unlink(missing_ok=True)


class RunLedger:
    def __init__(self, repo: Repo, github: GitHubCLI | Any):
        self.repo = repo
        self.github = github
        git_dir = repo.git("rev-parse", "--git-dir")
        p = Path(git_dir)
        if not p.is_absolute():
            p = repo.root / p
        self.dir = p / "ai-dev" / "runs"
        self.dir.mkdir(parents=True, exist_ok=True)

    def record(self, *, role: str, issue: int, input_sha: str, prompt: str, provider: str, model: str, status: str, result_summary: str, repair_round: int = 0, run_id: str | None = None, started_at: float | None = None) -> str:
        run_id = run_id or f"run-{int(time.time())}-{uuid.uuid4().hex[:8]}"
        data = {
            "RUN_ID": run_id,
            "ROLE": role,
            "ISSUE": issue,
            "INPUT_SHA": input_sha,
            "PROMPT_SHA256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
            "PROVIDER": provider,
            "MODEL": model,
            "STARTED_AT": started_at or time.time(),
            "ENDED_AT": time.time(),
            "STATUS": status,
            "RESULT_SUMMARY": result_summary[:1200],
            "REPAIR_ROUND": repair_round,
        }
        (self.dir / f"{run_id}.json").write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
        body = "AI_DEV_RUN_RECORD\n" + "\n".join(f"{k}: {v}" for k, v in data.items())
        try:
            self.github.comment(issue, body)
        except Exception:
            pass
        return run_id


class WorkflowEngine:
    def __init__(self, repo: Any, github: Any, prompts: PromptBuilder, developer: Any, reviewer: Any, planner: Any, config: Config, ledger: Any | None = None):
        self.repo = repo
        self.github = github
        self.prompts = prompts
        self.developer = developer
        self.reviewer = reviewer
        self.planner = planner
        self.config = config
        self.ledger = ledger
        self.state: dict[str, Any] = {}

    def _record(self, **kwargs):
        if self.ledger:
            self.ledger.record(**kwargs)

    def _review_parse(self, text: str) -> ReviewOutcome:
        m = re.search(r"VERDICT:\s*(APPROVE|REQUEST_CHANGES)", text)
        if not m:
            raise ProviderError("malformed reviewer output: missing verdict")
        b = re.search(r"BLOCKER_COUNT:\s*(\d+)", text)
        blockers = int(b.group(1)) if b else (0 if m.group(1) == "APPROVE" else 1)
        if m.group(1) == "APPROVE" and blockers != 0:
            raise ProviderError("malformed reviewer output: APPROVE with nonzero blockers")
        return ReviewOutcome(m.group(1), text, blockers)

    def _run_review_once(self, issue: dict[str, Any], sha: str, diff: str, ci_evidence: str, repair_plan: str = "", previous_review: str = "") -> ReviewOutcome:
        prompt = self.prompts.reviewer(issue, sha, diff, ci_evidence, repair_plan, previous_review)
        started = time.time()
        with self.repo.detached_worktree(sha) as worktree:
            result = self.reviewer.run(prompt, worktree)
            dirty = subprocess.run(["git", "status", "--porcelain"], cwd=str(worktree), text=True, capture_output=True).stdout.strip() if isinstance(worktree, Path) else ""
            if dirty:
                result = ModelResult(False, result.text, result.exit_code or 1, "reviewer modified isolated worktree")
        if not result.ok:
            self._record(role="REVIEWER", issue=issue["number"], input_sha=sha, prompt=prompt, provider=self.reviewer.provider, model=self.reviewer.model, status="REVIEW_ERROR", result_summary=result.error or result.text, started_at=started)
            raise ProviderError(result.error or "reviewer execution failed")
        try:
            outcome = self._review_parse(result.text)
        except ProviderError as exc:
            self._record(role="REVIEWER", issue=issue["number"], input_sha=sha, prompt=prompt, provider=self.reviewer.provider, model=self.reviewer.model, status="REVIEW_ERROR", result_summary=str(exc), started_at=started)
            raise
        self._record(role="REVIEWER", issue=issue["number"], input_sha=sha, prompt=prompt, provider=self.reviewer.provider, model=self.reviewer.model, status=outcome.verdict, result_summary=result.text, started_at=started)
        try:
            self.github.comment(issue["number"], f"AI_DEV_REVIEW_RESULT\nINPUT_SHA: {sha}\nVERDICT: {outcome.verdict}\nBLOCKER_COUNT: {outcome.blocker_count}\n\n{result.text}")
        except Exception:
            pass
        return outcome

    def review(self, issue_no: int, sha: str, *, repair_plan: str = "", previous_review: str = "", allow_retry: bool = True) -> ReviewOutcome:
        if self.repo.head() != sha:
            raise GuardError("HEAD does not match requested review SHA")
        ci = self.github.ci_status(sha, self.config.ci_check_name)
        if ci != "PASS":
            raise GuardError(f"exact-SHA CI is not PASS: {ci}")
        issue = self.github.issue(issue_no)
        base = self.repo.merge_base(self.config.base_branch, sha)
        diff = self.repo.diff(base, sha)
        attempts = 2 if allow_retry else 1
        last_error = ""
        for _ in range(attempts):
            try:
                outcome = self._run_review_once(issue, sha, diff, f"{self.config.ci_check_name}=PASS", repair_plan, previous_review)
                self.state.update({"issue": issue_no, "sha": sha, "review": outcome.verdict, "review_text": outcome.text})
                if outcome.verdict == "REQUEST_CHANGES":
                    self.create_repair_plan(issue_no, sha, outcome.text)
                return outcome
            except ProviderError as exc:
                last_error = str(exc)
        self.state.update({"issue": issue_no, "sha": sha, "review": "REVIEW_ERROR", "review_error": last_error})
        return ReviewOutcome("REVIEW_ERROR", last_error, 0)

    def create_repair_plan(self, issue_no: int, sha: str, review_text: str) -> str:
        issue = self.github.issue(issue_no)
        round_no = self.repair_round_count(issue_no) + 1
        if round_no > self.config.max_repair_rounds:
            self.github.comment(issue_no, f"AI_DEV_NEEDS_HUMAN\nISSUE: {issue_no}\nTARGET_SHA: {sha}\nREASON: formal repair round limit {self.config.max_repair_rounds} reached")
            self.state.update({"needs_human": True, "repair_round": round_no})
            return "NEEDS_HUMAN"
        prompt = self.prompts.planner(issue, sha, review_text, round_no)
        started = time.time()
        with self.repo.detached_worktree(sha) as worktree:
            result = self.planner.run(prompt, worktree)
            dirty = subprocess.run(["git", "status", "--porcelain"], cwd=str(worktree), text=True, capture_output=True).stdout.strip() if isinstance(worktree, Path) else ""
            if dirty:
                result = ModelResult(False, result.text, result.exit_code or 1, "planner modified isolated worktree")
        if not result.ok:
            self._record(role="PLANNER", issue=issue_no, input_sha=sha, prompt=prompt, provider=self.planner.provider, model=self.planner.model, status="ERROR", result_summary=result.error, repair_round=round_no, started_at=started)
            raise ProviderError(result.error or "repair planner failed")
        plan_id = f"RP-{issue_no}-{int(time.time())}"
        body = f"""AI_DEV_REPAIR_PLAN
PLAN_ID: {plan_id}
STATUS: AWAITING_APPROVAL
ISSUE: {issue_no}
TARGET_SHA: {sha}
REPAIR_ROUND: {round_no}

{result.text.strip()}
"""
        self.github.comment(issue_no, body)
        self._record(role="PLANNER", issue=issue_no, input_sha=sha, prompt=prompt, provider=self.planner.provider, model=self.planner.model, status="PLAN_CREATED", result_summary=plan_id, repair_round=round_no, started_at=started)
        self.state.update({"repair_plan": plan_id, "repair_round": round_no})
        return plan_id

    def repair_round_count(self, issue_no: int) -> int:
        count = 0
        for c in self.github.comments(issue_no):
            body = c.get("body", "")
            if "AI_DEV_RUN_RECORD" in body and "ROLE: REPAIR" in body and "STATUS: SUCCESS" in body:
                count += 1
        return count

    def _latest_review_text(self, issue_no: int, sha: str) -> str:
        found = ""
        for c in self.github.comments(issue_no):
            body = c.get("body", "")
            if "AI_DEV_REVIEW_RESULT" in body and f"INPUT_SHA: {sha}" in body:
                found = body
        return found

    def _find_plan(self, issue_no: int, plan_id: str) -> tuple[str, bool, bool]:
        comments = self.github.comments(issue_no)
        plan = ""
        approved = False
        exceptional = False
        for c in comments:
            body = c.get("body", "")
            if f"PLAN_ID: {plan_id}" in body and "AI_DEV_REPAIR_PLAN" in body:
                plan = body
            if "AI_DEV_REPAIR_APPROVAL" in body and f"PLAN_ID: {plan_id}" in body and "STATUS: APPROVED" in body:
                approved = True
            if "AI_DEV_EXCEPTIONAL_REPAIR_APPROVAL" in body and f"PLAN_ID: {plan_id}" in body and "STATUS: APPROVED" in body:
                exceptional = True
        return plan, approved, exceptional

    def approve_repair(self, issue_no: int, plan_id: str, exceptional: bool = False) -> None:
        marker = "AI_DEV_EXCEPTIONAL_REPAIR_APPROVAL" if exceptional else "AI_DEV_REPAIR_APPROVAL"
        self.github.comment(issue_no, f"{marker}\nPLAN_ID: {plan_id}\nSTATUS: APPROVED")

    def start(self, issue_no: int) -> dict[str, Any]:
        issue = self.github.issue(issue_no)
        self.repo.ensure_clean()
        self.repo.ensure_issue_branch(issue_no, issue["title"], self.config.base_branch)
        self.repo.ensure_clean()
        input_sha = self.repo.head()
        prompt = self.prompts.developer(issue, input_sha)
        started = time.time()
        result = self.developer.run(prompt, self.repo.root)
        if not result.ok:
            self._record(role="DEVELOPER", issue=issue_no, input_sha=input_sha, prompt=prompt, provider=self.developer.provider, model=self.developer.model, status="ERROR", result_summary=result.error or result.text, started_at=started)
            raise ProviderError(result.error or "developer failed")
        if not self.repo.has_changes():
            self._record(role="DEVELOPER", issue=issue_no, input_sha=input_sha, prompt=prompt, provider=self.developer.provider, model=self.developer.model, status="ERROR", result_summary="no product changes", started_at=started)
            raise RunnerError("developer produced no product changes")
        self.repo.validate_local()
        sha = self.repo.commit_and_push(issue_no, "feat")
        self._record(role="DEVELOPER", issue=issue_no, input_sha=input_sha, prompt=prompt, provider=self.developer.provider, model=self.developer.model, status="SUCCESS", result_summary=f"pushed {sha}", started_at=started)
        ci = self.github.wait_for_ci(sha, self.config.ci_check_name, self.config.ci_timeout_seconds, self.config.ci_poll_seconds)
        if ci != "PASS":
            raise RunnerError(f"exact-SHA CI did not pass: {ci}")
        outcome = self.review(issue_no, sha)
        self.state.update({"issue": issue_no, "sha": sha, "ci": ci, "review": outcome.verdict})
        return self.state.copy()

    def repair(self, issue_no: int, plan_id: str) -> dict[str, Any]:
        self.repo.ensure_clean()
        plan, approved, exceptional = self._find_plan(issue_no, plan_id)
        if not plan:
            raise GuardError(f"repair plan {plan_id} not found")
        if not approved and not exceptional:
            raise GuardError(f"repair plan {plan_id} is not approved")
        completed = self.repair_round_count(issue_no)
        next_round = completed + 1
        if next_round > self.config.max_repair_rounds and not exceptional:
            raise GuardError("formal product repair limit reached; exceptional approval required")
        issue = self.github.issue(issue_no)
        input_sha = self.repo.head()
        if f"TARGET_SHA: {input_sha}" not in plan:
            raise GuardError("repair plan TARGET_SHA does not match current HEAD")
        prompt = self.prompts.repair(issue, input_sha, plan, next_round)
        started = time.time()
        result = self.developer.run(prompt, self.repo.root)
        if not result.ok:
            self._record(role="REPAIR", issue=issue_no, input_sha=input_sha, prompt=prompt, provider=self.developer.provider, model=self.developer.model, status="ERROR", result_summary=result.error or result.text, repair_round=next_round, started_at=started)
            raise ProviderError(result.error or "repair developer failed")
        if not self.repo.has_changes():
            raise RunnerError("repair produced no product changes")
        self.repo.validate_local()
        new_sha = self.repo.commit_and_push(issue_no, "fix")
        self._record(role="REPAIR", issue=issue_no, input_sha=input_sha, prompt=prompt, provider=self.developer.provider, model=self.developer.model, status="SUCCESS", result_summary=f"pushed {new_sha}", repair_round=next_round, started_at=started)
        ci = self.github.wait_for_ci(new_sha, self.config.ci_check_name, self.config.ci_timeout_seconds, self.config.ci_poll_seconds)
        if ci != "PASS":
            raise RunnerError(f"repair exact-SHA CI did not pass: {ci}")
        previous_review = self._latest_review_text(issue_no, input_sha) or self.state.get("review_text", "")
        outcome = self.review(issue_no, new_sha, repair_plan=plan, previous_review=previous_review)
        self.state.update({"issue": issue_no, "sha": new_sha, "ci": ci, "review": outcome.verdict, "repair_round": next_round})
        return self.state.copy()

    def recover_review(self, issue_no: int, sha: str) -> ReviewOutcome:
        if self.repo.head() != sha:
            raise GuardError("review recovery SHA does not match current HEAD")
        comments = self.github.comments(issue_no)
        had_review_error = any(
            "AI_DEV_RUN_RECORD" in c.get("body", "") and "ROLE: REVIEWER" in c.get("body", "") and "STATUS: REVIEW_ERROR" in c.get("body", "") and f"INPUT_SHA: {sha}" in c.get("body", "")
            for c in comments
        )
        if not had_review_error:
            raise GuardError("review-only recovery requires prior REVIEW_ERROR for the same SHA")
        if self.github.ci_status(sha, self.config.ci_check_name) != "PASS":
            raise GuardError("review-only recovery requires existing exact-SHA CI PASS")
        return self.review(issue_no, sha, allow_retry=False)


class FakeLedger:
    def __init__(self):
        self.records: list[dict[str, Any]] = []
    def record(self, **kwargs):
        self.records.append(kwargs)


def parse_issue_from_branch(branch: str) -> int | None:
    m = re.match(r"^(?:feature|fix)/(\d+)(?:-|$)", branch)
    return int(m.group(1)) if m else None


def build_engine(root: Path) -> tuple[WorkflowEngine, Repo, GitHubCLI, Config]:
    repo = Repo(root)
    config = Config.load(repo.root)
    gh = GitHubCLI(repo.remote_repo(), repo.root, repo.shell)
    prompts = PromptBuilder(repo.root)
    developer = CommandModelAdapter(config.developer_command, config.developer_provider, config.developer_model, repo.shell)
    reviewer = CommandModelAdapter(config.reviewer_command, config.reviewer_provider, config.reviewer_model, repo.shell)
    planner = CommandModelAdapter(config.planner_command, config.planner_provider, config.planner_model, repo.shell)
    ledger = RunLedger(repo, gh)
    return WorkflowEngine(repo, gh, prompts, developer, reviewer, planner, config, ledger), repo, gh, config


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-dev", description="GitHub-centered automated Codex development runner")
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
        here = Path(__file__).resolve().parent
        proc = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(here / "tests"), "-p", "test_*.py"], cwd=str(here))
        return proc.returncode

    engine, repo, gh, config = build_engine(Path.cwd())
    issue = getattr(args, "issue", None) or parse_issue_from_branch(repo.branch())

    try:
        if args.cmd == "status":
            sha = repo.head(); branch = repo.branch(); inferred = parse_issue_from_branch(branch)
            ci = gh.ci_status(sha, config.ci_check_name)
            print(json.dumps({"CURRENT_STATE": "READY" if not repo.dirty() else "DIRTY", "CURRENT_ISSUE": inferred, "BRANCH": branch, "PRODUCT_SHA": sha, "CI_STATUS": ci, "REVIEW_STATUS": "QUERY_ISSUE_RUN_RECORDS", "KNOWN_BLOCKERS": [] if not repo.dirty() else ["dirty worktree"], "NEXT_ACTION": "start/review according to Issue state"}, indent=2))
        elif args.cmd == "start":
            print(json.dumps(engine.start(args.issue), indent=2))
        elif args.cmd == "review":
            if issue is None: raise GuardError("cannot infer issue; pass --issue")
            out = engine.review(issue, args.sha); print(out.text if out.text else out.verdict)
        elif args.cmd == "approve-repair":
            if issue is None: raise GuardError("cannot infer issue; pass --issue")
            engine.approve_repair(issue, args.plan, args.exceptional); print(f"approved {args.plan}")
        elif args.cmd == "repair":
            if issue is None: raise GuardError("cannot infer issue; pass --issue")
            print(json.dumps(engine.repair(issue, args.plan), indent=2))
        elif args.cmd == "recover-review":
            if issue is None: raise GuardError("cannot infer issue; pass --issue")
            out = engine.recover_review(issue, args.sha); print(out.text if out.text else out.verdict)
        return 0
    except GuardError as exc:
        print(f"GUARD_BLOCKED: {exc}", file=sys.stderr); return 2
    except ProviderError as exc:
        print(f"REVIEW_OR_PROVIDER_ERROR: {exc}", file=sys.stderr); return 3
    except RunnerError as exc:
        print(f"RUNNER_ERROR: {exc}", file=sys.stderr); return 4


if __name__ == "__main__":
    raise SystemExit(main())
