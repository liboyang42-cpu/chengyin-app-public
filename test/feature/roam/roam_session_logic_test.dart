import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/roam_session.dart';

void main() {
  group('会话合法性校验(读不出/坏数据 与 找不到 必须分家)', () {
    test('坐标:数字或非空数字串,超界/非数字一律非法', () {
      expect(isValidRoamCoordinate(1, 90), isTrue);
      expect(isValidRoamCoordinate('1.5', 90), isTrue);
      expect(isValidRoamCoordinate('0', 90), isTrue);
      expect(isValidRoamCoordinate('', 90), isFalse);
      expect(isValidRoamCoordinate('abc', 90), isFalse);
      expect(isValidRoamCoordinate(null, 90), isFalse);
      expect(isValidRoamCoordinate(91, 90), isFalse);
      expect(isValidRoamCoordinate(-91, 90), isFalse);
      expect(isValidRoamCoordinate(181, 180), isFalse);
    });

    test('点:两个坐标都合法才算', () {
      expect(isValidRoamPoint(<String, dynamic>{'lat': 1, 'lng': 2}), isTrue);
      expect(isValidRoamPoint(<String, dynamic>{'lat': '1', 'lng': '2'}), isTrue);
      expect(isValidRoamPoint(<String, dynamic>{'lat': null, 'lng': 2}), isFalse);
      expect(isValidRoamPoint(<String, dynamic>{'lat': 1}), isFalse);
      expect(isValidRoamPoint('x'), isFalse);
      expect(isValidRoamPoint(null), isFalse);
    });

    test('会话:缺 ts / ts 非法 / 数组里混坏点 → 非法', () {
      expect(isValidRoamSession(null), isFalse);
      expect(isValidRoamSession('x'), isFalse);
      expect(isValidRoamSession(<String, dynamic>{}), isFalse);
      expect(isValidRoamSession(<String, dynamic>{'ts': 'abc'}), isFalse);
      expect(isValidRoamSession(<String, dynamic>{'ts': 123, 'pois': 'x'}), isFalse);
      expect(
        isValidRoamSession(<String, dynamic>{
          'ts': 123,
          'track': <dynamic>[
            <String, dynamic>{'lat': 1, 'lng': 2},
            <String, dynamic>{'lat': 'bad', 'lng': 2},
          ],
        }),
        isFalse,
      );
      // 缺 pois/track 是合法(那次可能没点亮/没轨迹),只有坏才非法。
      expect(isValidRoamSession(<String, dynamic>{'ts': '123'}), isTrue);
      expect(
        isValidRoamSession(<String, dynamic>{
          'ts': 123,
          'pois': <dynamic>[<String, dynamic>{'lat': 1, 'lng': 2}],
        }),
        isTrue,
      );
    });

    test('tryParse:合法返回,非法返回 null(页面据此分流)', () {
      expect(RoamSession.tryParse(<String, dynamic>{'ts': 123}), isNotNull);
      expect(RoamSession.tryParse(<String, dynamic>{'ts': 'x'}), isNull);
    });
  });

  group('派生文案', () {
    RoamSession s(Map<String, dynamic> m) => RoamSession.tryParse(m)!;

    test('dateFull:非法 ts 显示「日期不可用」,不显示 1970 年', () {
      expect(s(<String, dynamic>{'ts': 0}).dateFull, '日期不可用');
      // 非法字符串 ts 解析即失败,tryParse 返回 null —— 这一条锁的是
      // 「坏数据必须拒绝,不能容忍成某张卡」。
      expect(RoamSession.tryParse(<String, dynamic>{'ts': 'abc'}), isNull);
    });

    test('时长:优先用已格式化的 time,否则由 durSec 派生', () {
      expect(s(<String, dynamic>{'ts': 1, 'time': '12:34'}).timeText, '12:34');
      expect(s(<String, dynamic>{'ts': 1, 'durSec': 65}).timeText, '01:05');
    });

    test('路线名:占位 zone 不算真足迹名,按地点数派生', () {
      expect(s(<String, dynamic>{'ts': 1, 'zone': '苏堤'}).routeName, '苏堤');
      expect(
        s(<String, dynamic>{
          'ts': 1,
          'zone': '这片街区',
          'pois': <dynamic>[
            <String, dynamic>{'name': 'A', 'lat': 1, 'lng': 2},
            <String, dynamic>{'name': 'B', 'lat': 1, 'lng': 2},
          ],
        }).routeName,
        'A等2处足迹回看',
      );
      expect(
        s(<String, dynamic>{
          'ts': 1,
          'pois': <dynamic>[
            <String, dynamic>{'name': 'A', 'lat': 1, 'lng': 2},
          ],
        }).routeName,
        'A周边足迹回看',
      );
      // 没有地点时才落到日期命名;ts 非法时兜底「城市漫游足迹」。
      expect(s(<String, dynamic>{'ts': 0}).routeName, '城市漫游足迹');
    });

    test('POI 图标名映射', () {
      RoamPoi p(String? cat) => RoamPoi.fromJson(<String, dynamic>{'cat': cat});
      expect(p('merchant').iconName, 'poi-shop');
      expect(p('park').iconName, 'poi-park');
      expect(p(null).iconName, 'poi-landmark');
      expect(p('landmark').iconName, 'poi-landmark');
    });

    test('distance 数字与字符串都能收', () {
      expect(s(<String, dynamic>{'ts': 1, 'distance': 2.5}).distance, 2.5);
      expect(s(<String, dynamic>{'ts': 1, 'distance': '1.2'}).distance, 1.2);
      expect(s(<String, dynamic>{'ts': 1}).distance, isNull);
    });
  });

  group('历史卡片派生', () {
    RoamHistoryEntry e(Map<String, dynamic> m) =>
        RoamHistoryEntry(RoamSession.tryParse(m)!);

    test('封面取第一张照片,照片可以是字符串或 {path}', () {
      expect(
        e(<String, dynamic>{
          'ts': 1,
          'photos': <dynamic>['u1', 'u2'],
        }).cover,
        'u1',
      );
      expect(
        e(<String, dynamic>{
          'ts': 1,
          'photos': <dynamic>[
            <String, dynamic>{'path': 'p1'},
          ],
        }).cover,
        'p1',
      );
      expect(e(<String, dynamic>{'ts': 1}).cover, '');
    });

    test('勋章行:空值不占位', () {
      expect(
        e(<String, dynamic>{'ts': 1, 'medal': 'm', 'shopMedalName': ''}).medals,
        <String>['m'],
      );
      expect(e(<String, dynamic>{'ts': 1}).medals, isEmpty);
    });

    test('出发/到达缩写:去掉虚词取前两字,全没了兜底「城西」', () {
      expect(e(<String, dynamic>{'ts': 1, 'zone': '苏堤'}).zoneCode, '苏堤');
      expect(e(<String, dynamic>{'ts': 1, 'zone': '这片街区'}).zoneCode, '城西');
      expect(e(<String, dynamic>{'ts': 1}).zoneCode, '漫游');
    });

    test('汇总:行程数/公里/点亮店铺数', () {
      final sum = RoamHistorySummary.fromSessions(<RoamSession>[
        RoamSession.tryParse(<String, dynamic>{'ts': 1, 'distance': 1.2, 'shops': 2})!,
        RoamSession.tryParse(<String, dynamic>{'ts': 2, 'distance': '2.3', 'shops': 1})!,
      ]);
      expect(sum.trips, 2);
      expect(sum.kmText, '3.5');
      expect(sum.shops, 3);
    });
  });
}
