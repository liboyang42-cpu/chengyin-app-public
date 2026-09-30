import 'package:chengyin_app/data/models/roam_social.dart';
import 'package:flutter_test/flutter_test.dart';

/// 漫游社交域模型的解析契约。
///
/// 判据来自两处真源:
///   · 后端 `RoamHangoutServiceImpl.hangoutItem` / `ApiRoamController`
///     (nearby-runners / shop-visitors)的字段拼写;
///   · 小程序 `utils/roam-runners.js:normalizeRunners` 的丢弃与截断规则。
void main() {
  group('RoamHangoutItem:三类混排一条记录', () {
    test('局用 title,主题/活动用 name;label 取到的那一个', () {
      final RoamHangoutItem hangout = RoamHangoutItem.fromJson(
        <String, dynamic>{'kind': 'hangout', 'id': 7, 'title': '打 UNO 找搭子'},
      );
      expect(hangout.label, '打 UNO 找搭子');
      expect(hangout.isHangout, isTrue);

      final RoamHangoutItem topic = RoamHangoutItem.fromJson(
        <String, dynamic>{'kind': 'topic', 'id': 3, 'name': '老城厢的九个门'},
      );
      expect(topic.label, '老城厢的九个门');
      expect(topic.isTopic, isTrue);
    });

    test('坐标两种拼写都认(latitude/longitude 与 lat/lng)', () {
      final RoamHangoutItem a = RoamHangoutItem.fromJson(
        <String, dynamic>{'kind': 'topic', 'id': 1, 'latitude': 31.2, 'longitude': 121.4},
      );
      expect(a.latitude, 31.2);
      expect(a.longitude, 121.4);

      final RoamHangoutItem b = RoamHangoutItem.fromJson(
        <String, dynamic>{'kind': 'topic', 'id': 2, 'lat': '31.2', 'lng': '121.4'},
      );
      expect(b.latitude, 31.2);
      expect(b.longitude, 121.4);
    });

    test('商家/俱乐部身份按 ownerRole 字面判,不靠颜色', () {
      expect(
        RoamHangoutItem.fromJson(
          <String, dynamic>{'kind': 'hangout', 'id': 1, 'ownerRole': 'merchant'},
        ).isMerchantOwner,
        isTrue,
      );
      expect(
        RoamHangoutItem.fromJson(
          <String, dynamic>{'kind': 'hangout', 'id': 1, 'ownerRole': 'club'},
        ).isMerchantOwner,
        isTrue,
      );
      expect(
        RoamHangoutItem.fromJson(
          <String, dynamic>{'kind': 'hangout', 'id': 1, 'ownerRole': 'player'},
        ).isMerchantOwner,
        isFalse,
      );
    });

    test('members 只收 Map,脏行丢掉不崩', () {
      final RoamHangoutItem item = RoamHangoutItem.fromJson(
        <String, dynamic>{
          'kind': 'hangout',
          'id': 1,
          'members': <dynamic>[
            <String, dynamic>{'memberId': 9, 'nickname': '阿岚', 'avatar': 'a.png'},
            '脏行',
          ],
        },
      );
      expect(item.members.length, 1);
      expect(item.members.first.nickname, '阿岚');
    });

    test('reported 是界面状态,后端不下发就为 false', () {
      expect(
        RoamHangoutItem.fromJson(<String, dynamic>{'kind': 'hangout', 'id': 1}).reported,
        isFalse,
      );
    });
  });

  group('RoamRunner:隐私与脏数据', () {
    test('没有 memberId 或没有坐标的一律丢 —— 不画到几内亚湾', () {
      expect(
        RoamRunner.normalize(<dynamic>[
          <String, dynamic>{'memberId': 0, 'lat': 31.2, 'lng': 121.4},
          <String, dynamic>{'memberId': 8, 'lng': 121.4},
          <String, dynamic>{'memberId': 9, 'lat': 31.2, 'lng': 121.4, 'nickname': '阿岚'},
          '脏行',
        ]),
        hasLength(1),
        reason: '只有第 3 条同时有 id 与坐标',
      );
    });

    test('昵称缺失回落「漫游者」', () {
      final RoamRunner runner = RoamRunner.normalize(<dynamic>[
        <String, dynamic>{'memberId': 9, 'lat': 31.2, 'lng': 121.4},
      ]).single;
      expect(runner.nickname, '漫游者');
    });

    test('explorePct 截到 0–99、shops 不为负(与小程序 normalizeRunners 同款)', () {
      final RoamRunner runner = RoamRunner.normalize(<dynamic>[
        <String, dynamic>{
          'memberId': 9,
          'lat': 31.2,
          'lng': 121.4,
          'explorePct': 240,
          'shops': -3,
        },
      ]).single;
      expect(runner.explorePct, 99);
      expect(runner.shops, 0);
    });

    test('「TA 点亮的店」只留有图的,空图不占格子', () {
      final RoamRunner runner = RoamRunner.normalize(<dynamic>[
        <String, dynamic>{
          'memberId': 9,
          'lat': 31.2,
          'lng': 121.4,
          'shopPhotos': <dynamic>[
            <String, dynamic>{'name': '梧桐咖啡', 'image': 'a.png'},
            <String, dynamic>{'name': '没有图', 'image': ''},
          ],
        },
      ]).single;
      expect(runner.shopPhotos, hasLength(1));
      expect(runner.shopPhotos.single.name, '梧桐咖啡');
    });
  });

  group('RoamShopVisitors:按来源回行,没人来过也回一行', () {
    test('total=0 与「没查到」是两件事', () {
      final RoamShopVisitors empty = RoamShopVisitors.fromJson(
        <String, dynamic>{'sourceId': 12, 'avatars': <dynamic>[], 'total': 0},
      );
      expect(empty.sourceId, 12);
      expect(empty.total, 0);
      expect(empty.avatars, isEmpty);
    });

    test('头像里的空串清掉,不留空位', () {
      final RoamShopVisitors row = RoamShopVisitors.fromJson(
        <String, dynamic>{
          'sourceId': 12,
          'avatars': <dynamic>['a.png', '', null],
          'total': 5,
        },
      );
      expect(row.avatars, <String>['a.png']);
      expect(row.total, 5);
    });
  });

  group('RoamStampExchangeResult:三态分开,不能只看 code', () {
    test('换到了:stamp 有值', () {
      final RoamStampExchangeResult r = RoamStampExchangeResult.fromJson(
        <String, dynamic>{
          'exchanged': true,
          'stamp': <String, dynamic>{
            'id': 12345,
            'picUrl': 'p.png',
            'caption': '巷口那家豆浆七点才开',
            'checkState': 0,
            'createTime': '2026-09-15T07:09:17',
          },
        },
      );
      expect(r.exchanged, isTrue);
      expect(r.stamp?.id, 12345);
      expect(r.stamp?.caption, '巷口那家豆浆七点才开');
    });

    test('没换到是正常空态:reason 带出去,stamp 为 null', () {
      final RoamStampExchangeResult r = RoamStampExchangeResult.fromJson(
        <String, dynamic>{'exchanged': false, 'reason': '还没有可以换的票'},
      );
      expect(r.exchanged, isFalse);
      expect(r.reason, '还没有可以换的票');
      expect(r.stamp, isNull);
    });

    test('同键重放命中要能认出来(不是换了两张)', () {
      final RoamStampExchangeResult r = RoamStampExchangeResult.fromJson(
        <String, dynamic>{'exchanged': true, 'idempotent': true},
      );
      expect(r.idempotent, isTrue);
    });
  });

  group('RoamTilePage:迷雾增量页', () {
    test('翻页游标与 hasMore 原样带出,空格子清掉', () {
      final RoamTilePage page = RoamTilePage.fromJson(
        <String, dynamic>{
          'tiles': <dynamic>['a', '', null, 'b'],
          'nextAfterId': 42,
          'hasMore': true,
        },
      );
      expect(page.tiles, <String>['a', 'b']);
      expect(page.nextAfterId, 42);
      expect(page.hasMore, isTrue);
    });

    test('缺字段时是空页而不是抛', () {
      final RoamTilePage page = RoamTilePage.fromJson(<String, dynamic>{});
      expect(page.tiles, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('RoamHangoutNearby:冷启动拉远提示', () {
    test('suggestedRadius/suggestedCount 带出', () {
      final RoamHangoutNearby nearby = RoamHangoutNearby.fromJson(
        <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'kind': 'hangout', 'id': 1, 'title': '打 UNO'},
          ],
          'radius': 3000,
          'suggestedRadius': 10000,
          'suggestedCount': 2,
        },
      );
      expect(nearby.items, hasLength(1));
      expect(nearby.radius, 3000);
      expect(nearby.suggestedRadius, 10000);
      expect(nearby.suggestedCount, 2);
    });
  });

  group('RoamHangoutCreated:开局回执就是那个群', () {
    test('id 与 conversationId', () {
      final RoamHangoutCreated created = RoamHangoutCreated.fromJson(
        <String, dynamic>{'id': 7, 'conversationId': 88},
      );
      expect(created.id, 7);
      expect(created.conversationId, 88);
    });
  });
}
