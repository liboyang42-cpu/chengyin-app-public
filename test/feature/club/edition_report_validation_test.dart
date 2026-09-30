// 工时与证据页的纯校验函数(无 UI,快)。
//
// ★ 负控重点:可重试的「重试原路退款」按钮只在 retryable 时才出现 —— 这页
//   是真金白银,把可退的看成不可退(或反过来)都是钱的问题。
//   这里先钉死校验函数本身,页面上的按钮门在 club_pages_behavior_test.dart。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/club/edition_report_validation.dart';

void main() {
  group('hoursInputError', () {
    test('空串 → 提示填非负实际工时', () {
      expect(hoursInputError(''), '请填写非负的实际工时');
      expect(hoursInputError('   '), '请填写非负的实际工时');
    });

    test('非数字 → 同上', () {
      expect(hoursInputError('abc'), '请填写非负的实际工时');
      expect(hoursInputError('1.2.3'), '请填写非负的实际工时');
    });

    test('负数 → 同上', () {
      expect(hoursInputError('-1'), '请填写非负的实际工时');
      expect(hoursInputError('-0.5'), '请填写非负的实际工时');
    });

    test('合法 → null(放行)', () {
      expect(hoursInputError('0'), isNull);
      expect(hoursInputError('1.5'), isNull);
      expect(hoursInputError('12'), isNull);
    });
  });

  group('evidenceHashError', () {
    test('空 → 提示填证据哈希', () {
      expect(evidenceHashError(''), '请填写证据哈希');
    });

    test('长度不对 → 提示 64 位 SHA-256', () {
      expect(evidenceHashError('abc'), '请填写 64 位 SHA-256 哈希');
    });

    test('长度对但非十六进制 → 提示 64 位 SHA-256', () {
      expect(evidenceHashError('z' * 64), '请填写 64 位 SHA-256 哈希');
    });

    test('64 位十六进制 → null(放行)', () {
      expect(evidenceHashError('a' * 64), isNull);
      expect(evidenceHashError('0123456789abcdef' * 4), isNull);
    });
  });

  test('kPickEditionFirst 是引导文案而非空串', () {
    expect(kPickEditionFirst, isNotEmpty);
  });
}