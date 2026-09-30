// 扫码核销的三态解析。**这是本项目里契约最微妙的一处。**
//
// 后端在交集 ≥2 时返回的是 `error("请选择要核销的章节", data)`：
// code 是**失败码**，但 data 里带着候选列表。
// 前端判据必须是 `data.needChapterChoice`，**不是 code**。
//
// 后端注释把理由写死了(ApiRegistrationController:1010-1018)：
// 小程序发版不原子、老客户端长期滞留 —— 一旦这里返 success，
// 任何只判 `code == 200` 的客户端都会弹「验票成功」**放人走**，
// 而 entitlement 从没消费 ⇒ **同一张票可以反复核销**。
//
// App 侧原来直接 `_ensureOk` 抛异常，等于把候选列表连同 data 一起丢掉 ——
// 商家看到一句红字却没有可选的东西，后端管这叫「核销是个死胡同」。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/scan_result.dart';

void main() {
  group('★ 三态解析', () {
    test('code==200 → 真的核销掉了', () {
      final ScanResult r = ScanResult.fromBody(
          <String, dynamic>{'code': 200, 'msg': '核销成功'});
      expect(r.outcome, ScanOutcome.redeemed);
      expect(r.message, '核销成功');
    });

    test('★ code!=200 但 needChapterChoice=true → 是「要选」不是「失败」', () {
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapterIds': <dynamic>[7, 9],
        },
      });
      expect(r.outcome, ScanOutcome.needsChoice,
          reason: '只看 code 会把它判成失败,候选列表就丢了');
      expect(r.needsChoice, isTrue);
      expect(r.choiceKind, 'chapter');
      expect(r.choices.map((ScanChoice c) => c.id), <int>[7, 9]);
    });

    test('★ 判据是 data 不是 code —— 就算 code==200 也按 data 走', () {
      // 防的是反过来的错:后端若哪天误把它改成 success,
      // 我们仍然按载荷判「还没核销」,不会弹成功放人走。
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 200,
        'msg': '请选择要核销的章节',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapterIds': <dynamic>[1],
        },
      });
      expect(r.outcome, ScanOutcome.needsChoice,
          reason: 'code==200 也不能当成「已核销」—— 选章未完成 = 核销没发生');
    });

    test('真失败就是失败,且原话透传', () {
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '您在本路线没有生效的权益供给,或该章节已核销',
      });
      expect(r.outcome, ScanOutcome.failed);
      expect(r.message, contains('已核销'));
    });
  });

  group('候选列表', () {
    test('★ 优先用带名字的 chapters,不是两份都用', () {
      // 后端保证 chapters 与 chapterIds 同源同序,并明确要求
      //「别让它们能各说各话」。
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapterIds': <dynamic>[7, 9],
          'chapters': <dynamic>[
            <String, dynamic>{'id': 7, 'name': '第一章'},
            <String, dynamic>{'id': 9, 'name': '第三章'},
          ],
        },
      });
      expect(r.choices.length, 2, reason: '两份都用会变成 4 个候选');
      expect(r.choices.first.label, '第一章');
    });

    test('拿不到名字时用 #id,不显示空条目', () {
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapterIds': <dynamic>[7],
        },
      });
      expect(r.choices.single.label, '#7');
    });

    test('★ 站点分支回传的是「中标记录 ID」不是站点 id', () {
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择要核销的站点',
        'data': <String, dynamic>{
          'needStationChoice': true,
          'stations': <dynamic>[
            <String, dynamic>{
              'registrationMerchantId': 31,
              'id': 999, // 站点自身 id —— 传错这个后端认不出
              'name': '静安店',
            },
          ],
        },
      });
      expect(r.choiceKind, 'station');
      expect(r.choices.single.id, 31,
          reason: '传站点 id(999)后端会找不到中标记录');
    });

    test('id 为 0 或缺失的候选项丢掉 —— 选了也提交不了', () {
      final ScanResult r = ScanResult.fromBody(<String, dynamic>{
        'code': 500,
        'msg': '请选择',
        'data': <String, dynamic>{
          'needChapterChoice': true,
          'chapters': <dynamic>[
            <String, dynamic>{'name': '没有 id 的一条'},
            <String, dynamic>{'id': 7, 'name': '第一章'},
          ],
        },
      });
      expect(r.choices.single.id, 7);
    });
  });
}
