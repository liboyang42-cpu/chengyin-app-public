// 门口码冷启动 + 邀请人归因的纯判定层(gap-spec-player #1)。
// 钉的是真源口径:`utils/game-door-entry.js` 的 parseDoorScene/pathForScanEntry、
// `pages/index/index.js` 的 readInviterId/handleInviter 三闸。
import 'package:chengyin_app/core/router/door_entry.dart';
import 'package:chengyin_app/data/models/scan_entry.dart';
import 'package:chengyin_app/feature/account/inviter_cold_start.dart';
import 'package:flutter_test/flutter_test.dart';

const String _code = '0123456789abcdef0123456789abcdef';

void main() {
  group('parseDoorScene', () {
    test('32 位 hex 收下并归一小写;其余一律当没有码', () {
      expect(parseDoorScene(_code), _code);
      expect(parseDoorScene(_code.toUpperCase()), _code);
      expect(parseDoorScene(' $_code\n'), _code);
      expect(parseDoorScene(null), isNull);
      expect(parseDoorScene(''), isNull);
      expect(parseDoorScene('not-a-door-code'), isNull);
      expect(parseDoorScene('${_code}0'), isNull); // 33 位不算
    });
  });

  group('doorEntryRouteFor', () {
    test('action=play 带场次进 /play/{activityId},没场次是主题自玩 /play/0', () {
      expect(
        doorEntryRouteFor(
          const ScanEntryResult(
            action: 'play',
            topicId: 5,
            activityId: 9,
            nodeId: 3,
          ),
        ),
        '/play/9?topicId=5',
      );
      expect(
        doorEntryRouteFor(const ScanEntryResult(action: 'play', topicId: 5)),
        '/play/0?topicId=5',
      );
    });

    test('其余 action(未报名)去主题购买页;缺 topicId 判不了路回 null', () {
      expect(
        doorEntryRouteFor(
          const ScanEntryResult(action: 'purchase', topicId: 5),
        ),
        '/topic/5',
      );
      expect(doorEntryRouteFor(const ScanEntryResult(action: 'play')), isNull);
      expect(doorEntryRouteFor(null), isNull);
    });
  });

  group('readInviterId / shouldBindInviter', () {
    test('inviter 优先、id 等价(真源 options.inviter || options.id)', () {
      expect(readInviterId(<String, String>{'inviter': '7', 'id': '8'}), '7');
      expect(readInviterId(<String, String>{'id': '8'}), '8');
      expect(readInviterId(<String, String>{}), '');
    });

    test('三闸:登录后、没绑过、不是自己', () {
      expect(
        shouldBindInviter(inviterId: '7', currentUserId: 42, hasInviter: false),
        isTrue,
      );
      expect(
        shouldBindInviter(
          inviterId: '7',
          currentUserId: null,
          hasInviter: false,
        ),
        isFalse,
        reason: '冷启动没会话,当场发不出去要等登录落地补发,不是这里发',
      );
      expect(
        shouldBindInviter(inviterId: '7', currentUserId: 42, hasInviter: true),
        isFalse,
      );
      expect(
        shouldBindInviter(
          inviterId: '42',
          currentUserId: 42,
          hasInviter: false,
        ),
        isFalse,
        reason: '分享里是字符串、会话里是数字,要归一比较才挡得住自己点自己',
      );
      expect(
        shouldBindInviter(inviterId: '', currentUserId: 42, hasInviter: false),
        isFalse,
      );
    });
  });

  group('consumeColdStartInviter', () {
    test('登录 + 未绑 + 非自己 → 发一次 setInviter 并打 has_inviter 标记', () async {
      final List<String> sent = <String>[];
      bool marked = false;
      await consumeColdStartInviter(
        inviterId: '7',
        currentUserId: 42,
        isBound: () async => false,
        markBound: () async => marked = true,
        bind: (String id) async => sent.add(id),
      );
      expect(sent, <String>['7']);
      expect(marked, isTrue);
    });

    test('已绑过不再发(邀请人只能绑一次,重试不会有变化)', () async {
      int sends = 0;
      await consumeColdStartInviter(
        inviterId: '7',
        currentUserId: 42,
        isBound: () async => true,
        markBound: () async {},
        bind: (_) async => sends++,
      );
      expect(sends, 0);
    });

    test('后端说绑不上就静默:不打标记、不抛(真源无 fail 分支)', () async {
      bool marked = false;
      await consumeColdStartInviter(
        inviterId: '7',
        currentUserId: 42,
        isBound: () async => false,
        markBound: () async => marked = true,
        bind: (_) async => throw Exception(
          '没能绑定。可能这个邀请码不存在,也可能你之前已经绑过邀请人了 —— 邀请人只能绑一次,重试不会有变化。',
        ),
      );
      expect(marked, isFalse);
    });
  });
}
