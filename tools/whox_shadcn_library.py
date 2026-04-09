#!/usr/bin/env python3
"""
WHOX local shadcn component/block library bootstrap.

This keeps reusable UI primitives and blocks in a single local WHOX folder so
new isolated app workspaces can copy from it without hitting the network.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from whox_constants import get_whox_home


UI_COMPONENTS = {
    "button.tsx": """import * as React from "react"

import { cn } from "@/lib/utils"

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost"
  size?: "default" | "sm" | "lg"
}

export function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center rounded-md font-medium transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900",
        "disabled:pointer-events-none disabled:opacity-50",
        variant === "default" && "bg-zinc-900 text-white hover:bg-zinc-800",
        variant === "outline" && "border border-zinc-300 bg-white hover:bg-zinc-50",
        variant === "ghost" && "hover:bg-zinc-100",
        size === "default" && "h-10 px-4 py-2",
        size === "sm" && "h-8 px-3 text-sm",
        size === "lg" && "h-11 px-6",
        className
      )}
      {...props}
    />
  )
}
""",
    "card.tsx": """import * as React from "react"

import { cn } from "@/lib/utils"

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("rounded-xl border bg-white text-zinc-950 shadow-sm", className)} {...props} />
}

export function CardHeader({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-col space-y-1.5 p-6", className)} {...props} />
}

export function CardTitle({ className, ...props }: React.HTMLAttributes<HTMLHeadingElement>) {
  return <h3 className={cn("text-2xl font-semibold leading-none tracking-tight", className)} {...props} />
}

export function CardDescription({ className, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-sm text-zinc-500", className)} {...props} />
}

export function CardContent({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("p-6 pt-0", className)} {...props} />
}
""",
    "badge.tsx": """import * as React from "react"

import { cn } from "@/lib/utils"

export function Badge({ className, ...props }: React.HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full border border-zinc-200 bg-zinc-50 px-2.5 py-0.5 text-xs font-semibold text-zinc-700",
        className
      )}
      {...props}
    />
  )
}
""",
    "input.tsx": """import * as React from "react"

import { cn } from "@/lib/utils"

export const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
  ({ className, type = "text", ...props }, ref) => {
    return (
      <input
        type={type}
        ref={ref}
        className={cn(
          "flex h-10 w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm",
          "placeholder:text-zinc-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-900",
          className
        )}
        {...props}
      />
    )
  }
)
Input.displayName = "Input"
""",
}

BLOCKS = {
    "hero-centered.tsx": """import { Button } from "@/components/ui/button"

export function HeroCentered() {
  return (
    <section className="mx-auto max-w-5xl px-6 py-24 text-center">
      <p className="mb-3 text-sm font-semibold uppercase tracking-wider text-zinc-500">WHOX Block</p>
      <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">Build with local WHOX shadcn blocks</h1>
      <p className="mx-auto mt-6 max-w-2xl text-zinc-600">
        Fast, isolated app creation with reusable UI building blocks.
      </p>
      <div className="mt-10 flex items-center justify-center gap-3">
        <Button>Get Started</Button>
        <Button variant="outline">View Demo</Button>
      </div>
    </section>
  )
}
""",
    "features-grid.tsx": """import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"

const ITEMS = [
  { title: "Isolated Workspaces", text: "Each app is generated in its own folder and lifecycle." },
  { title: "Reusable UI", text: "Prebuilt local shadcn components and blocks for consistency." },
  { title: "Fast Delivery", text: "No remote registry required to start building." },
]

