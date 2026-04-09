#!/usr/bin/env python3
"""
App Workspace Tool

Creates isolated per-app project workspaces so generated applications never
collide. Each workspace contains frontend/backend separation plus deployment
and GitHub handoff docs for portable VPS production installs.
"""

import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

from whox_constants import get_whox_home
from tools.whox_shadcn_library import seed_workspace_from_shadcn_library


def _slugify(name: str) -> str:
    raw = str(name or "").strip().lower()
    raw = re.sub(r"[^a-z0-9]+", "-", raw)
    raw = re.sub(r"-{2,}", "-", raw).strip("-")
    return raw or "app"


def _apps_root(override: Optional[str] = None) -> Path:
    if override:
        return Path(override).expanduser()
    env_root = os.getenv("WHOX_APPS_ROOT", "").strip()
    if env_root:
        return Path(env_root).expanduser()
    return get_whox_home() / "apps"


def _write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _base_domain_configured() -> bool:
    """
    App/site workspace creation is allowed only when a base domain is configured.
    """
    enabled_flag = str(os.getenv("WHOX_ENABLE_APP_WORKSPACES", "")).strip().lower()
    if enabled_flag in {"0", "false", "no", "off"}:
        return False

    domain = str(os.getenv("WHOX_BASE_DOMAIN", "")).strip().lower()
    if domain:
        return True

    # Backward compatibility alias for older deployments.
    domain_legacy = str(os.getenv("HERMES_BASE_DOMAIN", "")).strip().lower()
    return bool(domain_legacy)


def app_workspace_tool(
    app_name: str,
    stack: str = "web",
    include_convex: bool = True,
    include_generation_notes: bool = True,
    init_git: bool = False,
    apps_root: Optional[str] = None,
) -> str:
    """
    Create an isolated app workspace.
    """
    if not _base_domain_configured():
        return json.dumps(
            {
                "success": False,
                "error": (
                    "Isolated app/site workspace creation is disabled because WHOX_BASE_DOMAIN is not set. "
                    "Set WHOX_BASE_DOMAIN (and optionally WHOX_ENABLE_APP_WORKSPACES=1), then restart WHOX gateway."
                ),
            },
            ensure_ascii=False,
        )

    name = str(app_name or "").strip()
    if not name:
        return json.dumps({"success": False, "error": "app_name is required"}, ensure_ascii=False)

    slug = _slugify(name)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    root = _apps_root(apps_root)
    project_dir = root / f"{slug}-{ts}"
    frontend_dir = project_dir / "frontend"
    backend_dir = project_dir / "backend"
    docs_dir = project_dir / "docs"
    infra_dir = project_dir / "infra"

    project_dir.mkdir(parents=True, exist_ok=False)
    frontend_dir.mkdir(parents=True, exist_ok=True)
    backend_dir.mkdir(parents=True, exist_ok=True)
    docs_dir.mkdir(parents=True, exist_ok=True)
    infra_dir.mkdir(parents=True, exist_ok=True)

    if include_convex:
        (backend_dir / "convex").mkdir(parents=True, exist_ok=True)

    shadcn_seed = seed_workspace_from_shadcn_library(project_dir)

    _write_file(
        project_dir / ".gitignore",
        "\n".join(
            [
                "# Node",
                "node_modules/",
                ".next/",
                "dist/",
                ".turbo/",
                "",
                "# Python",
                "__pycache__/",
                "*.pyc",
                ".venv/",
                "",
                "# Secrets",
                ".env",
                ".env.*",
                "",
                "# Logs",
                "*.log",
            ]
        )
        + "\n",
    )

    convex_note = (
        "Convex backend directory: `backend/convex/`\n"
        if include_convex
        else "Convex backend directory was not pre-created for this workspace.\n"
    )
    generation_note = (
        "Generation note: keep implementation scoped to this root and reuse this folder for iterative versions.\n"
        if include_generation_notes
        else ""
    )

    _write_file(
        project_dir / "README.md",
        "\n".join(
            [
                f"# {name}",
                "",
                f"Workspace: `{project_dir}`",
                "",
                "This app is isolated from all other WHOX-generated apps.",
                "",
                "## Structure",
                "- `frontend/` UI/client code",
                "- `backend/` API/server code",
                "- `infra/` infra/deploy manifests",
                "- `docs/` operational runbooks",
                "- `frontend/src/components/ui/` local shadcn UI components",
                "- `frontend/src/components/blocks/` local shadcn page blocks",
                "- `frontend/src/components/.whox-shadcn/` local shadcn component/block catalogs",
                "",
                convex_note.strip(),
                generation_note.strip(),
                "",
                "## Next",
                "1. Build app features only inside this folder.",
                "2. Use local shadcn catalogs first and reuse seeded local shadcn files from frontend/src/components.",
                "3. Avoid handwritten custom UI unless no suitable local shadcn item exists.",
                "4. Commit and push this folder as its own Git repo.",
                "5. Use docs/GITHUB_PUBLISH.md and docs/INSTALL_ON_VPS.md for handoff.",
            ]
        ).replace("\n\n\n", "\n\n")
        + "\n",
    )

    _write_file(
        docs_dir / "GITHUB_PUBLISH.md",
        "\n".join(
            [
                "# Publish This App To GitHub",
                "",
                "Run from the app root:",
                "```bash",
                "git init",
                "git add .",
                "git commit -m \"initial app scaffold\"",
                "gh repo create <your-org-or-user>/<repo-name> --private --source=. --remote=origin --push",
                "```",
                "",
                "Alternative without gh CLI:",
                "```bash",
                "git init",
                "git add .",
                "git commit -m \"initial app scaffold\"",
                "git remote add origin git@github.com:<your-org-or-user>/<repo-name>.git",
                "git branch -M main",
                "git push -u origin main",
                "```",
            ]
        )
        + "\n",
    )

    _write_file(
        docs_dir / "INSTALL_ON_VPS.md",
        "\n".join(
            [
                "# Install On New VPS",
                "",
                "```bash",
                "sudo apt-get update",
                "sudo apt-get install -y git curl build-essential",
                "# install runtime(s) needed by this app (node/python/etc.)",
                "git clone <repo-url>",
                "cd <repo-name>",
                "cp .env.example .env  # if present, then edit secrets",
                "# install dependencies (example):",
                "# frontend: cd frontend && npm install",
                "# backend: cd backend && npm install (or pip install -r requirements.txt)",
                "# run migrations / convex deploy as needed",
                "# start app services",
                "```",
                "",
                "Keep frontend and backend deployment isolated under this repository only.",
            ]
        )
        + "\n",
    )

    _write_file(
        docs_dir / "STACK_PROFILE.md",
        "\n".join(
            [
                "# Stack Profile",
                "",
                f"- Requested stack: `{stack}`",
                f"- Convex included: `{include_convex}`",
                f"- Generation notes included: `{include_generation_notes}`",
                f"- Local shadcn library: `{shadcn_seed['library_root']}`",
                f"- Seeded UI target: `{shadcn_seed['ui_target']}`",
                f"- Seeded Blocks target: `{shadcn_seed['blocks_target']}`",
                f"- Created at: `{datetime.now().isoformat(timespec='seconds')}`",
            ]
        )
        + "\n",
    )

    if init_git:
        # Keep this optional and shell-free to avoid external command dependency.
        # We only scaffold the marker docs; users/agent can run git commands via terminal tool.
        _write_file(
            project_dir / ".git-init-requested",
            "Git initialization was requested. Run commands in docs/GITHUB_PUBLISH.md.\n",
        )

    return json.dumps(
        {
            "success": True,
            "app_name": name,
            "slug": slug,
            "workspace": str(project_dir),
            "paths": {
                "frontend": str(frontend_dir),
                "backend": str(backend_dir),
                "infra": str(infra_dir),
                "docs": str(docs_dir),
                "convex": str((backend_dir / "convex")) if include_convex else None,
            },
            "notes": [
                "Workspace is isolated from other generated apps.",
                "Use docs/GITHUB_PUBLISH.md to push this specific app repo.",
                "Use docs/INSTALL_ON_VPS.md to install on a separate production VPS.",
                "Seeded from local WHOX shadcn library.",
            ],
            "shadcn": shadcn_seed,
        },
        ensure_ascii=False,
    )


