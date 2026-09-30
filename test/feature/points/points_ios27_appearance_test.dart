// 积分域 a5-ios27-points-2 二轮外观复核的回归钉。
// 钉的是「字级已落到 iOS 梯级上、取色全走 CyPalette、页面不再套透明 Material」
// —— 防止下一遍又漂回 rpx÷2 私值。
// 真源:`/tmp/be-master` github/master components/cy/profile/index.wxss
// (.pts-hero / .pts-row / .pc-gs-link 各档字号字重)。
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/api/points_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/points_record.dart';
import 'package:chengyin_app/data/models/points_statistics.dart';
import 'package:chengyin_app/feature/points/points_hero.dart';
import 'package:chengyin_app/feature/points/points_page.dart';
import 'package:chengyin_app/feature/points/points_tasks_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme, DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design/scan_support.dart';

const List<String> _pointsSources = <String>[
  'lib/feature/points/points_page.dart',
  'lib/feature/points/points_hero.dart',
  'lib/feature/points/points_tasks_sheet.dart',
  'lib/feature/points/points_controller.dart',
];

/// 手册 §3.6/§3.8:呈现层取色一律 `CyPalette.of(context)`;
/// `CyTokens.*` 颜色常量与 `AppColors` 是暗色编译期常量/冻结别名层。
final RegExp _staticColor = RegExp(
  r'AppColors\.|CyTokens\.(bg|text|border|status|brand|state|overlay|input)\w',
);

/// T2:字号必须落在 iOS 梯级(`CyType.*`)上,不许再抄 rpx÷2 私值。
final RegExp _rawType = RegExp(r'CyTokens\.type\w+');

final RegExp _colorLiterals = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}');

List<String> _hitsOf(String source) => <String>[
  ..._staticColor
      .allMatches(stripComments(source))
      .map((RegExpMatch m) => m.group(0)!),
  ..._colorLiterals
      .allMatches(stripComments(source))
      .map((RegExpMatch m) => m.group(0)!),
];

/// 替身放在 **API 边界**(口径同 pages_official_points_golden_test.dart),
/// 让真 notifier 自己算分页,基准外的测试也不打真网络。
class _FakePointsApi implements PointsApi {
  _FakePointsApi([this.firstPage]);

  /// null = 用下面这份单条样例;给 [] = 空态。
  final List<PointsRecord>? firstPage;

