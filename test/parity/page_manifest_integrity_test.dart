import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 页面一致性 manifest 的**自洽门禁**。
///
/// `tool/page_parity.py` 需要兄弟仓(小程序快照)才能跑,CI 里没有,
/// 所以它一直是「人工工具」——manifest 写歪了没人拦。这个测试只读仓内文件,
/// 把「manifest 自称的落点真的存在」变成机器判据。
///
/// 判据分五层,每层都在 `_负控` 里钉了反例(坏数据必须被拦下):
/// 1. 母页条目数 = 小程序页数(130),`miniPage` 不重复;
/// 2. 每条 `source` 文件真实存在,且文件里真有 `marker` 那个 Widget 类;
/// 3. 每条 `route` 类条目的 carrier 类**真的被 `app_router.dart` 用到**
///    —— 防「页面写了但没接进路由」这种假对齐;
/// 4. 平台例外(`reason` 代替 `source`)有上限,防它变成默认逃生门。
/// 5. `appRoute`(App 从母页拆出的可深链子路由,如 /ticket/:id)不占母页
///    落点位,但必须:母页在册、route 在路由表且当场构造 marker 类、
///    带 reason、route 不与其他条目重复 —— 登记即受审,防它成免检通道
///    (b1-sim-club-2 N2;真源页不存在独立路由,见 tool/page_parity.py 的
///    APP_ROUTE_KIND 注释)。

// 页数真源 = 小程序 `github/master` 的 `app.json`(pages + subPackages),
// 与 `tool/page_parity.py` 的 `EXPECTED_XCX_PAGE_COUNT` 同值,两处必须一起改。
// 2026-09-22(gap-new-pages)128 → 130:`pages/topic/pricing/partner/index` 回潮
// + 新增 `subpackagePrefab/index`(预制人生),两页都在 app.json 里。
const int _pageCount = 130;
const String _appRouteKind = 'appRoute';

List<Map<String, dynamic>> _parse(String text) => <Map<String, dynamic>>[
  for (final dynamic raw in jsonDecode(text) as List<dynamic>)
    raw as Map<String, dynamic>,
];

List<Map<String, dynamic>> _pageEntries(List<Map<String, dynamic>> manifest) =>
    manifest
        .where((Map<String, dynamic> e) => e['kind'] != _appRouteKind)
        .toList(growable: false);

List<Map<String, dynamic>> _appRouteEntries(
  List<Map<String, dynamic>> manifest,
) => manifest
    .where((Map<String, dynamic> e) => e['kind'] == _appRouteKind)
    .toList(growable: false);

List<String> _duplicateKeys(List<Map<String, dynamic>> manifest) {
  final List<Map<String, dynamic>> pages = _pageEntries(manifest);
  final Set<String> seen = <String>{};
  return <String>[
    for (final Map<String, dynamic> entry in pages)
      if (!seen.add(entry['miniPage'] as String)) entry['miniPage'] as String,
  ];
}

String? _unreachableSource(
  Map<String, dynamic> entry,
  String Function(String path) readFile,
  bool Function(String path) exists,
) {
  final dynamic source = entry['source'];
  if (source is! String) return null; // 平台例外,由 _platformExceptions 守
  final String path = 'lib/$source';
  if (!exists(path)) return '${entry['miniPage']} → $path 不存在';
  final String marker = entry['marker'] as String;
  if (!readFile(path).contains(marker)) {
    return '${entry['miniPage']} → $marker 不在 $path 里';
  }
  return null;
}

String? _unwiredCarrier(Map<String, dynamic> entry, String router) {
  final String kind = entry['kind'] as String;
  if (kind != 'route' && kind != _appRouteKind) return null;
  final String carrier = (entry['marker'] as String).replaceFirst('class ', '');
  if (router.contains(carrier)) return null;
  return '${entry['miniPage']} → $carrier 未被 app_router.dart 使用';
}

