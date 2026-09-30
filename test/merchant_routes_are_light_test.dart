// 门禁:每条 `/merchant/**` 路由都必须包 `_merchantLight(...)`。
//
// 为什么需要:商家工作台在小程序里是**浅色**的(pages/merchant/** 每页
// @import merchant-light.wxss + onShow 调 merchantPageShow())。App 这边靠
// 路由外层包一个 Theme 实现,而「包一层」是**很容易在新增路由时漏掉**的动作 ——
// 漏了不会报错、不会抛异常,只是那一页悄悄变成黑底,和相邻商家页对不上。
// 这类「少做一步就静默错」的地方必须有门禁,不能靠记得。
//
// 负控:把任意一条 /merchant 路由的 _merchantLight( 去掉,本测试必须红。

import 'dart:io';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/source_text.dart';

/// 应当渲成浅色的路由前缀 —— 判据是**小程序对应页 @import merchant-light.wxss
/// 且无条件 onShow 切浅色**(pages/merchant/** 全部,加 coop 四页,加 topic 域的
/// `pages/topic/pricing`)。
///
/// ⚠️ 2026-09-18 更正:上一版注释写「pages/topic/pricing 是暗色」,**读错了**。
///   快照(master@90e66d70)实测 `pages/topic/pricing/index.wxml` 根节点是
///   `theme-merchant`、index.wxss 第 1 行 `@import merchant-light.wxss` ——
///   与 `pricing/partner` 同档,且 pairs 台账 E24 也把这一屏记在 role=merchant 名下。
///   App 此前没包浅色,整屏是玩家黑皮(与 club 剧情页那次的漏挂同一类)。
///
/// ⚠️ 不在这张表里的:8 个**按角色条件切**的页面(activity/detail、shezhi、
///   template…)—— 那些不是「整条路由恒浅」,不能用这道闸判,
///   得按商家视角在页面内部切。
const List<String> _kLightRoutes = <String>[
  '/merchant',
  '/merchant/coupons',
  '/coop-pool',
  '/coop-finance',
  '/coop/nearby',
  '/coop/candidates',
  '/topic/:id/pricing',
];

/// **条件**浅色的路由 —— 小程序对应页在 onShow 里 `if (isMerchantView)` 才切浅色,
/// 玩家看到的仍是暗色。这几条必须包 `_merchantLightIfMerchant(...)`,不是 `_merchantLight(...)`。
///
/// ⚠️ 这批比恒浅那批更容易漏:漏了**只有商家账号看得出来**,玩家视角一切正常,
///   自测时用玩家号点一圈是发现不了的。
const List<String> _kConditionalLightRoutes = <String>[
  '/activity/:id',
  '/official-inbox',
  '/official-mine',
  '/coop/invite/:topicId',
  '/settings',
  '/templates',
  '/template/:id',
  // 剧情与玩法页同款:真源 pages/club/topic-story 按 isMerchantViewer 切浅色。
  '/club/:id/topic/:topicId/story',
];

