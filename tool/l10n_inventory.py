#!/usr/bin/env python3
"""Static localization inventory. Candidates are not automatically UI or translations.

No user content is loaded and no strings are translated. An English acceptance
claim requires complete extraction review AND Flutter/native runtime evidence.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import plistlib
import re

HAN = re.compile(r'[\u3400-\u9fff]')
PLACEHOLDER = re.compile(r'\{([A-Za-z_]\w*)\s*(?:,|\})')


def plural_pound_positions(message):
    """Find shorthand counters with escaping disabled (this repo's l10n.yaml).

    Flutter 3.44.2 emits these as literal text. Track the nearest enclosing
    plural, including nested/multiple expressions; ordinary # labels stay put.
    This is a focused compatibility guard, not a general ICU parser.
    """
    scopes = [None]
    positions = []
    for index, char in enumerate(message):
        if char == '{':
            header = re.match(r'\{\s*(\w+)\s*,\s*plural\s*,', message[index:])
            scopes.append(header.group(1) if header else scopes[-1])
        elif char == '}' and len(scopes) > 1:
            scopes.pop()
        elif char == '#' and scopes[-1] is not None:
            positions.append((index, scopes[-1]))
    return positions


def literals(source):
    """Skip comments; yield string tokens with locations. Interpolations need review."""
    i, line = 0, 1
    while i < len(source):
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
            continue
        if source.startswith('/*', i):
            level = 1
            i += 2
            while i < len(source) and level:
                if source.startswith('/*', i):
                    level += 1
                    i += 2
                elif source.startswith('*/', i):
                    level -= 1
                    i += 2
                else:
                    line += source[i] == '\n'
                    i += 1
            continue
        raw = source[i:i+1] == 'r' and source[i+1:i+2] in ["'", '"']
        start = i + 1 if raw else i
        if source[start:start+1] in ["'", '"']:
            quote = source[start]
            delim = quote * 3 if source.startswith(quote * 3, start) else quote
            i = start + len(delim)
            body, start_line = i, line
            while i < len(source) and not source.startswith(delim, i):
                if source[i] == '\\' and not raw:
                    line += source[i+1:i+2] == '\n'
                    i += 2
                else:
                    line += source[i] == '\n'
                    i += 1
            yield start_line, source[body:i]
            i += len(delim)
            continue
        line += source[i] == '\n'
        i += 1


def arb_errors(template, translated):
    keys = {k for k in template if not k.startswith('@')}
    actual = {k for k in translated if not k.startswith('@')}
    errors = [f'missing:{key}' for key in sorted(keys - actual)]
    errors += [f'extra:{key}' for key in sorted(actual - keys)]
    for key in sorted(keys & actual):
        original, value = template[key], translated[key]
        if not isinstance(original, str) or not isinstance(value, str) or not value.strip():
            errors.append(f'invalid-message:{key}')
            continue
        expected = set(PLACEHOLDER.findall(original))
        received = set(PLACEHOLDER.findall(value))
        if expected != received:
            errors.append(f'placeholder-mismatch:{key}')
        metadata = template.get('@' + key, {})
        declared = metadata.get('placeholders', {}) if isinstance(metadata, dict) else {}
        if expected and set(declared) != expected:
            errors.append(f'placeholder-metadata-mismatch:{key}')
        for name in expected:
            if name in {'class', 'return', 'switch', 'case', 'default', 'if', 'else',
                        'for', 'while', 'do', 'try', 'catch', 'finally', 'throw',
                        'const', 'final', 'var', 'void', 'new', 'this', 'super',
                        'true', 'false', 'null', 'required'}:
                errors.append(f'placeholder-invalid-identifier:{key}:{name}')
        if re.search(r',\s*plural\s*,', value) and not re.search(r'other\s*\{', value):
            errors.append(f'plural-missing-other:{key}')
        # Numeric selectors must agree with generated Dart argument types. This
        # is a lexical guard, not ICU parsing or a substitute for gen-l10n.
        selectors = set(re.findall(r'\{(\w+)\s*,\s*plural\s*,', original + '\n' + value))
        for name in sorted(selectors):
            spec = declared.get(name, {})
            if not isinstance(spec, dict) or spec.get('type') not in {'int', 'double', 'num'}:
                errors.append(f'plural-nonnumeric-placeholder:{key}:{name}')
        for locale, message in [('template', original), ('translation', value)]:
            if plural_pound_positions(message):
                errors.append(f'plural-literal-pound:{key}:{locale}')
        # Language chooser uses the native language name deliberately in every locale.
        # Exact exceptions: language autonym and a literal real-world clue.
        # Translating the sign character would change the gameplay target.
        preserved_literals = {
            'chineseLanguage': '简体中文',
            'prefabSceneSignPrompt': 'Is there a sign along the road with the character “新” (new)?',
        }
        # Legal identities/registered addresses remain verbatim source data.
        legal_identity_keys = {
            'legalDraftUserAgreementIntro', 'legalDraftUserAgreementSection1Body',
            'legalDraftUserAgreementSection13Body', 'legalDraftCancellationNoticeSection5Body',
        }
        checked_value = value
        if key in legal_identity_keys:
            checked_value = checked_value.replace('西安吾令文化传媒有限公司', '')
            if key in {'legalDraftUserAgreementSection1Body', 'legalDraftUserAgreementSection13Body'}:
                checked_value = checked_value.replace('陕西省西安市高新区锦业路1号绿地领海B座6层604室A043号', '')
        if HAN.search(checked_value) and preserved_literals.get(key) != value:
            errors.append(f'chinese-in-english:{key}')
    return errors


def resource_references(source):
    """Conservative source references; not Dart parsing or generated-code analysis."""
    source = re.sub(r"(?m)^\s*(?:import|export|part)\b[^\n]*", "", source)
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    declarations = list(re.finditer(
        r'(?m)^(?P<indent>[ \t]*)(?:final(?:\s+AppLocalizations)?|AppLocalizations)\s+(?P<alias>\w+)\s*=\s*stringsOf\([^)]*\)\s*;', source))
    keys = set(re.findall(r'stringsOf\([^)]*\)\.(\w+)', source))
    keys.update(re.findall(r'ref\.read\(appStringsProvider\)\.(\w+)', source))
    for declaration in declarations:
        # Bound an alias to its containing indented block, not every variable
        # with that name elsewhere in the file. This remains a conservative
        # source check; the Dart analyzer is authoritative for lexical scopes.
        tail = source[declaration.end():]
        width = len(declaration['indent'].expandtabs(2))
        end = re.search(r'(?m)^[ \t]{0,' + str(max(0, width - 1)) + r'}\}', tail)
        region = tail[:end.start()] if end else tail
        keys.update(re.findall(r'\b' + re.escape(declaration['alias']) + r'\.(\w+)', region))
    return keys - {'localeName'}


def inventory(root):
    rows, regions, backend = [], [], []
    dart_paths = sorted((root / 'lib').rglob('*.dart'))
    for path in dart_paths + sorted((root / 'ios/Runner').rglob('*.swift')):
        relative = path.relative_to(root).as_posix()
        source = path.read_text(encoding='utf-8')
        for line, value in literals(source):
            if HAN.search(value):
                rows.append({'path': relative, 'line': line, 'text': value,
                             'interpolationReview': '$' in value or '\\(' in value,
                             'textFingerprint': hashlib.sha256(value.encode()).hexdigest()[:16]})
            if any(mark in value for mark in ['¥', '￥', 'CNY', 'USD', 'Asia/Shanghai', 'zh_CN']):
                regions.append({'path': relative, 'line': line, 'text': value})
        for line, value in enumerate(source.splitlines(), 1):
            if re.search(r'friendlyOrBackendMessage|\[.msg.\]|\.message\b', value):
                backend.append({'path': relative, 'line': line})
    permissions = {}
    info_path = root / 'ios/Runner/Info.plist'
    if info_path.exists():
        info = plistlib.loads(info_path.read_bytes())
        permissions = {k: v for k, v in info.items() if k.endswith('UsageDescription')}
    arbs = {p.stem: json.loads(p.read_text()) for p in sorted((root / 'lib').rglob('*.arb'))}
    errors = arb_errors(arbs.get('app_zh', {}), arbs.get('app_en', {}))
    if not arbs.get('app_zh') or not arbs.get('app_en'):
        errors.append('missing-zh-en-resource-pair')
    references = {str(path.relative_to(root)): resource_references(path.read_text())
                  for path in dart_paths}
    detected_keys = set().union(*references.values()) if references else set()
    source_errors = [f'{path}:{key}'
                     for path, keys in references.items()
                     for key in sorted(keys)
                     if key not in arbs.get('app_zh', {})]
    grouped = Counter('/'.join(r['path'].split('/')[:3]) for r in rows)
    return {
        'schemaVersion': 1,
        'completeEnglishAccepted': False,
        'limitations': ['Lexical candidate inventory, not semantic UI or ICU validation',
                        'Nested interpolation and adjacent literals require extraction review',
                        'No ARB key match can prove that UI uses resources',
                        'Detected resource references are a conservative lower bound; parameter-based helpers may be missed',
                        'No runtime, long-text, accessibility or native acceptance performed'],
        'summary': {'dartFiles': len(dart_paths), 'chineseLiteralCandidates': len(rows),
                    'uniqueCandidateTexts': len({r['text'] for r in rows}),
                    'candidateFiles': len({r['path'] for r in rows}),
                    'byArea': dict(sorted(grouped.items())),
                    'arbFiles': len(arbs), 'resourceErrors': errors,
                    'sourceReferenceErrors': source_errors,
                    'detectedResourceKeys': len(detected_keys & set(arbs.get('app_zh', {}))),
                    'detectedResourceFiles': sum(bool(keys) for keys in references.values()),
                    'detectedResourceFileKeyPairs': sum(len(keys) for keys in references.values()),
                    'englishResourceKeys': sum(not k.startswith('@') for k in arbs.get('app_en', {})),
                    'regionLiteralCandidates': len(regions),
                    'backendMessageReviewSites': len(backend),
                    'permissionStrings': len(permissions)},
        'candidates': rows, 'regionCandidates': regions,
        'backendMessageReviewSites': backend, 'iosPermissionStrings': permissions,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = inventory(args.repo)
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result['summary'], ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
