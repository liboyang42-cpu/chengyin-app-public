import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/badge_wall.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_logic.dart';

void main() {
  group('categoryToTrack:未知类别落 0,CO_CREATE 两种写法都归 4', () {
    test('标准类别', () {
      expect(trackOf('EXPLORE'), 0);
      expect(trackOf('CREATE'), 1);
      expect(trackOf('ORGANIZE'), 2);
      expect(trackOf('CONNECT'), 3);
    });
    test('CO_CREATE / CO-CREATE / COCREATE 都归 4', () {
      expect(trackOf('CO_CREATE'), 4);
      expect(trackOf('CO-CREATE'), 4);
      expect(trackOf('COCREATE'), 4);
    });
    test('未知/缺失 → 0,不崩', () {
      expect(trackOf('garbage'), 0);
      expect(trackOf(null), 0);
      expect(trackOf('toString'), 0);
    });
  });

  BadgeWallItem item({
    String badgeName = '开始在场',
    String category = 'EXPLORE',
    bool unlocked = true,
    String? unlockTime = '2026-07-12 10:30:00',
    String unlockHint = '完成第一次打卡',
    String statement = '你来了',
  }) => BadgeWallItem(
    badgeCode: 'FIRST_STEP',
    badgeName: badgeName,
    nameEn: 'First Step',
    statement: statement,
    iconUrl: '',
    assetType: 'IDENTITY',
    category: category,
    unlockHint: unlockHint,
    unlocked: unlocked,
    unlockTime: unlockTime,
  );

  group('identityBadgeView', () {
    test('已点亮:展示日期(只到天),来源=身份卡+类别', () {
      final v = identityBadgeView(item());
      expect(v.locked, isFalse);
      expect(v.timeText, '2026-07-12');
      expect(v.source, '城市身份卡 · 探索');
      expect(v.cond, '完成第一次打卡');
    });

    test('★ 未点亮 → 未点亮;已点亮但拿不到时间 → "—" 不编日期', () {
      expect(identityBadgeView(item(unlocked: false)).timeText, '未点亮');
      expect(
        identityBadgeView(item(unlockTime: null)).timeText,
        '—',
        reason: '拿到 null 与拿到日期是两回事,不能用假日期或空串冒充',
      );
    });

    test('名字缺失 → 城市身份卡 兜底', () {
      expect(identityBadgeView(item(badgeName: '')).name, '城市身份卡');
    });
  });

  MedalWallItem medal({
    String kind = '',
    String style = 'enamel',
    String medalName = '城墙勋章',
    String medalImg = 'https://x/y.png',
    String? getTime = '2026-07-13 09:00:00',
    String condition = '完成绑定此勋章模板的城市节点',
  }) => MedalWallItem(
    templateId: 3,
    medalImg: medalImg,
    medalName: medalName,
    style: style,
    topicId: 5,
    getTime: getTime,
    condition: condition,
    kind: kind,
    badgeCode: '',
  );

  group('medalBadgeView:成就与城市纪念章两条装配线', () {
    test('★ 成就行没有条件字段 → cond 空,不套用城市节点条件', () {
      final v = medalBadgeView(medal(kind: 'achievement', condition: ''));
      expect(v.source, '成长成就');
      expect(v.cond, '', reason: 'player_badge 接口没有条件字段,不能编造');
      expect(v.tierZh, '成就徽章');
    });

    test('城市纪念章:style 保留(珐琅可进 3D),缺省按 glow', () {
      final enamel = medalBadgeView(medal(style: 'enamel'));
      expect(enamel.style, 'enamel');
      final glow = medalBadgeView(medal(style: ''));
      expect(glow.style, 'glow', reason: '后端未配 style 时不能丢「查看3D」能力');
      expect(glow.cond, '完成绑定此勋章模板的城市节点');
    });
  });

  group('wallDateText(displayDate 移植)', () {
    test('纯日期串:合法原样返回', () {
      expect(wallDateText('2026-07-12'), '2026-07-12');
    });
    test('非法日期 → null(2-30 / 13 月 / 0 日)', () {
      expect(wallDateText('2026-02-30'), isNull);
      expect(wallDateText('2026-13-01'), isNull);
      expect(wallDateText('2026-07-00'), isNull);
    });
    test('闰年 2-29 合法,平年 2-29 非法', () {
      expect(wallDateText('2024-02-29'), '2024-02-29');
      expect(wallDateText('2026-02-29'), isNull);
    });
    test('带时分秒(naive 中国串)→ 日期部分', () {
      expect(wallDateText('2026-07-12 10:30:00'), '2026-07-12');
      expect(wallDateText('2026-07-12T23:59:59.999'), '2026-07-12');
    });
    test('带显式时区 → 换算成中国日历日', () {
      // 7-12 23:00+00:00 = 中国 7-13 07:00
      expect(wallDateText('2026-07-12T23:00:00Z'), '2026-07-13');
      expect(wallDateText('2026-07-12T23:00:00+05:00'), '2026-07-13');
      expect(wallDateText('2026-07-13T01:00:00+08:00'), '2026-07-13');
    });
    test('非法时刻(24 时 / 60 分 / 乱串)→ null', () {
      expect(wallDateText('2026-07-12 24:00:00'), isNull);
      expect(wallDateText('2026-07-12 10:60:00'), isNull);
      expect(wallDateText('garbage'), isNull);
      expect(wallDateText(null), isNull);
    });
    test('epoch 毫秒 → 中国日历日', () {
      // 2026-07-12 00:00:00 +08:00 = 1783785600000
      expect(wallDateText(1783785600000), '2026-07-12');
      // 2026-07-11 16:00:00Z = 中国 7-12 00:00,同一时刻
      expect(wallDateText(1783785600000), '2026-07-12');
    });
    test('epoch 非法(0 / 负数 / NaN)→ null', () {
      expect(wallDateText(0), isNull);
      expect(wallDateText(-1), isNull);
    });
  });

  group('buildLegend:只列墙上真有的类别', () {
    test('按轨道聚合数量', () {
      final badges = <WallBadgeView>[
        identityBadgeView(item()),
        identityBadgeView(item(category: 'CO_CREATE', badgeName: '共创卡')),
        identityBadgeView(item(category: 'ORGANIZE', badgeName: '组织卡')),
      ];
      final legend = buildLegend(badges);
      expect(legend.map((e) => '${e.zh}${e.count}'), <String>[
        '探索1',
        '组织1',
        '共创1',
      ]);
    });
    test('空墙 → 空图例', () {
      expect(buildLegend(const <WallBadgeView>[]), isEmpty);
    });
  });

  group('buildFamilyGroups:列表视图三族分组标题(真源 index.js:16-20)', () {
    test('三族各一枚 → 固定顺序 + 中文标题', () {
      final groups = buildFamilyGroups(<WallBadgeView>[
        medalBadgeView(medal(kind: 'achievement', condition: '')),
        medalBadgeView(medal()),
        identityBadgeView(item()),
      ]);
      expect(groups.map((WallFamilyGroup g) => g.title), <String>[
        '城市身份卡',
        '城市纪念章',
        '成长成就',
      ], reason: '组顺序按族表固定,不随传入顺序');
      expect(groups.every((WallFamilyGroup g) => g.items.length == 1), isTrue);
    });

    test('只有身份卡 → 只剩一组;空墙 → 空列表', () {
      final one = buildFamilyGroups(<WallBadgeView>[identityBadgeView(item())]);
      expect(one.map((WallFamilyGroup g) => g.key), <String>['identity']);
      expect(
        buildFamilyGroups(const <WallBadgeView>[]),
        isEmpty,
        reason: '空族不占标题(真源 filter items.length)',
      );
    });
  });
}
