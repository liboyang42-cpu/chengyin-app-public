#!/usr/bin/env python3
"""Generate App design-token values from the Mini Program tokens.wxss."""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = (
    Path(os.environ["CY_TOKENS_WXSS"])
    if os.environ.get("CY_TOKENS_WXSS")
    else Path.home() / "Downloads/chengyin/chengyinhub-xcx/style/tokens.wxss"
)
DEFAULT_OUTPUT = ROOT / "lib/core/theme/cy_tokens.g.dart"
ALLOWLIST = ROOT / "tool/token_allowlist.txt"
TOKEN_NAME = re.compile(r"--cy-[a-z0-9-]+")
DECLARATION = re.compile(r"(--cy-[a-z0-9-]+)\s*:\s*([^;]+);")
VAR_REFERENCE = re.compile(r"var\(\s*(--cy-[a-z0-9-]+)\s*\)")


class TokenError(RuntimeError):
    pass


def _without_comments(source: str) -> str:
    def blank(match: re.Match[str]) -> str:
        text = match.group(0)
        return "".join("\n" if char == "\n" else " " for char in text)

    return re.sub(r"/\*.*?\*/", blank, source, flags=re.DOTALL)


def parse_theme_blocks(source: str) -> dict[str, dict[str, str]]:
    """Parse all four top-level theme rules, including multiline selectors."""
    clean = _without_comments(source)
    rules: list[tuple[str, str]] = []
    selector_start = 0
    body_start = 0
    depth = 0
    selector = ""
    for index, char in enumerate(clean):
        if char == "{":
            if depth == 0:
                selector = clean[selector_start:index].strip()
                body_start = index + 1
            depth += 1
        elif char == "}":
            depth -= 1
            if depth < 0:
                raise TokenError("tokens.wxss 的大括号不配对")
            if depth == 0:
                rules.append((selector, clean[body_start:index]))
                selector_start = index + 1
    if depth != 0:
        raise TokenError("tokens.wxss 的大括号不配对")

    blocks: dict[str, dict[str, str]] = {}
    for selectors, body in rules:
        selector_set = {
            item.strip() for item in selectors.split(",") if item.strip()
        }
        block_name: str | None = None
        if selector_set == {"page"}:
            block_name = "default"
        elif ".theme-light" in selector_set or ".theme-merchant" in selector_set:
            block_name = "light"
        elif ".theme-topic-editor" in selector_set:
            block_name = "topicEditor"
        elif ".theme-dark" in selector_set:
            block_name = "dark"
        if block_name is None:
            continue
        declarations: dict[str, str] = {}
        for match in DECLARATION.finditer(body):
            declarations[match.group(1)] = match.group(2).strip()
        blocks[block_name] = declarations

    missing = {"default", "light", "topicEditor", "dark"} - blocks.keys()
    if missing:
        raise TokenError(f"没有解析到主题块：{', '.join(sorted(missing))}")
    return blocks


def read_allowlist(path: Path) -> list[str]:
    tokens: list[str] = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|", maxsplit=1)]
        if len(parts) != 2 or not TOKEN_NAME.fullmatch(parts[0]) or not parts[1]:
            raise TokenError(
                f"{path}:{line_number} 必须是 '<token> | <为什么需要它>'"
            )
        tokens.append(parts[0])
    duplicates = sorted({token for token in tokens if tokens.count(token) > 1})
    if duplicates:
        raise TokenError(f"allowlist 有重复 token：{', '.join(duplicates)}")
    return tokens


def resolve_token(
    token: str,
    values: dict[str, str],
    cache: dict[str, str],
    stack: tuple[str, ...] = (),
) -> str | None:
    if token in cache:
        return cache[token]
    if token in stack:
        chain = " -> ".join((*stack, token))
        raise TokenError(f"var() 循环引用：{chain}")
    raw = values.get(token)
    if raw is None:
        return None
    reference = VAR_REFERENCE.fullmatch(raw)
    if reference is None:
        cache[token] = raw
        return raw
    resolved = resolve_token(reference.group(1), values, cache, (*stack, token))
    if resolved is not None:
        cache[token] = resolved
    return resolved


def resolve_snapshot(values: dict[str, str]) -> dict[str, str]:
    """Resolve every alias once, matching WXSS custom-property snapshots."""
    cache: dict[str, str] = {}
    resolved: dict[str, str] = {}
    for token in values:
        value = resolve_token(token, values, cache)
        if value is not None:
            resolved[token] = value
    return resolved


def _dart_number(value: float) -> str:
    if value.is_integer():
        return str(int(value))
    return f"{value:.8f}".rstrip("0").rstrip(".")


def _dart_color(raw: str) -> str | None:
    compact = re.sub(r"\s+", "", raw).lower()
    hex_match = re.fullmatch(r"#([0-9a-f]{3,8})", compact)
    if hex_match:
        digits = hex_match.group(1)
        if len(digits) in {3, 4}:
            digits = "".join(char * 2 for char in digits)
        if len(digits) == 6:
            red_green_blue, alpha = digits, "ff"
        elif len(digits) == 8:
            red_green_blue, alpha = digits[:6], digits[6:]
        else:
            return None
        return f"Color(0x{alpha.upper()}{red_green_blue.upper()})"

    rgba = re.fullmatch(
        r"rgba?\((\d+),(\d+),(\d+)(?:,([\d.]+))?\)", compact
    )
    if rgba:
        channels = [int(rgba.group(index)) for index in range(1, 4)]
        alpha_value = float(rgba.group(4) or "1")
        if any(channel < 0 or channel > 255 for channel in channels):
            return None
        if alpha_value < 0 or alpha_value > 1:
            return None
        alpha = math.floor(alpha_value * 255 + 0.5)
        argb = f"{alpha:02X}{channels[0]:02X}{channels[1]:02X}{channels[2]:02X}"
        return f"Color(0x{argb})"
    return None