void main() {
  test('所有应为浅色的路由都包了浅色主题', () {
    final File file = File('lib/core/router/app_router.dart');
    expect(file.existsSync(), isTrue, reason: '路由表找不到了,门禁形同虚设');
    final List<String> lines = file.readAsLinesSync();

    final List<String> offenders = <String>[];
    int checked = 0;
    for (int i = 0; i < lines.length; i++) {
      if (!_kLightRoutes.any((String r) => lines[i].contains("path: '$r"))) {
        continue;
      }
      final String path =
          RegExp(r"path: '([^']+)'").firstMatch(lines[i])?.group(1) ?? '?';

      // builder 可能是单行箭头式,也可能是带 body 的多行式(里面 return 页面),
      // 两种都要能判 —— 只认单行会让多行那几条**静默漏检**。
      final StringBuffer body = StringBuffer();
      for (int j = i + 1; j < lines.length && j < i + 12; j++) {
        if (lines[j].contains("path: '")) break; // 进了下一条路由
        body.writeln(lines[j]);
        if (lines[j].contains('),') && body.toString().contains('builder:'))
          break;
      }
      checked++;
      if (!body.toString().contains('builder:')) {
        offenders.add('$path —— 找不到 builder,无法判定');
      } else if (!body.toString().contains('_merchantLight(')) {
        offenders.add('$path —— builder 没包 _merchantLight()');
      }
    }

    // ★ 没有这条,整个门禁在路由改名/重构后会变成「零条待检、恒绿」。
    expect(
      checked,
      greaterThanOrEqualTo(15),
      reason:
          '只扫到 $checked 条应为浅色的路由,少于已知的 15 条 —— '
          '要么路由表变了、要么正则失效,别让门禁静默降级成恒真',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          '这些商家路由会渲成黑底,与小程序浅色工作台不一致:\n'
          '${offenders.join('\n')}',
    );
  });

  test('所有条件浅色的路由都包了 _merchantLightIfMerchant', () {
    final List<String> lines = File(
      'lib/core/router/app_router.dart',
    ).readAsLinesSync();

    final List<String> offenders = <String>[];
    int checked = 0;
    for (int i = 0; i < lines.length; i++) {
      final String? path = _kConditionalLightRoutes
          .where((String r) => lines[i].contains("path: '$r'"))
          .firstOrNull;
      if (path == null) continue;

      final StringBuffer body = StringBuffer();
      for (int j = i; j < lines.length && j < i + 14; j++) {
        if (j > i && lines[j].contains("path: '")) break;
        body.writeln(lines[j]);
      }
      checked++;
      final String text = body.toString();
      if (!text.contains('_merchantLightIfMerchant(')) {
        offenders.add('$path —— 商家视角下不会变浅色');
      }
      // ★ 用错包装比不包更隐蔽:玩家也会看到浅色商家皮,而且门禁「看起来包了」。
      if (RegExp(r'_merchantLight\(').hasMatch(text)) {
        offenders.add('$path —— 用成了恒浅的 _merchantLight(),玩家也会变浅色');
      }
    }

    expect(
      checked,
      _kConditionalLightRoutes.length,
      reason:
          '只扫到 $checked 条,应为 ${_kConditionalLightRoutes.length} 条 —— '
          '路由改名了就把表一起改,别让门禁静默少检',
    );
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
  test('设置页的「关于」子路由也按商家视角切浅色', () {
    // `/settings/about` 在路由表里是**相对路径子路由**(`path: 'about'`),上面那张
    // 表按 `path: '<路由>'` 匹配,扫不到它 —— 父页包了、子路由漏包,只有商家
    // 账号看得出来(玩家视角一切正常)。
    // 真源 `pages/shezhi/about/index.wxml` 根节点与父页同款:
    // `{{isMerchantView ? 'theme-merchant' : 'theme-dark'}}`。
    final List<String> lines =
        File('lib/core/router/app_router.dart').readAsLinesSync();
    final int parent = lines.indexWhere(
      (String l) => l.contains("path: '/settings',"),
    );
    expect(parent, greaterThanOrEqualTo(0), reason: '找不到 /settings 路由,改表');
    final int about = lines
        .skip(parent)
        .toList()
        .indexWhere((String l) => l.contains("path: 'about',"));
    expect(about, greaterThanOrEqualTo(0), reason: '/settings 下没有 about 子路由了');
    final String block = lines.sublist(parent + about, parent + about + 10).join('\n');
    expect(
      block,
      contains('_merchantLightIfMerchant('),
      reason: '商家点进「关于」会看到一屏纯黑 —— 与真源 theme-merchant 不一致',
    );
  });

  test('★★ 商家页的 golden 必须用浅色主题拍 —— 深色版是没人会看到的画面', () {
    // golden_theme.dart 早写了这条:「用 goldenTheme 拍出来的黑底是
    // **没人会看到的画面**,基准图会变成假证据」。
    // 而 2026-08-19 我这一轮新建的五个商家页全拍成了深色 —— 写了纪律还是犯。
    //
    // 判据:golden 测试里凡是渲染 lib/feature/merchant/ 下的页面,
    //   那个用例必须出现 merchantGoldenTheme。
    // ⚠️ 只认**真实渲染**,不认注释里提到 ——
    //   第一版我照全文扫,把一个只在注释里写了 MerchantScanPage 的文件
    //   判成了违规(它渲的其实是玩家侧的 TicketDetailPage/PassPage)。
    //   剥注释后再匹配 `const XxxPage(` 这种构造调用。
    final RegExp merchantPage = RegExp(
      r'const\s+(\w*Merchant\w*Page|Project\w*Page)\(',
    );

    final List<String> offenders = <String>[];
    for (final FileSystemEntity e in Directory(
      'test/golden',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('_test.dart')) continue;
      final String src = codeOf(e.path);
      // 只看真的渲染了商家页的文件。
      if (!merchantPage.hasMatch(src)) continue;
      if (!src.contains('merchantGoldenTheme')) {
        offenders.add(e.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '这些 golden 渲染了商家页却没用 merchantGoldenTheme —— '
          '拍出来的黑底是用户看不到的画面,基准图会变成假证据:\n'
          '${offenders.join('\n')}',
    );
  });

  // ★★ 只挂 Material `Theme` **换不动 CupertinoTheme** —— 2026-09-18 实测:
  //   根是 `CupertinoApp`(main.dart:47,它本身就是一层 `CupertinoTheme`),
  //   而 Material `Theme` 取 Cupertino 主题时**优先继承祖先**(flutter
  //   `material/theme.dart::_inheritedCupertinoThemeData`:祖先里有
  //   `InheritedCupertinoTheme` 就不看自己的 `cupertinoOverrideTheme`)——
  //   于是 `_merchantLight` 里那层 Material override 在真机上形同虚设:
  //   `CyPalette.of().bgPage` 已是浅色,但 `CupertinoTheme.brightnessOf()` 仍 dark,
  //   页面里所有 Cupertino 控件(导航栏、`CupertinoTextField` 文字/占位、
  //   无显式前景的 `CupertinoButton`)照旧取暗色值。
  //   所以恒浅包装必须自己再挂一层 `CupertinoTheme`;下面两条守住它:
  //   ① 静态:包装里必须有 `CupertinoTheme(`(负控:删掉它,①必须红);
  //   ② 负控:证明「只挂 Material Theme」真的不够(Flutter 哪天改了这个继承顺序,
  //      ②会红 —— 那时才可以把包装里那层 CupertinoTheme 去掉)。
  test('恒浅包装必须自己挂 CupertinoTheme(只挂 Material Theme 换不动它)', () {
    final String source = codeOf('lib/core/router/app_router.dart');
    // main 侧把「Material `Theme` + `CupertinoTheme` 一起挂」抽成了共用助手,
    // 商家域与创建域都委托给它 —— 那层 CupertinoTheme 现在住在 `_lightScope` 里,
    // 判据跟着委托走(只看 `_merchantLight` 的就地展开会漏掉真正挂它的那层)。
    final int start = source.indexOf('Widget _lightScope(');
    expect(start, greaterThan(-1), reason: '找不到 _lightScope,门禁形同虚设');
    final String body = source.substring(
      start,
      (start + 1500).clamp(0, source.length),
    );
    expect(
      body.contains('CupertinoTheme('),
      isTrue,
      reason: '只挂 Material `Theme` 时,浅色页里的 Cupertino 控件仍取暗色值',
    );
    expect(
      source.contains('_lightScope(AppTheme.merchantLight()'),
      isTrue,
      reason: '_merchantLight 必须继续走这层 —— 自己另起一份就不受本门禁保护',
    );
  });

  testWidgets('负控:祖先有 CupertinoTheme 时,只挂 Material Theme 仍然读出暗色', (
    WidgetTester tester,
  ) async {
    late Brightness brightness;
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (BuildContext context) => Theme(
            data: AppTheme.merchantLight(),
            child: Builder(
              builder: (BuildContext inner) {
                brightness = CupertinoTheme.brightnessOf(inner);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      brightness,
      Brightness.dark,
      reason:
          '这条是**负控**:它红说明 Flutter 改成「Material Theme 能覆盖祖先 '
          'Cupertino 主题」了,那时才可以把 _merchantLight 里那层 CupertinoTheme 去掉',
    );
  });
}
