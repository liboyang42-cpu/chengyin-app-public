import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/ai_quota.dart';

void main() {
  group('★★ limited 与 remaining 是一对', () {
    test('不限量 → 能生成,且不显示剩余次数', () {
      final q = AiQuota.fromJson(<String, dynamic>{'limited': false, 'remaining': 0});
      expect(q.canGenerate, isTrue,
          reason: '只看 remaining<=0 会把不限量的用户也挡住');
      expect(q.remainingText, isNull, reason: '显示「剩余 0 次」会吓到人');
    });
    test('限量且有余额 → 能生成并显示', () {
      final q = AiQuota.fromJson(<String, dynamic>{'limited': true, 'remaining': 3});
      expect(q.canGenerate, isTrue);
      expect(q.remainingText, '今天还能生成 3 次');
      expect(q.exhaustedHint, isNull);
    });
    test('限量且用完 → 挡住并说清', () {
      final q = AiQuota.fromJson(<String, dynamic>{'limited': true, 'remaining': 0});
      expect(q.canGenerate, isFalse);
      // ★★ 2026-08-20 改文案:必须说「可以先手动填」——
      //   AI 起草是**附加功能**,用完了主功能(手动写主题名和简介)一点没受影响。
      //   只说「明天再来」会让人以为整个发布都得等到明天。
      expect(q.exhaustedHint, contains('可以先手动填'));
      expect(q.exhaustedHint, isNot(contains('明天再来')),
          reason: '这句话把附加功能的限额说成了整个发布的限额');
    });
  });

  group('★ 没取到配额不该禁用', () {
    test('loaded=false → 先放行,让后端把关', () {
      const q = AiQuota();
      expect(q.loaded, isFalse);
      expect(q.canGenerate, isTrue,
          reason: '拿不到配额就关掉功能,等于用一次网络抖动废掉一个功能');
      expect(q.remainingText, isNull);
      expect(q.exhaustedHint, isNull);
    });
  });

  group('★ 身份被拒 vs 服务故障', () {
    const roleMsg = '当前身份暂不支持AI创作,请切换到俱乐部或商家身份';
    const faultMsg = 'AI 服务暂时不可用,请稍后重试';

    test('身份问题 → 不给重试,并告诉他怎么换身份', () {
      expect(AiGateResult.isRoleBlocked(roleMsg), isTrue);
      expect(AiGateResult.retryable(roleMsg), isFalse,
          reason: '重试不会让玩家变成主理人');
      expect(AiGateResult.nextStep(roleMsg), contains('申请成为'));
    });
    test('服务故障 → 给重试,不给换身份的指引', () {
      expect(AiGateResult.isRoleBlocked(faultMsg), isFalse);
      expect(AiGateResult.retryable(faultMsg), isTrue);
      expect(AiGateResult.nextStep(faultMsg), isNull,
          reason: '故障时叫人去换身份是把人带偏');
    });
  });
}
