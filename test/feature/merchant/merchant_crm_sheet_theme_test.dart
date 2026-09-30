// 商家 CRM 运营台的选择半屏必须**恒浅** —— 这一页是商家域(D10① 商家=恒浅)。
//
// 为什么单独一条:`showCupertinoSheet` 把 sheet 挂在 **rootNavigator** 上
// (Flutter `sheet.dart` 的 `Navigator.of(context, rootNavigator: true)`),
// 而浅色是**路由 builder 那层** 的 `Theme`(`app_router._merchantLight`)。
// sheet 因此是路由页的**兄弟**而不是子节点,拿不到浅色 Theme ——
// `CyPalette.of(sheetContext)` 会掉到根主题 `AppTheme.dark()`,浅色页上弹出
// 一块黑面板。仓里已有同类登记(`test/light_pages_no_static_colors_test.dart`
// 头注释的 publish_chooser_sheet)。
//
// 本用例按**生产**的主题层级搭树:根暗(如 `main.dart` 的 `AppTheme.dark()`)
// + 路由层浅(`_merchantLight`),而不是像其余用例那样直接把整棵树设成浅色 ——
// 后者会掩盖这个 bug。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';

import '../../support/fake_crm_console_api.dart';

const MerchantCrmAccess _fullAccess = MerchantCrmAccess(
  active: true,
  canReadCrm: true,
  canSegmentCrm: true,
  canExportCrm: true,
  canWriteMarketing: true,
  canManageCoupons: true,
);

/// 生产同构:根 = 暗色(玩家侧),路由层 = 浅色(商家域)。
Widget _prodLikeTree(FakeCrmConsoleApi api) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    merchantCrmAccessProvider.overrideWith((ref) async => _fullAccess),
    merchantCrmConsoleApiProvider.overrideWithValue(api),
  ],
  child: CupertinoApp(
    theme: const CupertinoThemeData(brightness: Brightness.dark),
    // 生产同款(`main.dart:66-68`):页里还有 Material 组件(RefreshIndicator
    // 等)要 MaterialLocalizations,少这一味会在**有名单**时直接断言崩 ——
    // 空名单的用例撞不到,别把「测试树缺料」当成页面 bug。
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      DefaultMaterialLocalizations.delegate,
    ],
    builder: (BuildContext context, Widget? child) => Theme(
      data: AppTheme.dark(),
      child: child ?? const SizedBox.shrink(),
    ),
    home: Builder(
      builder: (BuildContext context) =>
          Theme(data: AppTheme.merchantLight(), child: const MerchantCustomerPage()),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final Finder target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★★ 选择半屏在半浅树里仍是浅色(不能掉到根暗主题)', (WidgetTester tester) async {
    final FakeCrmConsoleApi api = FakeCrmConsoleApi(
      segmentRows: <CrmSavedSegment>[
        CrmSavedSegment(id: 3, name: '复购客'),
      ],
    );
    await _pump(tester, _prodLikeTree(api));

    // 打开触达面板 → 点分群选择行 → 半屏弹起(全走界面,不直接调函数)。
    await _tapText(tester, '管理');
    await _tapText(tester, '合规触达');
    await _tapText(tester, '复购客');
    expect(find.text('选择保存分群'), findsOneWidget);

    final Material sheet = tester.widget<Material>(
      find
          .ancestor(of: find.text('选择保存分群'), matching: find.byType(Material))
          .first,
    );
    expect(
      sheet.color,
      CyPalette.light.bgPage,
      reason: 'sheet 底色应是浅色页底;拿到深色 = 掉到根暗主题了',
    );
    expect(
      sheet.color,
      isNot(CyPalette.dark.bgPage),
      reason: '浅色商家页上不许弹黑面板',
    );
  });
  testWidgets('★★ 定向广播半屏同样是浅色(新半屏也得把宿主主题带过去)', (WidgetTester tester) async {
    final FakeCrmConsoleApi api = FakeCrmConsoleApi(
      page: FakeCrmConsoleApi.pageOf(<Map<String, dynamic>>[
        FakeCrmConsoleApi.rowJson(),
      ]),
    );
    await _pump(tester, _prodLikeTree(api));

    await _tapText(tester, '定向广播');
    expect(find.text('定向广播'), findsNWidgets(2), reason: '底栏 + 半屏标题');

    final CupertinoPageScaffold sheet = tester.widget<CupertinoPageScaffold>(
      find
          .ancestor(
            of: find.text('1 人 · 点发送先核一遍可触达人数'),
            matching: find.byType(CupertinoPageScaffold),
          )
          .first,
    );
    expect(
      sheet.backgroundColor,
      CyPalette.light.bgPage,
      reason: 'sheet 底色应是浅色页底;拿到深色 = 掉到根暗主题了',
    );
    expect(sheet.backgroundColor, isNot(CyPalette.dark.bgPage));
  });
}
