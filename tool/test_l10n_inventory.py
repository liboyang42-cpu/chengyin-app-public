import tempfile
from pathlib import Path
import unittest
from l10n_inventory import literals, arb_errors, inventory, resource_references, plural_pound_positions


class LocalizationInventoryTest(unittest.TestCase):
    def test_plural_pounds_track_nested_and_independent_counts(self):
        text = '#1 {a, plural, one{# item} other{{b, plural, other{# visits}} / # items}}; {c, plural, other{# likes}} #2'
        self.assertEqual([name for _, name in plural_pound_positions(text)], ['a', 'b', 'a', 'c'])
        self.assertTrue(all(text[index] == '#' for index, _ in plural_pound_positions(text)))
        self.assertEqual(plural_pound_positions('#123 {count} items'), [])
        self.assertEqual(plural_pound_positions('{n, plural, one{{n} item} other{{n} items}}'), [])

    def test_flutter_plural_literal_pound_is_rejected(self):
        template = {'items': '{n} 项', '@items': {'placeholders': {'n': {'type': 'int'}}}}
        self.assertIn('plural-literal-pound:items:translation', arb_errors(
            template, {'items': '{n, plural, one{# item} other{# items}}'}))
        self.assertEqual(arb_errors(template,
            {'items': '{n, plural, one{{n} item} other{{n} items}}'}), [])
    def test_resource_references_ignore_imports_and_comments(self):
        source = "import '../l10n/strings.dart';\nfinal strings = stringsOf(context);\nText(strings.retry); Text(stringsOf(context).done); // strings.fake\n"
        self.assertEqual(resource_references(source), {'retry', 'done'})

    def test_local_alias_does_not_capture_unrelated_variables_in_other_functions(self):
        source = "void before() { final s = ''; s.isEmpty; }\nvoid labels() {\n  final s = stringsOf(context);\n  Text(s.retry);\n}\nvoid after() { final s = ''; s.length; }"
        self.assertEqual(resource_references(source), {'retry'})

    def test_literal_sign_clue_preserves_the_gameplay_target_only(self):
        key = 'prefabSceneSignPrompt'
        value = 'Is there a sign along the road with the character “新” (new)?'
        self.assertEqual(arb_errors({key: '带“新”字的招牌'}, {key: value}), [])
        self.assertIn('chinese-in-english:' + key,
                      arb_errors({key: '招牌'}, {key: '尚未翻译'}))
        self.assertIn('chinese-in-english:otherClue',
                      arb_errors({'otherClue': '招牌'}, {'otherClue': value}))

    def test_legal_identity_exception_is_exact_and_field_scoped(self):
        key = 'legalDraftUserAgreementIntro'
        self.assertEqual(arb_errors({key: '正文'}, {key: 'Operator: 西安吾令文化传媒有限公司'}), [])
        for value in ['Operator: 其他公司', 'Operator: 西安吾令文化传媒有限公司 未翻译']:
            self.assertIn('chinese-in-english:' + key, arb_errors({key: '正文'}, {key: value}))
        self.assertIn('chinese-in-english:otherText', arb_errors(
            {'otherText': '正文'}, {'otherText': '西安吾令文化传媒有限公司'}))

    def test_only_exact_language_autonym_is_allowed_in_english(self):
        self.assertEqual(arb_errors({'chineseLanguage': '简体中文'}, {'chineseLanguage': '简体中文'}), [])
        self.assertIn('chinese-in-english:chineseLanguage', arb_errors(
            {'chineseLanguage': '简体中文'}, {'chineseLanguage': '其他中文'}))
        self.assertIn('chinese-in-english:retry', arb_errors({'retry': '重试'}, {'retry': '重试'}))

    def test_locale_string_is_not_a_resource_alias(self):
        source = 'final locale = stringsOf(context).localeName;\nlocale.startsWith("zh");'
        self.assertEqual(resource_references(source), set())

    def test_inventory_reports_missing_callsite_resource(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'lib/a.dart').write_text('Text(stringsOf(context).missingLabel);')
            (root / 'lib/app_zh.arb').write_text('{"retry":"重试"}')
            (root / 'lib/app_en.arb').write_text('{"retry":"Retry"}')
            report = inventory(root)['summary']
            self.assertEqual(report['sourceReferenceErrors'], ['lib/a.dart:missingLabel'])
            self.assertEqual(report['detectedResourceKeys'], 0)
            self.assertEqual(report['detectedResourceFiles'], 1)
            self.assertEqual(report['detectedResourceFileKeyPairs'], 1)

    def test_comments_do_not_count_and_nested_comments_end(self):
        source = "// '注释'\n/* '忽略' /* nested */ */ Text('玩家注册');"
        self.assertEqual(list(literals(source)), [(2, '玩家注册')])

    def test_raw_triple_quoted_and_escaped_strings(self):
        source = "r'中文\\n'\n'''多行\n中文'''\n\"a\\\"中文\""
        self.assertEqual([line for line, _ in literals(source)], [1, 2, 4])
        self.assertEqual(len(list(literals(source))), 3)

    def test_interpolation_is_retained_for_manual_review(self):
        self.assertEqual(list(literals("'共 $count 人'")), [(1, '共 $count 人')])

    def test_missing_keys_and_placeholders_fail(self):
        errors = arb_errors({'hello': '你好 {name}', 'retry': '重试'}, {'hello': 'Hello'})
        self.assertIn('missing:retry', errors)
        self.assertIn('placeholder-mismatch:hello', errors)

    def test_metadata_rename_and_reserved_parameter_are_rejected(self):
        self.assertIn('placeholder-metadata-mismatch:progress', arb_errors(
            {'progress': '{total}', '@progress': {'placeholders': {'required': {'type': 'int'}}}},
            {'progress': '{total}'}))
        self.assertIn('placeholder-invalid-identifier:message:class', arb_errors(
            {'message': '{class}', '@message': {'placeholders': {'class': {'type': 'String'}}}},
            {'message': '{class}'}))

    def test_plural_other_and_chinese_fallback_rejected(self):
        errors = arb_errors({'count': '{n, plural, other{# 人}}'},
                            {'count': '{n, plural, one{# person}}'})
        self.assertIn('plural-missing-other:count', errors)
        self.assertIn('chinese-in-english:x', arb_errors({'x': '重试'}, {'x': '重试'}))

    def test_plural_selector_requires_numeric_placeholder_in_either_locale(self):
        for kind in ['String', 'Object', None, 'int', 'double', 'num']:
            with self.subTest(kind=kind):
                template = {'visits': '{count} 次', '@visits': {
                    'placeholders': {'count': {'type': kind}}}}
                translated = {'visits': '{count, plural, one{{count} visit} other{{count} visits}}'}
                errors = arb_errors(template, translated)
                expected = 'plural-nonnumeric-placeholder:visits:count'
                self.assertEqual(expected in errors, kind not in {'int', 'double', 'num'})
        self.assertIn('plural-nonnumeric-placeholder:visits:count', arb_errors(
            {'visits': '{count, plural, other{# 次}}', '@visits': {
                'placeholders': {'count': {'type': 'String'}}}},
            {'visits': 'Visits: {count}'}))

    def test_localized_pair_is_not_full_app_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'lib/app.dart').write_text("Text('未翻译'); // '注释'\nText('¥$amount');")
            (root / 'lib/app_zh.arb').write_text('{"retry":"重试"}')
            (root / 'lib/app_en.arb').write_text('{"retry":"Retry"}')
            result = inventory(root)
            self.assertFalse(result['completeEnglishAccepted'])
            self.assertEqual(result['summary']['resourceErrors'], [])
            self.assertEqual(result['summary']['chineseLiteralCandidates'], 1)
            self.assertEqual(result['summary']['regionLiteralCandidates'], 1)

class RepositoryResourceTest(unittest.TestCase):
    def test_chinese_english_keys_and_placeholders_match(self):
        import json
        root = Path(__file__).resolve().parents[1]
        zh = json.loads((root / 'lib/l10n/app_zh.arb').read_text())
        en = json.loads((root / 'lib/l10n/app_en.arb').read_text())
        self.assertEqual(arb_errors(zh, en), [])
        self.assertIn('one{{count} item}', en['itemCount'])
        self.assertIn('other{{count} items}', en['itemCount'])

    def test_callsite_resource_references_exist(self):
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(inventory(root)['summary']['sourceReferenceErrors'], [])

    def test_permission_resources_preserve_existing_keys(self):
        import json
        import plistlib
        import re
        root = Path(__file__).resolve().parents[1]
        info = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
        expected = {k for k in info if k.endswith('UsageDescription')}
        for locale in ['en', 'zh-Hans']:
            contents = (root / f'ios/Runner/{locale}.lproj/InfoPlist.strings').read_text()
            values = {json.loads(k): json.loads(v) for k,v in
                      re.findall(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;', contents)}
            self.assertEqual(set(values), expected)
            self.assertTrue(all(values.values()))


if __name__ == '__main__':
    unittest.main()