/// appRoute 条目专属判据:母页在册、带 reason、route 非空且在路由表里
/// 当场构造 marker 类、route 不与其他条目重复。
List<String> _appRouteProblems(
  List<Map<String, dynamic>> manifest,
  String router,
) {
  final Set<String> parents = _pageEntries(
    manifest,
  ).map((Map<String, dynamic> e) => e['miniPage'] as String).toSet();
  final List<Map<String, dynamic>> appRoutes = _appRouteEntries(manifest);
  final Set<String> routes = <String>{};
  final List<String> problems = <String>[];
  for (final Map<String, dynamic> entry in appRoutes) {
    final String route = entry['route'] as String? ?? '';
    final String marker = entry['marker'] as String? ?? '';
    final String label = '[appRoute] ${entry['miniPage']} → $route';
    if (!parents.contains(entry['miniPage'])) {
      problems.add('$label 母页不在册(不是任何小程序页的落点条目)');
    }
    if ((entry['reason'] as String?)?.trim().isNotEmpty != true) {
      problems.add('$label 没写 reason(它从母页拆出了什么)');
    }
    if (route.isEmpty || !routes.add(route)) {
      problems.add('$label route 为空或重复登记');
    }
    // 精确到 `path: '<route>'`:路由表里声明了这条 GoRoute 才算数,
    // 只 grep 类名会被 import 行/别的页顶包。
    if (!router.contains("path: '$route'")) {
      problems.add('$label app_router.dart 没有声明这条路由');
    }
    final String className = marker.replaceFirst('class ', '');
    final RegExp constructor = RegExp(RegExp.escape(className) + r'\s*\(');
    final int pathAt = router.indexOf("path: '$route'");
    if (pathAt >= 0) {
      final String tail = router.substring(pathAt);
      final int end = tail.indexOf('GoRoute(', 10);
      final String block = end < 0 ? tail : tail.substring(0, end);
      if (!constructor.hasMatch(block)) {
        problems.add('$label 路由块里没有构造 $className');
      }
    }
  }
  // route/component 条目不许借用 appRoute 的 route(一条路由两个主键 = 台账说谎)。
  for (final Map<String, dynamic> entry in _pageEntries(manifest)) {
    final String route = entry['route'] as String? ?? '';
    if (entry['kind'] == _appRouteKind) continue;
    if (route.isNotEmpty &&
        appRoutes.any((Map<String, dynamic> a) => a['route'] == route)) {
      problems.add('${entry['miniPage']} 与 appRoute 共用 route $route');
    }
  }
  return problems;
}

List<String> _platformExceptions(List<Map<String, dynamic>> manifest) =>
    <String>[
      for (final Map<String, dynamic> entry in manifest)
        if (entry['source'] is! String) entry['miniPage'] as String,
    ];

List<String> _mixedEntries(List<Map<String, dynamic>> manifest) => <String>[
  for (final Map<String, dynamic> entry in manifest)
    if (entry['source'] != null &&
        ((entry['reason'] as String?)?.isNotEmpty ?? false) &&
        entry['kind'] != _appRouteKind)
      // appRoute 的 source+reason 是**必填**(见 _appRouteProblems),不算混写。
      entry['miniPage'] as String,
];

