#!/usr/bin/env python3
"""Fail-closed release gate for the in-App privacy policy Dart source."""

from __future__ import annotations

import pathlib
import re
import sys


def _strip_comments(source: str) -> str:
    """Remove Dart comments without treating comment markers in strings as code."""
    out: list[str] = []
    i = 0
    block_depth = 0
    quote = ''
    while i < len(source):
        if block_depth:
            if source.startswith('/*', i):
                block_depth += 1
                i += 2
            elif source.startswith('*/', i):
                block_depth -= 1
                i += 2
            else:
                out.append('\n' if source[i] == '\n' else ' ')
                i += 1
            continue
        if quote:
            if source.startswith(quote, i):
                out.append(quote)
                i += len(quote)
                quote = ''
            elif source[i] == '\\':
                out.append(source[i:i + 2])
                i += 2
            else:
                out.append(source[i])
                i += 1
            continue
        if source.startswith('//', i):
            end = source.find('\n', i)
            if end < 0:
                out.extend(' ' for _ in source[i:])
                break
            out.extend(' ' for _ in source[i:end])
            i = end
            continue
        if source.startswith('/*', i):
            block_depth = 1
            out.extend((' ', ' '))
            i += 2
            continue
        if source.startswith("'''", i) or source.startswith('"""', i):
            quote = source[i:i + 3]
            out.append(quote)
            i += 3
            continue
        if source[i] in "'\"":
            quote = source[i]
            out.append(source[i])
            i += 1
            continue
        out.append(source[i])
        i += 1
    return ''.join(out)


def _balanced(source: str, start: int, opening: str, closing: str) -> str | None:
    depth = 0
    quote = ''
    i = start
    while i < len(source):
        if quote:
            if source.startswith(quote, i):
                i += len(quote)
                quote = ''
            elif source[i] == '\\':
                i += 2
            else:
                i += 1
            continue
        if source.startswith("'''", i) or source.startswith('"""', i):
            quote = source[i:i + 3]
            i += 3
            continue
        if source[i] in "'\"":
            quote = source[i]
            i += 1
            continue
        if source[i] == opening:
            depth += 1
        elif source[i] == closing:
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    return None


def _string_field(block: str, name: str) -> str | None:
    match = re.search(
        rf'\b{re.escape(name)}\s*:\s*(?:const\s+)?([\'\"])(.*?)\1',
        block,
        re.S,
    )
    return match.group(2).strip() if match else None


def inspect_privacy_policy(source: str) -> tuple[bool, list[str], int, str, str]:
    code = _strip_comments(source)
    entry = re.search(
        r'\bLegalDocType\.privacyPolicy\s*:\s*(?:const\s+)?LegalDoc\s*\(',
        code,
    )
    if entry is None:
        return False, ['privacyPolicy 构造体缺失'], 0, '', ''
    opening = code.find('(', entry.start())
    block = _balanced(code, opening, '(', ')')
    if block is None:
        return False, ['privacyPolicy 构造体括号不完整'], 0, '', ''

    version = _string_field(block, 'version') or ''
    updated_at = _string_field(block, 'updatedAt') or ''
    sections_match = re.search(
        r'\bsections\s*:\s*(?:const\s*)?(?:<\s*LegalSection\s*>\s*)?\[',
        block,
    )
    section_count = 0
    if sections_match is not None:
        list_start = block.find('[', sections_match.start())
        section_list = _balanced(block, list_start, '[', ']')
        if section_list is not None:
            section_count = len(re.findall(r'\bLegalSection\s*\(', section_list))

    failures: list[str] = []
    if section_count == 0:
        failures.extend(('pending=true', 'sections 为空'))
    if not version:
        failures.append('version 为空')
    if not updated_at:
        failures.append('updatedAt 为空')
    return not failures, failures, section_count, version, updated_at


def main(argv: list[str]) -> int:
    default = pathlib.Path(__file__).resolve().parents[1] / 'lib/feature/legal/legal_docs.dart'
    path = pathlib.Path(argv[1]) if len(argv) > 1 else default
    try:
        source = path.read_text(encoding='utf-8')
    except OSError as error:
        print(f'隐私政策门禁失败:无法读取 {path}:{error}')
        return 2
    valid, failures, count, version, updated_at = inspect_privacy_policy(source)
    if not valid:
        print('隐私政策门禁失败:' + '; '.join(failures))
        return 1
    print(
        '隐私政策门禁通过:pending=false'
        f' · sections={count} · version={version} · updatedAt={updated_at}'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
