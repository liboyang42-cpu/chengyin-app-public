import 'package:chengyin_app/feature/auth/login_gate.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';
import 'package:chengyin_app/core/theme/cy_palette.dart';
import 'package:chengyin_app/core/widgets/cy_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget _host({
  required _RouteObserver observer,
  required void Function(BuildContext context) open,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      navigatorObservers: <NavigatorObserver>[observer],
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('登录入口走原生 sheet presenter，保留入口顺序、协议和原页返回', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RouteObserver observer = _RouteObserver();
    await tester.pumpWidget(
      _host(
        observer: observer,
        open: (BuildContext context) =>
            showLoginSheet(context, appleSignInAvailability: () async => true),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // S2:承载走 B1 `native_flutter_sheet`;测试环境无插件,回退
    // showCupertinoSheet —— 两条路径都由 presenter 给抓手/detent/下滑关闭,
    // 页面不再自绘假抓手,也不再自拼 CupertinoPopupSurface 几何。
    expect(
      observer.pushed.whereType<CupertinoSheetRoute<void>>(),
      hasLength(1),
    );
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CySheetGrab), findsNothing);

    final CupertinoButton primary = tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('微信登录'),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(primary.color, CyPalette.dark.actionPrimaryBg);
    expect(primary.foregroundColor, CyPalette.dark.actionPrimaryFg);
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('微信登录'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .height,
      44,
    );
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('手机号登录'),
              matching: find.byType(CupertinoButton),
            ),
          )
          .height,
      44,
    );
    expect(find.text('微信登录'), findsOneWidget);
    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.text('通过 Apple 登录'), findsOneWidget);
    expect(find.textContaining('登录即同意'), findsOneWidget);

    final double wechatY = tester.getCenter(find.text('微信登录')).dy;
    final double phoneY = tester.getCenter(find.text('手机号登录')).dy;
    final double appleY = tester.getCenter(find.text('通过 Apple 登录')).dy;
    final double legalY = tester.getCenter(find.textContaining('登录即同意')).dy;
    expect(wechatY, lessThan(phoneY));
    expect(phoneY, lessThan(appleY));
    expect(appleY, lessThan(legalY));

    Navigator.of(tester.element(find.text('登录城瘾'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('手机号登录走原生 sheet presenter，保持字段合同', (WidgetTester tester) async {
    final _RouteObserver observer = _RouteObserver();
    await tester.pumpWidget(
      _host(observer: observer, open: showPhoneLoginSheet),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      observer.pushed.whereType<CupertinoSheetRoute<void>>(),
      hasLength(1),
    );
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));

    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].keyboardType, TextInputType.phone);
    expect(fields[0].maxLength, 11);
    expect(fields[0].clearButtonMode, OverlayVisibilityMode.editing);
    expect(fields[1].keyboardType, TextInputType.number);
    expect(fields[1].maxLength, 6);
    expect(
      (fields[0].decoration as BoxDecoration).color,
      CyPalette.dark.inputBgEmpty,
    );
    expect(fields[0].style?.color, CyPalette.dark.textPrimary);
    expect(fields[0].placeholderStyle?.color, CyPalette.dark.textSecondary);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).first, '123');
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('phone-login-feedback'))).data,
      '请输入 11 位手机号',
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('从登录入口展开手机号表单，返回后仍回到原登录入口', (WidgetTester tester) async {
    final _RouteObserver observer = _RouteObserver();
    await tester.pumpWidget(
      _host(
        observer: observer,
        open: (BuildContext context) =>
            showLoginSheet(context, appleSignInAvailability: () async => false),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();
    expect(find.text('获取验证码'), findsOneWidget);
    // F1 修复:表单在既有弹窗内页内展开,不再二层 present。
    expect(
      observer.pushed.whereType<CupertinoSheetRoute<void>>(),
      hasLength(1),
    );

    await tester.tap(find.byKey(const Key('login-sheet-phone-back')));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.text('获取验证码'), findsNothing);
  });
}
