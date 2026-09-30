import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/infomation.dart';

void main() {
  Infomation i({String title = 'T', String? subtitle, String? contents = 'C'}) =>
      Infomation.fromJson(<String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'contents': contents,
      });

  group('★ 摘要:与标题逐字相同就不渲染', () {
    test('相同 → null(印两遍信息量为零)', () {
      expect(i(title: '新手指南', subtitle: '新手指南').summary, isNull);
      expect(i(title: ' 新手指南 ', subtitle: '新手指南').summary, isNull,
          reason: '两端空白不该让它变成"不同"');
    });
    test('不同 → 渲染', () {
      expect(i(title: '新手指南', subtitle: '五分钟上手').summary, '五分钟上手');
    });
    test('空 → null', () {
      expect(i(subtitle: null).summary, isNull);
      expect(i(subtitle: '   ').summary, isNull);
    });
  });

  group('★ usable 三条判据', () {
    test('a. 标题为空 → 不可用', () {
      expect(i(title: '').usable, isFalse);
      expect(i(title: '   ').usable, isFalse);
    });
    test('b. 正文为空 → 不可用(点进详情是空的)', () {
      expect(i(contents: null).usable, isFalse);
      expect(i(contents: '  ').usable, isFalse);
    });
    test('c. 纯数字标题 + 无区分副标 → 不可用', () {
      expect(i(title: '11', subtitle: '11').usable, isFalse,
          reason: '线上真实存在这一行');
      expect(i(title: '11', subtitle: '').usable, isFalse);
      expect(i(title: '11').usable, isFalse);
    });
  });

  group('★★ (c) 绝不是「过滤数字」', () {
    test('数值命名 + 有效副标 → 保留', () {
      expect(i(title: '2024', subtitle: '年度城市定向回顾').usable, isTrue);
    });
    test('纯数字但副标给了语义 → 保留', () {
      expect(i(title: '11', subtitle: '新手上路指南').usable, isTrue);
    });
    test('非纯数字 → 保留(哪怕以数字开头)', () {
      expect(i(title: '72小时城市漫游').usable, isTrue);
      expect(i(title: '11 号线沿线玩法').usable, isTrue);
    });
  });

  group('三种玩法', () {
    test('三条齐,各有名字/标签/说明', () {
      expect(kPlayModes.length, 3);
      for (final PlayMode m in kPlayModes) {
        expect(m.name.trim(), isNotEmpty);
        expect(m.tag.trim(), isNotEmpty);
        expect(m.desc.trim(), isNotEmpty);
        expect(m.route.startsWith('/'), isTrue);
      }
    });
    test('key 不重复', () {
      expect(kPlayModes.map((PlayMode m) => m.key).toSet().length, 3);
    });
  });
}
