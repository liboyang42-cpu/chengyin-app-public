import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_pool.dart';

/// 合作池八态。
///
/// ★ 后端 ApiCoopPoolController:152-161 的注释点名了两个坑,两条都是
///   「状态漏一档就把用户带进死路」:
///   ① invited 必须先于 applied —— 否则「去接受邀约」这一跳俱乐部永远看不见;
///   ② 少了 converted 会掉进 else 显示成「可申请」—— 明明已经通过了却像没人理,
///      而且诱导他再申请一次。
void main() {
  CoopPoolItem s(String state) =>
      CoopPoolItem.fromJson(<String, dynamic>{'name': 'X', 'state': state});

  group('八态文案', () {
    final expected = <String, String>{
      'open': '可申请',
      'applied': '已申请 · 等商家处理',
      'invited': '商家已邀约',
      'taken': '已被其他俱乐部承接',
      'cooped': '合作中',
      'converted': '已通过 · 已生成邀约',
      'declined': '已婉拒 · 可再申请',
      'withdrawn': '已撤回 · 可再申请',
    };
    expected.forEach((String state, String text) {
      test('$state → $text', () => expect(s(state).stateText, text));
    });
  });

  group('★ 能不能申请', () {
    test('只有三态可申请', () {
      for (final String st in <String>['open', 'declined', 'withdrawn']) {
        expect(s(st).canApply, isTrue, reason: st);
      }
    });
    test('★ converted 不可再申请 —— 已经通过了,再申请是把人带进死路', () {
      expect(s('converted').canApply, isFalse);
      expect(s('converted').stateText, isNot('可申请'));
    });
    test('★ invited 不可再申请 —— 该去接受邀约,不是重新申请', () {
      expect(s('invited').canApply, isFalse);
    });
    test('其余终态都不可申请', () {
      for (final String st in <String>['applied', 'taken', 'cooped']) {
        expect(s(st).canApply, isFalse, reason: st);
      }
    });
    test('未知态兜底成 open —— 那是后端加了新态,不是漏判', () {
      expect(s('brand_new_state').stateText, '可申请');
    });
  });

  group('撤回', () {
    test('只有待商家处理时能撤回', () {
      expect(s('applied').canWithdraw, isTrue);
      for (final String st in <String>['open', 'invited', 'converted', 'cooped']) {
        expect(s(st).canWithdraw, isFalse, reason: st);
      }
    });
  });

  group('★ 没有俱乐部 ≠ 没有可承接的主题', () {
    test('hasClub=false 时页面该说"先创建俱乐部"', () {
      final p =
          CoopPool.fromJson(<String, dynamic>{'rows': <dynamic>[], 'hasClub': false});
      expect(p.hasClub, isFalse,
          reason: '只显示空列表会让人以为"暂时没有可承接的主题",其实是他还没有俱乐部');
      expect(p.rows, isEmpty);
    });
    test('有俱乐部但列表空 → 才是真的没有可承接', () {
      final p =
          CoopPool.fromJson(<String, dynamic>{'rows': <dynamic>[], 'hasClub': true});
      expect(p.hasClub, isTrue);
    });
  });

  test('缺名字兜底', () {
    expect(CoopPoolItem.fromJson(<String, dynamic>{}).name, '未命名主题');
  });

  // 带队申请(`/api/coop/pool/mine` / `/received`)的一行。
  //
  // ★ 同一行数据在两个箱子里**含义不同**(utils/coop-invite-view.js:160):
  //   received = 发布者看「谁申请了我的主题」→ 拒绝 / 回邀约;
  //   sent     = 俱乐部看「我申请了谁」      → 撤回。
  //   判错箱子摆出来的按钮,点下去必被服务端拒。
  group('带队申请:箱子决定"对方是谁"', () {
    CoopPoolApply a(Map<String, dynamic> extra) => CoopPoolApply.fromJson(
        <String, dynamic>{
          'applyId': 31,
          'topicId': 8,
          'status': 0,
          'clubId': 7,
          'clubName': '夜跑团',
          'merchantNick': '老街咖啡',
          'topicName': '周末路线',
          ...extra,
        });

    test('received 里对方是俱乐部,sent 里对方是商家', () {
      expect(a(<String, dynamic>{}).peerText(received: true), '来自 夜跑团');
      expect(a(<String, dynamic>{}).peerText(received: false), '发给 老街咖啡');
    });

    test('★ 对方名字拿不到时留空,不拼一个"来自 "出来', () {
      expect(
        a(<String, dynamic>{'clubName': null}).peerText(received: true),
        '',
      );
    });

    test('副行按箱子说清这是"申请带队"', () {
      expect(a(<String, dynamic>{}).subText(received: true), '俱乐部申请带队');
      expect(a(<String, dynamic>{}).subText(received: false), '申请带队 · 夜跑团');
      expect(
        a(<String, dynamic>{'clubName': ''}).subText(received: false),
        '申请带队',
        reason: '没有俱乐部名时别留一个孤零零的" · "',
      );
    });
  });

  group('带队申请:状态与动作', () {
    CoopPoolApply s(int status) =>
        CoopPoolApply.fromJson(<String, dynamic>{'status': status});

    test('四态文案逐条对齐 APPLY_STATUS', () {
      final Map<int, String> expected = <int, String>{
        0: '待确认',
        1: '已拒绝',
        2: '已撤回',
        3: '已回邀约',
      };
      expected.forEach((int code, String text) {
        expect(s(code).statusText, text, reason: '$code');
      });
    });

    test('★ 未知码不猜 —— 别让一条已拒绝的申请看起来还能处理', () {
      expect(s(9).statusText, '状态未知');
      expect(s(9).canHandle, isFalse);
      expect(s(9).canWithdraw, isFalse);
    });

    test('★★ 只有待确认才有动作(处理过的申请再点 = 必被拒)', () {
      expect(s(0).canWithdraw, isTrue);
      expect(s(0).canHandle, isTrue);
      for (final int done in <int>[1, 2, 3]) {
        expect(s(done).canWithdraw, isFalse, reason: '$done');
        expect(s(done).canHandle, isFalse, reason: '$done');
      }
    });
  });

  group('带队申请:文案兜底', () {
    test('没主题名 → "主题 #id",不是留空', () {
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'topicId': 8}).titleText,
        '主题 #8',
      );
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'topicId': 8, 'topicName': '  '})
            .titleText,
        '主题 #8',
        reason: '全空格等于没有名字',
      );
    });

    test('★ 没留言要说清"申请只表意向" —— 它决定商家该不该当合同看', () {
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{}).termsText,
        '申请只表意向,条款随商家回的邀约走',
      );
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'message': '带过 30 人'}).termsText,
        '留言:带过 30 人',
      );
    });

    test('★ 日期只取到日;短于 10 个字符的脏日期不能抛异常', () {
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'startDate': '2026-10-01 09:00:00'})
            .dateText,
        '2026-10-01',
      );
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'startDate': '2026-10'}).dateText,
        '2026-10',
        reason: 'JS 的 slice 只会截短,不该在这里抛 RangeError 把整页打崩',
      );
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'startDate': null}).dateText,
        '',
      );
    });

    test('★ scope 原样带着(商家员工处理 owner 主题时要回传给 /decline)', () {
      expect(
        CoopPoolApply.fromJson(<String, dynamic>{'scope': 'MERCHANT'}).scope,
        'MERCHANT',
      );
      expect(CoopPoolApply.fromJson(<String, dynamic>{}).scope, isNull);
    });
  });
}
