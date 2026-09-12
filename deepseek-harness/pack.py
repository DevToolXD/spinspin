#!/usr/bin/env python3
"""웹 채팅에 붙여넣을 컨텍스트 한 덩어리를 만든다.

웹 채팅은 grep을 못 하므로 관련 파일을 사람이 넣어줘야 한다. 이 스크립트가
파일 트리와 선택한 파일들을 경로 헤더를 붙여 하나로 합치고, 대략적인 토큰 수를
찍어준다.

    python3 pack.py                      # 현재 repo 전체 (기본 필터 적용)
    python3 pack.py -i '*.js' -i '*.css' # 확장자로 추리기
    python3 pack.py src/ lib/utils.py    # 경로로 추리기
    python3 pack.py --tree               # 트리만 (뭘 넣을지 고를 때)

의존성 없음. 표준 라이브러리만 쓴다.
"""

from __future__ import annotations

import argparse
import fnmatch
import subprocess
import sys
from pathlib import Path

# 넣어봐야 컨텍스트만 먹는 것들. --all 로 끌 수 있다.
SKIP_PATTERNS = [
    "*.lock", "*-lock.json", "*.min.js", "*.min.css", "*.map",
    "*.png", "*.jpg", "*.jpeg", "*.gif", "*.svg", "*.ico", "*.webp",
    "*.pdf", "*.zip", "*.tar", "*.gz", "*.woff*", "*.ttf", "*.eot",
    "*.pyc", "*.so", "*.dylib", "*.dll", "*.exe", "*.wasm",
    "*.snap", "*.pb", "*.onnx", "*.bin",
]
SKIP_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build",
    ".next", ".nuxt", "target", "vendor", ".pytest_cache", ".mypy_cache",
    "coverage", ".idea", ".vscode",
}

# 확장자 → 코드 펜스 언어. 모델이 문법을 바로 잡는다.
FENCE = {
    ".py": "python", ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".ts": "typescript", ".tsx": "tsx", ".jsx": "jsx", ".go": "go", ".rs": "rust",
    ".java": "java", ".kt": "kotlin", ".swift": "swift", ".rb": "ruby", ".php": "php",
    ".c": "c", ".h": "c", ".cpp": "cpp", ".hpp": "cpp", ".cs": "csharp",
    ".sh": "bash", ".bash": "bash", ".zsh": "bash", ".fish": "fish",
    ".html": "html", ".css": "css", ".scss": "scss", ".sql": "sql",
    ".json": "json", ".yaml": "yaml", ".yml": "yaml", ".toml": "toml",
    ".xml": "xml", ".md": "markdown", ".dockerfile": "dockerfile",
}

# 한글이 섞인 소스는 영어보다 토큰이 더 나온다. 넉넉하게 잡아 과소평가를 피한다.
CHARS_PER_TOKEN = 3.0


def repo_files(root: Path) -> list[Path]:
    """git이 아는 파일 목록. .gitignore가 자동으로 반영된다."""
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"],
            capture_output=True, text=True, timeout=30, check=True,
        )
        return [root / line for line in result.stdout.splitlines() if line]
    except (subprocess.SubprocessError, FileNotFoundError):
        # git repo가 아니면 직접 훑는다.
        out = []
        for path in root.rglob("*"):
            if path.is_file() and not any(part in SKIP_DIRS for part in path.parts):
                out.append(path)
        return out


def should_skip(path: Path, root: Path, use_filters: bool) -> bool:
    if any(part in SKIP_DIRS for part in path.relative_to(root).parts[:-1]):
        return True
    if not use_filters:
        return False
    name = path.name.lower()
    return any(fnmatch.fnmatch(name, pattern) for pattern in SKIP_PATTERNS)


def matches(path: Path, root: Path, includes: list[str], targets: list[str]) -> bool:
    rel = str(path.relative_to(root))
    if targets and not any(rel == t or rel.startswith(t.rstrip("/") + "/") for t in targets):
        return False
    if includes and not any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(path.name, p) for p in includes):
        return False
    return True


