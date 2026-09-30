import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/template.dart';

void main() {
  PlayTemplate t(Map<String, dynamic> m) =>
      PlayTemplate.fromJson(<String, dynamic>{'title': 'X', ...m});

  group('★ 时长:没给就不显示,不写 0 分钟', () {
    test('null / 0 / 负数都不显示', () {
      expect(t(<String, dynamic>{}).durationText, isNull,
          reason: '写「0 分钟」会让人以为这个玩法瞬间就能玩完');
      expect(t(<String, dynamic>{'duration': 0}).durationText, isNull);
      expect(t(<String, dynamic>{'duration': -5}).durationText, isNull);
    });
    test('分钟 / 小时 / 小时+分 三档', () {
      expect(t(<String, dynamic>{'duration': 45}).durationText, '45 分钟');
      expect(t(<String, dynamic>{'duration': 120}).durationText, '2 小时');
      expect(t(<String, dynamic>{'duration': 95}).durationText, '1 小时 35 分');
    });
  });

  group('★ 元信息行:各段可空,别拼出「· ·」', () {
    test('三段都有', () {
      expect(
          t(<String, dynamic>{'players': '2-6', 'duration': 60, 'difficulty': '中等'})
              .metaLine,
          '2-6 人 · 1 小时 · 中等');
    });
    test('只有一段时不带分隔符', () {
      expect(t(<String, dynamic>{'players': '4'}).metaLine, '4 人');
      expect(t(<String, dynamic>{'duration': 30}).metaLine, '30 分钟');
    });
    test('中间缺一段不留空位', () {
      expect(t(<String, dynamic>{'players': '4', 'difficulty': '简单'}).metaLine,
          '4 人 · 简单');
    });
    test('全空 → 空串,不是「 ·  · 」', () {
      expect(t(<String, dynamic>{}).metaLine, '');
      expect(
          t(<String, dynamic>{'players': '  ', 'difficulty': ''}).metaLine, '');
    });
  });

  group('★ 四种不可用原因,界面各不相同', () {
    // 后端 ApiTemplateController.producInfo 的四种拒绝理由。
    test('识别得出四种', () {
      expect(templateUnavailableFrom('模版审核中'), TemplateUnavailable.underReview);
      expect(templateUnavailableFrom('模版已下架'), TemplateUnavailable.offline);
      expect(templateUnavailableFrom('模版已删除'), TemplateUnavailable.deleted);
      expect(templateUnavailableFrom('模版不存在'), TemplateUnavailable.notFound);
      expect(templateUnavailableFrom('网络炸了'), TemplateUnavailable.unknown);
    });

    test('★ 只有审核中和未知给重试', () {
      expect(TemplateUnavailable.underReview.retryable, isTrue,
          reason: '审核通过后会回来,值得再看一次');
      expect(TemplateUnavailable.unknown.retryable, isTrue);
      expect(TemplateUnavailable.deleted.retryable, isFalse,
          reason: '已删除的重试一万次也不会回来,给按钮是骗人');
      expect(TemplateUnavailable.offline.retryable, isFalse);
      expect(TemplateUnavailable.notFound.retryable, isFalse);
    });

    test('四种文案互不相同,不都说成「加载失败」', () {
      final titles = TemplateUnavailable.values
          .map((TemplateUnavailable v) => v.title)
          .toSet();
      expect(titles.length, greaterThanOrEqualTo(4),
          reason: '五个枚举里 deleted/notFound 共用一句是有意的,其余必须各说各的');
      for (final TemplateUnavailable v in TemplateUnavailable.values) {
        expect(v.title, isNot(contains('加载失败')));
        expect(v.hint.trim(), isNotEmpty, reason: '$v 缺少下一步提示');
      }
    });
  });

  test('标题兜底', () {
    expect(PlayTemplate.fromJson(<String, dynamic>{'title': '  '}).title, '未命名玩法');
  });
}
