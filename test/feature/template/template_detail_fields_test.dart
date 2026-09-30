// 玩法详情:后端一直在下发,而模型此前没解析。
//
// ★★ App 的详情页原来只有三块(说明/场地/物料),小程序那页有 13 块。
//   差的不是「后端没给」—— CmsMemberTemplate 里 ruleInstructions /
//   storyText / storyImg / validationMethod 一直都在,
//   是 App 的模型只解析了**列表**要用的那几个字段。
//   这类缺口用端点对账查不出来(接口是通的),只有对着页面比才看得见。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/template.dart';

PlayTemplate _t(Map<String, dynamic> extra) =>
    PlayTemplate.fromJson(<String, dynamic>{'id': 1, 'title': '找猫', ...extra});

void main() {
  test('★ 详情字段都解析出来', () {
    final PlayTemplate t = _t(<String, dynamic>{
      'ruleInstructions': '三人一组',
      'storyText': '我在这条街住了十年',
      'storyImg': 'https://x/y.png',
      'validationMethod': 3,
      'publisher': '老王',
    });
    expect(t.ruleInstructions, '三人一组');
    expect(t.storyText, '我在这条街住了十年');
    expect(t.storyImg, 'https://x/y.png');
    expect(t.validationMethod, 3);
    expect(t.publisher, '老王');
  });

  group('★★ 创作者说:storyText 优先,退到 publisher', () {
    test('有 storyText 用它', () {
      expect(_t(<String, dynamic>{'storyText': '故事', 'publisher': '老王'}).creatorNote,
          '故事');
    });
    test('没有就用 publisher —— 与小程序 `storyText || publisher` 同一条', () {
      expect(_t(<String, dynamic>{'publisher': '老王'}).creatorNote, '老王');
      expect(_t(<String, dynamic>{'storyText': '  ', 'publisher': '老王'}).creatorNote,
          '老王');
    });
    test('★ 两个都没有 ⇒ null(整块不渲染,不留一个空标题)', () {
      expect(_t(const <String, dynamic>{}).creatorNote, isNull);
      expect(_t(<String, dynamic>{'storyText': ' ', 'publisher': ' '}).creatorNote,
          isNull);
    });
  });

  group('核验方式文案:与全 App 共用 0–7 码表', () {
    const Map<int, String> expected = <int, String>{
      0: '无需验证',
      1: '文字作答',
      2: '拍照打卡',
      3: '选项问答',
      4: '到店扫码',
      5: 'GPS 到达',
      6: '偏好题组',
      7: '传感器挑战',
    };
    test('★ 码 0–7 都认:1 不再是「扫码核销」,4–7 不再塌成「其他」', () {
      for (final MapEntry<int, String> e in expected.entries) {
        expect(
          _t(<String, dynamic>{'validationMethod': e.key}).validationText,
          e.value,
          reason: '码 ${e.key} 的文案错了',
        );
      }
    });
    test('★ 没给 ⇒ null(不显示这一块),未知值 ⇒「其他」不编名字', () {
      expect(_t(const <String, dynamic>{}).validationText, isNull);
      expect(_t(<String, dynamic>{'validationMethod': 99}).validationText, '其他',
          reason: '编一个名字的话,后端加了新方式后会一直错下去而没人发现');
    });
  });
}