def check_app_workspace_requirements() -> bool:
    return _base_domain_configured()


APP_WORKSPACE_SCHEMA = {
    "name": "app_workspace",
    "description": (
        "Create an isolated per-app project workspace under ~/.whox/apps "
        "(or WHOX_APPS_ROOT). Use this before building a new application so "
        "frontend/backend/docs/deploy artifacts stay separate from other apps."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "app_name": {
                "type": "string",
                "description": "Human-readable app name (used to create folder slug).",
            },
            "stack": {
                "type": "string",
                "description": "Optional stack profile label (e.g. nextjs+convex).",
                "default": "web",
            },
            "include_convex": {
                "type": "boolean",
                "description": "Pre-create backend/convex folder for realtime backend structure.",
                "default": True,
            },
            "include_generation_notes": {
                "type": "boolean",
                "description": "Include deterministic generation notes for app consistency.",
                "default": True,
            },
            "init_git": {
                "type": "boolean",
                "description": "Write git init marker and publish docs (does not execute git commands).",
                "default": False,
            },
        },
        "required": ["app_name"],
    },
}


from tools.registry import registry


registry.register(
    name="app_workspace",
    toolset="file",
    schema=APP_WORKSPACE_SCHEMA,
    handler=lambda args, **kw: app_workspace_tool(
        app_name=args.get("app_name", ""),
        stack=args.get("stack", "web"),
        include_convex=args.get("include_convex", True),
        include_generation_notes=args.get("include_generation_notes", True),
        init_git=args.get("init_git", False),
    ),
    check_fn=check_app_workspace_requirements,
    emoji="🗂️",
)