  @override
  Future<List<PointsRecord>> list({
    int? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    if (pageNum != 1) return <PointsRecord>[];
    return firstPage ??
        <PointsRecord>[
          PointsRecord.fromJson(<String, dynamic>{
            'id': 1,
            'changeType': 1,
            'changePoints': 120,
            'afterPoints': 1380,
            'changeReason': '完成「静安夜跑」',
            'createTime': '2026-08-18 21:10:00',
          }),
        ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeRegistrationApi implements RegistrationApi {
  _FakeRegistrationApi(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Map<String, dynamic>>> pointsResultList() async => rows;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<dynamic> get _statOverride => <dynamic>[
  pointsStatProvider.overrideWith(
    (ref) async => PointsStatistics.fromJson(<String, dynamic>{
      'weekPoints': '320',
      'rankPercentage': '82%',
    }),
  ),
];

Widget _wrap(Widget home, {List<dynamic> overrides = const <dynamic>[]}) {
  // 镜像真机根(main.dart ChengyinApp):CupertinoApp + Theme(AppTheme.dark())。
  // 用 MaterialApp 当宿主会把裸 TextStyle(family=null,CyType 全档如此)
  // 落到 flutter_test 的 monospace 默认族上 —— 量出来的排版不是用户看的那份。
  return ProviderScope(
    overrides: overrides.cast(),
    child: CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(brightness: Brightness.dark),
      // 页内仍有 RefreshIndicator.adaptive 要 MaterialLocalizations(main.dart 同源)。
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) =>
          Theme(data: AppTheme.dark(), child: child!),
      home: home,
    ),
  );
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  test('本域取色全走 CyPalette:无静态色、无色字面量、无 rpx 私值字号;页面不套透明 Material 壳', () {
    for (final String path in _pointsSources) {
      final String code = codeOfFile(path);
      expect(_hitsOf(code), isEmpty, reason: '$path 仍在取静态色/字面量');
      expect(
        _rawType.allMatches(code).map((RegExpMatch m) => m.group(0)!),
        isEmpty,
        reason: '$path 还有没上 CyType 梯级的字号(T2)',
      );
    }
    expect(
      RegExp(r'\bMaterial\(').hasMatch(codeOfFile(_pointsSources.first)),
      isFalse,
      reason: 'Cupertino 页不许再套透明 Material 壳',
    );
  });

  test('负控:同一套判据喂合成违规源码必须红,喂注释不许红', () {
    expect(_hitsOf('color: AppColors.bgPage,'), isNotEmpty);
    expect(_hitsOf('color: CyTokens.textTertiary,'), isNotEmpty);
    expect(
      _hitsOf('decoration: BoxDecoration(color: Color(0xFF1C1C1E))'),
      isNotEmpty,
    );
    expect(_rawType.hasMatch('fontSize: CyTokens.typeDisplay'), isTrue);
    expect(_hitsOf('// color: AppColors.bgPage'), isEmpty);
    expect(
      _rawType.hasMatch(stripComments('// fontSize: CyTokens.typeDisplay')),
      isFalse,
    );
  });

  testWidgets(
    'hero 三档字级钉死:数值 Title1 28/700、标签 caption1 12、排名 caption2 11;分值不上色',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const CupertinoPageScaffold(child: PointsHero(balance: 1380)),
          overrides: _statOverride,
        ),
      );
      await tester.pumpAndSettle();

      final TextStyle value = _styleOf(tester, '1380');
      expect(value.fontSize, CyType.title1.fontSize);
      expect(value.fontWeight, FontWeight.w700, reason: 'T3:Bold 不堆 w800');
      expect(value.color, CyPalette.dark.textPrimary, reason: 'C1:黑白档,不上强调色');
      expect(_styleOf(tester, '我的积分').fontSize, CyType.caption1.fontSize);
      expect(
        _styleOf(tester, '超过 82% 的探索者').fontSize,
        CyType.caption2.fontSize,
      );
    },
  );

  testWidgets('任务行字级对齐真源 .pts-row:名 17/600、说明与次数 caption2 11、分 16/700', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (BuildContext c) => Center(
            child: CupertinoButton(
              onPressed: () => showPointsTasksSheet(c),
              child: const Text('开'),
            ),
          ),
        ),
        overrides: <dynamic>[
          registrationApiProvider.overrideWithValue(
            _FakeRegistrationApi(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 1,
                'eventType': 3,
                'title': '完成一次探店',
                'description': '到店核销即得',
                'value': 12,
                'pointsNum': 2,
                'status': 1,
              },
            ]),
          ),
        ],
      ),
    );
    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();

    expect(_styleOf(tester, '完成一次探店').fontSize, CyType.headline.fontSize);
    expect(_styleOf(tester, '完成一次探店').fontWeight, FontWeight.w600);
    expect(_styleOf(tester, '到店核销即得').fontSize, CyType.caption2.fontSize);
    expect(_styleOf(tester, '到店核销即得').color, CyPalette.dark.textTertiary);
    expect(_styleOf(tester, '+12').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, '+12').color, CyPalette.dark.textPrimary);
    expect(_styleOf(tester, '已获 2 次').fontSize, CyType.caption2.fontSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「如何获取积分」按真源 .pc-gs-link:12pt / text-tertiary,不落强调色 (C1/D5)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PointsPage(),
        overrides: <dynamic>[
          pointsApiProvider.overrideWithValue(_FakePointsApi()),
          ..._statOverride,
        ],
      ),
    );
    await tester.pumpAndSettle();

    final TextStyle link = _styleOf(tester, '如何获取积分');
    expect(link.fontSize, CyType.caption1.fontSize);
    expect(link.color, CyPalette.dark.textTertiary);
    // 真源 .pc-gs-link 是**纯文字** —— 不带 ⓘ。图标是源外装饰,
    // 首轮复核后曾加过又按源回退,这里钉住不再长回来。
    expect(
      find.descendant(
        of: find.byKey(const Key('points-how-to-earn')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
  });

  testWidgets('空态下面不再顶一句「没有更多了」(空态与尾注不并立)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const PointsPage(),
        overrides: <dynamic>[
          pointsApiProvider.overrideWithValue(_FakePointsApi(<PointsRecord>[])),
          ..._statOverride,
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无积分记录'), findsOneWidget);
    expect(find.text('没有更多了'), findsNothing);
  });

  testWidgets('字号放大 2.0 下积分页不溢出、不裁字、无异常 (T4)', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _wrap(
          const PointsPage(),
          overrides: <dynamic>[
            pointsApiProvider.overrideWithValue(_FakePointsApi()),
            ..._statOverride,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