def _dart_duration(raw: str) -> str | None:
    match = re.fullmatch(r"(\d+)ms", re.sub(r"\s+", "", raw))
    if match is None:
        return None
    return f"Duration(milliseconds: {int(match.group(1))})"


def _dart_curve(raw: str) -> str | None:
    match = re.fullmatch(
        r"cubic-bezier\(([^)]*)\)", re.sub(r"\s+", "", raw).lower()
    )
    if match is None:
        return None
    parts = match.group(1).split(",")
    if len(parts) != 4:
        return None
    try:
        numbers = [float(part) for part in parts]
    except ValueError:
        return None
    # 控制点的 x 必须落在 [0,1]，否则 Flutter 的 Cubic 求解会发散。
    if not (0 <= numbers[0] <= 1 and 0 <= numbers[2] <= 1):
        return None
    return f"Cubic({', '.join(_dart_number(number) for number in numbers)})"


def to_dart_value(raw: str) -> tuple[str, str] | None:
    color = _dart_color(raw)
    if color is not None:
        return "Color", color
    duration = _dart_duration(raw)
    if duration is not None:
        return "Duration", duration
    curve = _dart_curve(raw)
    if curve is not None:
        return "Curve", curve
    compact = raw.strip()
    scaled_rpx = re.fullmatch(
        r"calc\(\s*(-?(?:\d+(?:\.\d+)?|\.\d+))rpx"
        r"\s*\*\s*var\(\s*--cy-type-scale\s*\)\s*\)",
        compact,
    )
    if scaled_rpx:
        return "double", _dart_number(float(scaled_rpx.group(1)) / 2)
    rpx = re.fullmatch(r"(-?(?:\d+(?:\.\d+)?|\.\d+))rpx", compact)
    if rpx:
        return "double", _dart_number(float(rpx.group(1)) / 2)
    number = re.fullmatch(r"-?(?:\d+(?:\.\d+)?|\.\d+)", compact)
    if number:
        return "double", _dart_number(float(number.group(0)))
    return None


def dart_name(token: str) -> str:
    parts = token.removeprefix("--cy-").split("-")
    name = parts[0]
    for part in parts[1:]:
        if name[-1].isdigit() and part[0].isdigit():
            name += f"_{part}"
        else:
            name += part[:1].upper() + part[1:]
    return name


def render_class(
    class_name: str,
    tokens: list[str],
    values: dict[str, str],
) -> tuple[list[str], list[str], list[tuple[str, str]]]:
    lines = [f"abstract final class {class_name} {{"]
    missing: list[str] = []
    skipped: list[tuple[str, str]] = []
    cache: dict[str, str] = {}
    names: set[str] = set()
    for token in tokens:
        name = dart_name(token)
        if name in names:
            raise TokenError(f"Dart 名称冲突：{token} -> {name}")
        names.add(name)
        resolved = resolve_token(token, values, cache)
        if resolved is None:
            missing.append(token)
            continue
        converted = to_dart_value(resolved)
        if converted is None:
            skipped.append((token, resolved))
            continue
        dart_type, dart_value = converted
        lines.append(f"  // {token}: {resolved}")
        lines.append(f"  static const {dart_type} {name} = {dart_value};")
        lines.append("")
    if lines[-1] == "":
        lines.pop()
    lines.append("}")
    return lines, missing, skipped


def generate(source: Path, output: Path) -> None:
    blocks = parse_theme_blocks(source.read_text())
    tokens = read_allowlist(ALLOWLIST)
    default_values = resolve_snapshot(blocks["default"])
    theme_values = {
        name: resolve_snapshot({**default_values, **blocks[name]})
        for name in ("light", "topicEditor", "dark")
    }
    light_values = theme_values["light"]
    default_lines, default_missing, default_skipped = render_class(
        "CyGeneratedTokens", tokens, default_values
    )
    light_lines, light_missing, light_skipped = render_class(
        "CyGeneratedLightTokens", tokens, light_values
    )

    generated = "\n".join(
        [
            "// 本文件由 tool/gen_tokens.py 生成，禁止手改；改值请改 tokens.wxss。",
            "// 生成范围由 tool/token_allowlist.txt 控制。",
            "",
            "import 'package:flutter/material.dart';",
            "",
            *default_lines,
            "",
            *light_lines,
            "",
        ]
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generated)

    missing = sorted(set(default_missing + light_missing))
    skipped = default_skipped + light_skipped
    generated_count = sum(
        1 for line in generated.splitlines() if line.startswith("  static const ")
    )
    shapes: dict[str, int] = {}
    for _, raw in skipped:
        shape = raw.split("(", maxsplit=1)[0] if "(" in raw else raw
        shapes[shape] = shapes.get(shape, 0) + 1
    shape_summary = ", ".join(f"{key}={value}" for key, value in sorted(shapes.items()))
    print(
        f"[token-codegen] 生成 {generated_count} 条 / 跳过 {len(skipped)} 条"
        f"{f' ({shape_summary})' if shape_summary else ''} / "
        f"allowlist 未找到 {len(missing)} 条"
    )
    print(
        "[token-codegen] 主题块唯一 token："
        + " / ".join(f"{name}={len(blocks[name])}" for name in blocks)
    )
    if missing:
        print("[token-codegen] 未找到：" + ", ".join(missing), file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        generate(args.source, args.output)
    except (OSError, TokenError) as error:
        print(f"[token-codegen] 失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