void main() {
  final List<Map<String, dynamic>> manifest = _parse(
    File('tool/page_parity_manifest.json').readAsStringSync(),
  );
  final String router = File(
    'lib/core/router/app_router.dart',
  ).readAsStringSync();
  bool exists(String path) => File(path).existsSync();
  String readFile(String path) => File(path).readAsStringSync();

  test('manifest 与小程序页数对齐且 miniPage 唯一', () {
    expect(
      _pageEntries(manifest).length,
      _pageCount,
      reason:
          '小程序共 $_pageCount 页;对不上说明漏登记或留了已删页'
          '(appRoute 条目不占母页位,单独过审)。'
          '改之前先跑 `python3 tool/page_parity.py`。',
    );
    expect(_duplicateKeys(manifest), isEmpty, reason: '同一页面挂了两个 carrier');
  });

  test('每条落点的 source 文件存在且 marker 类真的在里面', () {
    final List<String> broken = <String>[
      for (final Map<String, dynamic> entry in manifest)
        ?_unreachableSource(entry, readFile, exists),
    ];
    expect(broken, isEmpty, reason: broken.join('\n'));
  });

  test('route 类条目的 carrier 真的接进了 app_router', () {
    final List<String> unwired = <String>[
      for (final Map<String, dynamic> entry in manifest)
        ?_unwiredCarrier(entry, router),
    ];
    expect(
      unwired,
      isEmpty,
      reason:
          'manifest 声称有落点,但页面没接进路由,用户点不到:\n'
          '${unwired.join('\n')}',
    );
  });

  test('appRoute 登记全部受审:母页在册、路由在表、带 reason、不重复', () {
    final List<String> problems = _appRouteProblems(manifest, router);
    expect(
      problems,
      isEmpty,
      reason: 'App 拆出的子路由登记不成立:\n${problems.join('\n')}',
    );
    // 台账不许是空的:本票收口的 6 条(b1-sim-club-2 N2)必须在册。
    expect(
      _appRouteEntries(manifest).map((Map<String, dynamic> e) => e['route']),
      containsAll(<String>[
        '/club-feed',
        '/club/:id/leaderboard',
        '/club/:id/edition-report',
        '/club/:id/dissolution-blockers',
        '/ticket/:id',
        '/ticket/:id/pass',
      ]),
    );
  });

  test('平台例外有上限,不许变成默认逃生门,也不许与 source 混写', () {
    expect(
      _platformExceptions(manifest).length,
      lessThanOrEqualTo(3),
      reason:
          'app.json 有页面就得有 App 落点;只能用 reason 登记真平台差异'
          '(如系统相册取代独立裁切页)。现在:'
          '${_platformExceptions(manifest).join(', ')}',
    );
    expect(_mixedEntries(manifest), isEmpty, reason: '要么是真落点,要么是平台例外');
  });

  group('负控:坏 manifest 必须被这四条判据拦下', () {
    test('重复 miniPage 会被拦', () {
      expect(
        _duplicateKeys(<Map<String, dynamic>>[
          <String, dynamic>{'miniPage': 'a'},
          <String, dynamic>{'miniPage': 'a'},
        ]),
        <String>['a'],
      );
      expect(_duplicateKeys(manifest), isEmpty);
    });

    test('source 不存在 / marker 缺席会被拦', () {
      const Map<String, dynamic> missingFile = <String, dynamic>{
        'miniPage': 'x',
        'source': 'feature/nope/nope_page.dart',
        'marker': 'class NopePage',
      };
      const Map<String, dynamic> missingMarker = <String, dynamic>{
        'miniPage': 'y',
        'source': 'feature/feed/feed_page.dart',
        'marker': 'class DefinitelyNotInThatFile',
      };
      expect(_unreachableSource(missingFile, readFile, exists), isNotNull);
      expect(_unreachableSource(missingMarker, readFile, exists), isNotNull);
      expect(
        _unreachableSource(
          <String, dynamic>{
            'miniPage': 'z',
            'source': 'feature/feed/feed_page.dart',
            'marker': 'class FeedPage',
          },
          readFile,
          exists,
        ),
        isNull,
        reason: '真落点不许被误判',
      );
    });

    test('页面存在但没接进路由会被拦', () {
      expect(
        _unwiredCarrier(<String, dynamic>{
          'miniPage': 'w',
          'kind': 'route',
          'marker': 'class DefinitelyNotRoutedPage',
        }, router),
        isNotNull,
      );
      expect(
        _unwiredCarrier(<String, dynamic>{
          'miniPage': 'v',
          'kind': 'component',
          'marker': 'class DefinitelyNotRoutedPage',
        }, router),
        isNull,
        reason: '非 route 类条目不归这条判据管',
      );
    });

    test('source 与 reason 混写会被拦', () {
      expect(
        _mixedEntries(<Map<String, dynamic>>[
          <String, dynamic>{
            'miniPage': 'm',
            'source': 'feature/feed/feed_page.dart',
            'reason': '又想当落点又想当例外',
          },
        ]),
        <String>['m'],
      );
    });

    test('appRoute 坏登记会被拦:母页不在册 / 缺 reason / 路由不在表 / 与母页共用 route', () {
      final Map<String, dynamic> real = _appRouteEntries(manifest).first;
      List<String> problemsOf(Map<String, dynamic> entry) => _appRouteProblems(
        <Map<String, dynamic>>[..._pageEntries(manifest), entry],
        router,
      );
      expect(
        problemsOf(<String, dynamic>{...real, 'miniPage': 'pages/nope/index'}),
        isNotEmpty,
        reason: '母页不在册的 appRoute 必须判红',
      );
      expect(
        problemsOf(<String, dynamic>{...real, 'reason': ''}),
        isNotEmpty,
        reason: '没写拆出什么的 appRoute 必须判红',
      );
      expect(
        problemsOf(<String, dynamic>{...real, 'route': '/route/not/in/router'}),
        isNotEmpty,
        reason: '路由表里没有的登记必须判红',
      );
      final Map<String, dynamic> parentEntry = _pageEntries(manifest)
          .firstWhere(
            (Map<String, dynamic> e) => e['miniPage'] == real['miniPage'],
          );
      expect(
        problemsOf(<String, dynamic>{...real, 'route': parentEntry['route']}),
        isNotEmpty,
        reason: '与母页落点共用 route = 台账说谎,必须判红',
      );
      expect(_appRouteProblems(manifest, router), isEmpty, reason: '真登记不许被误判');
    });
  });
}
