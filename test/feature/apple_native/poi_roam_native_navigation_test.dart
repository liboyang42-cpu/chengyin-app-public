import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/poi_pick_page.dart';
import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _ScanRoamApi extends RoamApi {
  _ScanRoamApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<CityNodeDetail> nodeDetail(int poiId) async => CityNodeDetail(
    poiId: poiId,
    name: '武康大楼店内据点',
    status: 1,
    lat: 31.2,
    lng: 121.4,
    validationMethod: 4,
  );
}

class _LoggedInAuthController extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 1, nickname: '测试玩家', avatar: '', role: 'player'),
    initialized: true,
  );
}

Widget _host(Widget page, {List<dynamic> overrides = const <dynamic>[]}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: page,
    ),
  );
}

void _expectTransparentNativeNavigation() {
  final CupertinoNavigationBar bar = testerWidget(
    find.byType(CupertinoNavigationBar).last,
  );
  expect(bar.backgroundColor, Colors.transparent);
  expect(bar.border, isNull);
}

T testerWidget<T extends Widget>(Finder finder) {
  final Element element = finder.evaluate().single;
  return element.widget as T;
}

void _mockScannerChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
    (MethodCall call) async => null,
  );
  messenger.setMockStreamHandler(
    const EventChannel(
      'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
    ),
    MockStreamHandler.inline(
      onListen: (Object? arguments, MockStreamHandlerEventSink? events) {},
      onCancel: (Object? arguments) {},
    ),
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.steenbakker.mobile_scanner/scanner/event'),
    MockStreamHandler.inline(
      onListen: (Object? arguments, MockStreamHandlerEventSink? events) {},
      onCancel: (Object? arguments) {},
    ),
  );
}

void main() {
  testWidgets('选择地点降级态在 200% 字号下使用透明 Cupertino 导航', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(const PoiPickPage()));
    await tester.pump();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('选择地点'), findsOneWidget);
    expect(find.text('地图暂时不可用'), findsOneWidget);
    _expectTransparentNativeNavigation();
    expect(tester.takeException(), isNull);
  });

  testWidgets('冷启直达选点页仍有可达的取消出口', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/publish/poi',
      routes: <RouteBase>[
        GoRoute(path: '/publish', builder: (_, _) => const Text('发布页')),
        GoRoute(path: '/publish/poi', builder: (_, _) => const PoiPickPage()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: ThemeData(platform: TargetPlatform.iOS),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    final Finder cancel = find.bySemanticsLabel('取消选点，返回发布');
    expect(cancel, findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('发布页'), findsOneWidget);
  });

  testWidgets('据点详情在 200% 字号下使用透明 Cupertino 根导航', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        const RoamPoiDetailPage(poiId: 7),
        overrides: <dynamic>[
          // N1 后游客进据点详情落在页内登录门,本测试要的是登录后的页面树。
          authControllerProvider.overrideWith(_LoggedInAuthController.new),
          roamApiProvider.overrideWithValue(_ScanRoamApi()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('武康大楼店内据点'), findsOneWidget);
    expect(find.text('开始互动'), findsOneWidget);
    _expectTransparentNativeNavigation();
    expect(tester.takeException(), isNull);
  });

  testWidgets('扫码子页使用透明 Cupertino 导航且关闭时释放相机页', (WidgetTester tester) async {
    _mockScannerChannels();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
        null,
      );
      messenger.setMockStreamHandler(
        const EventChannel(
          'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
        ),
        null,
      );
      messenger.setMockStreamHandler(
        const EventChannel('dev.steenbakker.mobile_scanner/scanner/event'),
        null,
      );
    });
    await tester.pumpWidget(
      _host(
        const RoamPoiDetailPage(poiId: 7),
        overrides: <dynamic>[
          roamApiProvider.overrideWithValue(_ScanRoamApi()),
          authControllerProvider.overrideWith(_LoggedInAuthController.new),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始互动'));
    // 扫码是整屏页(CupertinoPageRoute),进场有转场动画 —— 要 settle 才落位。
    await tester.pumpAndSettle();

    expect(find.text('扫店内张贴码'), findsOneWidget);
    // 全屏页把来路压成 offstage,finder 默认跳过 → 台上只剩扫码这一屏。
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    _expectTransparentNativeNavigation();
    // ★ 存在的意义所在:导航栏必须带**可点的系统返回钮**(对照表 #11)。
    //   showGeneralDialog 路由不渲染它,叠上 barrierDismissible:false
    //   就是「扫不到码出不去」的死角 —— 这条断言把死锁钉死在门外。
    //   (`_BackChevron` 是 Text.rich 画的码点字符,不是 Icon widget。)
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            w.textSpan?.toPlainText() ==
                String.fromCharCode(CupertinoIcons.back.codePoint),
      ),
      findsOneWidget,
    );

    Navigator.of(tester.element(find.text('扫店内张贴码'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('扫店内张贴码'), findsNothing);
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