def read_text(path: Path) -> str | None:
    """텍스트 파일이면 내용, 바이너리면 None."""
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in raw[:8192]:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def build_tree(paths: list[Path], root: Path) -> str:
    """디렉터리별로 묶은 납작한 트리. 모델이 구조를 파악하는 용도."""
    by_dir: dict[str, list[str]] = {}
    for path in sorted(paths):
        rel = path.relative_to(root)
        by_dir.setdefault(str(rel.parent), []).append(rel.name)

    lines = []
    for directory in sorted(by_dir):
        prefix = "" if directory == "." else f"{directory}/"
        for name in sorted(by_dir[directory]):
            lines.append(f"  {prefix}{name}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="웹 채팅에 붙여넣을 컨텍스트 한 덩어리를 만든다.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("의존성")[0].split("\n\n", 2)[-1],
    )
    parser.add_argument("targets", nargs="*", help="넣을 파일/폴더. 없으면 전체.")
    parser.add_argument("-i", "--include", action="append", default=[],
                        help="glob 필터. 여러 번 쓸 수 있다. 예: -i '*.js'")
    parser.add_argument("-r", "--root", default=".", help="repo 루트. 기본 '.'")
    parser.add_argument("-o", "--out", default="context.md", help="출력 파일. 기본 context.md")
    parser.add_argument("--tree", action="store_true", help="트리만 출력하고 끝낸다.")
    parser.add_argument("--all", action="store_true", help="기본 필터(락파일·이미지 등) 끄기.")
    parser.add_argument("--max-kb", type=int, default=100, help="파일 하나 최대 크기(KB). 기본 100")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"디렉터리가 아님: {root}", file=sys.stderr)
        return 1

    candidates = [
        p for p in repo_files(root)
        if p.is_file()
        and not should_skip(p, root, not args.all)
        and matches(p, root, args.include, args.targets)
    ]

    if args.tree:
        print(f"{root.name}/ — 파일 {len(candidates)}개\n")
        print(build_tree(candidates, root))
        return 0

    if not candidates:
        print("조건에 맞는 파일이 없음. --tree 로 먼저 확인해 보세요.", file=sys.stderr)
        return 1

    chunks: list[str] = []
    included: list[tuple[str, int]] = []
    skipped: list[tuple[str, str]] = []

    for path in sorted(candidates):
        rel = str(path.relative_to(root))
        if path.stat().st_size > args.max_kb * 1024:
            skipped.append((rel, f"{path.stat().st_size // 1024}KB — --max-kb 초과"))
            continue
        text = read_text(path)
        if text is None:
            skipped.append((rel, "바이너리"))
            continue
        lang = FENCE.get(path.suffix.lower(), "")
        chunks.append(f"### {rel}\n\n```{lang}\n{text.rstrip()}\n```")
        included.append((rel, len(text)))

    body = (
        f"# {root.name}\n\n"
        f"## 파일 트리\n\n```\n{build_tree([root / r for r, _ in included], root)}\n```\n\n"
        f"## 파일 내용\n\n" + "\n\n".join(chunks) + "\n"
    )

    out_path = Path(args.out)
    out_path.write_text(body, encoding="utf-8")

    tokens = int(len(body) / CHARS_PER_TOKEN)
    print(f"✓ {out_path}  —  파일 {len(included)}개, {len(body):,}자, 약 {tokens:,} 토큰")

    if tokens > 50_000:
        print(f"\n  ⚠ 큽니다. 관련 파일만 추리는 게 답변 품질에 낫습니다.")
        print(f"    예: python3 {sys.argv[0]} -i '*.js' 또는 경로를 직접 지정")

    if included:
        print("\n  큰 파일부터:")
        for rel, size in sorted(included, key=lambda x: -x[1])[:5]:
            print(f"    {size // CHARS_PER_TOKEN:>8,.0f} 토큰  {rel}")

    if skipped:
        print(f"\n  건너뜀 {len(skipped)}개:")
        for rel, why in skipped[:5]:
            print(f"    {rel} ({why})")
        if len(skipped) > 5:
            print(f"    ... 외 {len(skipped) - 5}개")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