export function FeaturesGrid() {
  return (
    <section className="mx-auto grid max-w-6xl gap-6 px-6 pb-20 md:grid-cols-3">
      {ITEMS.map((item) => (
        <Card key={item.title}>
          <CardHeader>
            <CardTitle>{item.title}</CardTitle>
            <CardDescription>WHOX Block</CardDescription>
          </CardHeader>
          <CardContent>{item.text}</CardContent>
        </Card>
      ))}
    </section>
  )
}
""",
}

UTILS_FILE = """import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
"""

TAILWIND_HINT = """@tailwind base;
@tailwind components;
@tailwind utilities;
"""


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def whox_shadcn_library_root() -> Path:
    return get_whox_home() / "library" / "shadcn"


def _has_catalog_layout(root: Path) -> bool:
    return (root / "components" / "CATALOG.json").exists() and (root / "blocks" / "CATALOG.json").exists()


def ensure_whox_shadcn_library() -> Path:
    root = whox_shadcn_library_root()
    if _has_catalog_layout(root):
        return root

    ui_dir = root / "components" / "ui"
    blocks_dir = root / "blocks"
    meta_dir = root / "meta"
    examples_dir = root / "examples"

    for filename, content in UI_COMPONENTS.items():
        _write(ui_dir / filename, content)
    for filename, content in BLOCKS.items():
        _write(blocks_dir / filename, content)

    _write(root / "utils" / "cn.ts", UTILS_FILE)
    _write(root / "styles" / "tailwind.css", TAILWIND_HINT)

    catalog = {
        "name": "WHOX Local shadcn Library",
        "version": "1.0.0",
        "categories": {
            "ui": {
                "description": "Reusable UI primitives.",
                "files": sorted(UI_COMPONENTS.keys()),
            },
            "blocks": {
                "description": "Composable page sections.",
                "files": sorted(BLOCKS.keys()),
            },
        },
        "notes": [
            "Generated locally by WHOX",
            "Each app workspace can copy these files for isolated use",
        ],
    }
    _write(meta_dir / "catalog.json", json.dumps(catalog, indent=2))
    _write(
        meta_dir / "README.md",
        "\n".join(
            [
                "# WHOX Local shadcn Library",
                "",
                "This folder stores local reusable shadcn-style components and blocks.",
                "It is intended to be copied into isolated app workspaces.",
                "",
                "Core locations:",
                "- `components/ui/` primitive components",
                "- `blocks/` page blocks",
                "- `utils/cn.ts` class merge helper",
                "- `styles/tailwind.css` tailwind directives reference",
            ]
        ),
    )
    _write(
        examples_dir / "page.tsx",
        "\n".join(
            [
                'import { HeroCentered } from "@/components/blocks/hero-centered"',
                'import { FeaturesGrid } from "@/components/blocks/features-grid"',
                "",
                "export default function Page() {",
                "  return (",
                "    <main>",
                "      <HeroCentered />",
                "      <FeaturesGrid />",
                "    </main>",
                "  )",
                "}",
            ]
        ),
    )

    return root


def _seed_workspace_from_catalog_layout(workspace_root: Path, library_root: Path) -> dict[str, str]:
    frontend = workspace_root / "frontend"
    ui_target = frontend / "src" / "components" / "ui"
    blocks_target = frontend / "src" / "components" / "blocks"
    lib_target = frontend / "src" / "lib"
    styles_target = frontend / "src" / "styles"
    catalog_target = frontend / "src" / "components" / ".whox-shadcn"

    ui_target.mkdir(parents=True, exist_ok=True)
    blocks_target.mkdir(parents=True, exist_ok=True)
    lib_target.mkdir(parents=True, exist_ok=True)
    styles_target.mkdir(parents=True, exist_ok=True)
    catalog_target.mkdir(parents=True, exist_ok=True)

    components_catalog = library_root / "components" / "CATALOG.json"
    blocks_catalog = library_root / "blocks" / "CATALOG.json"

    comp_items = json.loads(components_catalog.read_text(encoding="utf-8")).get("items", [])
    block_items = json.loads(blocks_catalog.read_text(encoding="utf-8")).get("items", [])

    # Components: copy the source files from each catalog item into frontend/src/components/ui.
    # Later items may overwrite identical files; this is acceptable for canonical primitives.
    for item in comp_items:
        name = item.get("name", "")
        files_root = library_root / "components" / name / "files"
        if not files_root.exists():
            continue
        for src in files_root.rglob("*"):
            if not src.is_file():
                continue
            rel = src.relative_to(files_root)
            dst = ui_target / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    # Blocks: preserve per-block folder boundaries to avoid filename collisions.
    for item in block_items:
        name = item.get("name", "")
        files_root = library_root / "blocks" / name / "files"
        if not files_root.exists():
            continue
        dst_root = blocks_target / name
        for src in files_root.rglob("*"):
            if not src.is_file():
                continue
            rel = src.relative_to(files_root)
            dst = dst_root / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    # Copy catalogs into workspace for deterministic component/block selection.
    shutil.copy2(components_catalog, catalog_target / "components.CATALOG.json")
    shutil.copy2(blocks_catalog, catalog_target / "blocks.CATALOG.json")

    # Ensure minimal shared helpers exist.
    (lib_target / "utils.ts").write_text(UTILS_FILE.rstrip() + "\n", encoding="utf-8")
    (styles_target / "tailwind.css").write_text(TAILWIND_HINT.rstrip() + "\n", encoding="utf-8")

    return {
        "library_root": str(library_root),
        "ui_target": str(ui_target),
        "blocks_target": str(blocks_target),
        "utils_target": str(lib_target / "utils.ts"),
        "styles_target": str(styles_target / "tailwind.css"),
        "components_catalog": str(catalog_target / "components.CATALOG.json"),
        "blocks_catalog": str(catalog_target / "blocks.CATALOG.json"),
    }


def _seed_workspace_from_legacy_layout(workspace_root: Path, library_root: Path) -> dict[str, str]:
    frontend = workspace_root / "frontend"
    ui_target = frontend / "src" / "components" / "ui"
    blocks_target = frontend / "src" / "components" / "blocks"
    lib_target = frontend / "src" / "lib"
    styles_target = frontend / "src" / "styles"

    ui_target.mkdir(parents=True, exist_ok=True)
    blocks_target.mkdir(parents=True, exist_ok=True)
    lib_target.mkdir(parents=True, exist_ok=True)
    styles_target.mkdir(parents=True, exist_ok=True)

    for src in (library_root / "components" / "ui").glob("*.tsx"):
        shutil.copy2(src, ui_target / src.name)
    for src in (library_root / "blocks").glob("*.tsx"):
        shutil.copy2(src, blocks_target / src.name)
    shutil.copy2(library_root / "utils" / "cn.ts", lib_target / "utils.ts")
    shutil.copy2(library_root / "styles" / "tailwind.css", styles_target / "tailwind.css")

    return {
        "library_root": str(library_root),
        "ui_target": str(ui_target),
        "blocks_target": str(blocks_target),
        "utils_target": str(lib_target / "utils.ts"),
        "styles_target": str(styles_target / "tailwind.css"),
    }


def seed_workspace_from_shadcn_library(workspace_root: Path) -> dict[str, str]:
    """
    Copy the local WHOX shadcn library into an isolated app workspace.
    """
    library_root = ensure_whox_shadcn_library()
    if _has_catalog_layout(library_root):
        return _seed_workspace_from_catalog_layout(workspace_root, library_root)
    return _seed_workspace_from_legacy_layout(workspace_root, library_root)
