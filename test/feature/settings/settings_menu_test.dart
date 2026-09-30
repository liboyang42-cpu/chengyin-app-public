// 设置页菜单结构守卫:十行菜单 + 退出账号,标题与小程序 `pages/shezhi/shezhi`
// 逐行对齐。哪一行被删/改错,这里先红 —— 不需要等整页 golden 去盯。

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import 'package:chengyin_app/core/map/map_privacy_store.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/models/consent_record.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/settings/settings_page.dart';
import 'package:chengyin_app/feature/settings/sound_haptics_settings.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _MemorySoundHapticsStore implements SoundHapticsSettingsStore {
  _MemorySoundHapticsStore({this.readError, this.writeError})
    : value = SoundHapticsSettings.defaults;

  SoundHapticsSettings value;
  final Object? readError;
  Object? writeError;
  int writes = 0;

  @override
  Future<SoundHapticsSettings> read() async {
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> write(SoundHapticsSettings next) async {
    writes += 1;
    if (writeError != null) throw writeError!;
    value = next;
  }
}

DioClient _dummyClient() => DioClient(TokenStore(const FlutterSecureStorage()));

class _PrivacyAccountApi extends AccountApi {
  _PrivacyAccountApi({required this.events, this.gate, this.error})
    : super(_dummyClient());

  final List<String> events;
  final Completer<void>? gate;
  final Object? error;
  int calls = 0;

  @override
  Future<ConsentRecord> revokeRoamLocationConsent({
    required String requestId,
  }) async {
    calls += 1;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    events.add('server');
    return const ConsentRecord(
      docType: 'privacy_policy',
      scene: 'roam_location',
      eventType: 'REVOKE',
    );
  }
}

class _PrivacyMapStore extends MapPrivacyStore {
  _PrivacyMapStore({required this.events})
    : super(const FlutterSecureStorage());

  final List<String> events;
  bool value = true;

  @override
  Future<bool> hasAgreed() async => value;

  @override
  Future<void> setAgreed(bool agreed) async {
    events.add('local:$agreed');
    value = agreed;
  }
}

class _PrivacyRoamController extends RoamLiveController {
  _PrivacyRoamController(this.events);

  final List<String> events;
  int stops = 0;

  @override
  RoamLiveState build() => const RoamLiveState();

  @override
  Future<void> stopLocationTracking() async {
    stops += 1;
    events.add('stop');
  }
}

Widget _app({
  _MemorySoundHapticsStore? soundStore,
  _PrivacyAccountApi? privacyApi,
  _PrivacyMapStore? privacyStore,
  _PrivacyRoamController? roamController,
  bool? liquidGlassSupported,
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
    overrides: <dynamic>[
      authControllerProvider.overrideWith(
        () => _FixedAuth(
          AuthState(
            user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
            initialized: true,
          ),
        ),
      ),
      if (soundStore != null)
        soundHapticsSettingsStoreProvider.overrideWithValue(soundStore),
      if (privacyApi != null) accountApiProvider.overrideWithValue(privacyApi),
      if (privacyStore != null)
        mapPrivacyStoreProvider.overrideWithValue(privacyStore),
      if (roamController != null)
        roamLiveControllerProvider.overrideWith(() => roamController),
    ].cast(),
    child: MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: SettingsPage(liquidGlassSupported: liquidGlassSupported),
    ),
  );
}

({Widget app, GoRouter router}) _routedApp({
  String role = 'player',
  bool loggedIn = true,
}) {
  final GoRouter router = GoRouter(
    initialLocation: '/settings',
    routes: <RouteBase>[
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/profile/edit',
        builder: (_, _) => const Scaffold(
          key: Key('route-profile-edit'),
          body: Text('编辑个人资料'),
        ),
      ),
      GoRoute(
        path: '/merchant/apply',
        builder: (_, _) => const Scaffold(
          key: Key('route-merchant-apply'),
          body: Text('商家入驻'),
        ),
      ),
      GoRoute(
        path: '/merchant/decor',
        builder: (_, _) => const Scaffold(
          key: Key('route-merchant-decor'),
          body: Text('商家装修'),
        ),
      ),
      GoRoute(
        path: '/club/apply',
        builder: (_, _) =>
            const Scaffold(key: Key('route-club-apply'), body: Text('主理人申请')),
      ),
      GoRoute(
        path: '/clubs',
        builder: (_, _) =>
            const Scaffold(key: Key('route-clubs'), body: Text('俱乐部')),
      ),
      GoRoute(
        path: '/deregister',
        builder: (_, _) =>
            const Scaffold(key: Key('route-deregister'), body: Text('账号注销')),
      ),
    ],
  );
  return (
    router: router,
    app: ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            loggedIn
                ? AuthState(
                    user: User(id: 1, nickname: '阿兰', avatar: '', role: role),
                    initialized: true,
                  )
                : const AuthState(initialized: true),
          ),
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  testWidgets('商家的个人资料直达装修页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final routed = _routedApp(role: 'merchant');
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人资料'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-merchant-decor')), findsOneWidget);
    expect(find.byKey(const Key('route-profile-edit')), findsNothing);
  });

  testWidgets('普通玩家申请成为主理人直达申请页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final routed = _routedApp();
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('成为俱乐部主理人'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-club-apply')), findsOneWidget);
    expect(find.byKey(const Key('route-clubs')), findsNothing);
  });

  testWidgets('★ 游客点「账号注销」/「成为商家」先弹登录门,不静默弹回首页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final routed = _routedApp(loggedIn: false);
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    // 这两行都在 `_loginRequiredPrefixes` 下(/deregister、/merchant):
    // 游客点下去本该"整页需登录"—— 沉默弹回首页 = 用户以为按钮坏了。
    for (final String row in <String>['账号注销', '成为商家']) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('route-deregister')), findsNothing);
      expect(find.byKey(const Key('route-merchant-apply')), findsNothing);
      expect(find.text('登录城瘾'), findsOneWidget, reason: '点「$row」应先弹登录门');
      expect(find.text('设置'), findsOneWidget, reason: '人还该留在设置页');

      Navigator.of(tester.element(find.text('登录城瘾'))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('登录后点「账号注销」仍直达注销页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final routed = _routedApp();
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('账号注销'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-deregister')), findsOneWidget);
    expect(find.text('登录城瘾'), findsNothing);
  });

  testWidgets('设置的个人资料进入现有编辑页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final routed = _routedApp();
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人资料'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-profile-edit')), findsOneWidget);
    routed.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('设置的成为商家进入现有入驻页', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final routed = _routedApp();
    addTearDown(routed.router.dispose);
    await tester.pumpWidget(routed.app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('成为商家'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('route-merchant-apply')), findsOneWidget);
    expect(find.text('商家入驻正在接入中'), findsNothing);
    routed.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('设置页菜单十行 + 退出账号与小程序对齐', (WidgetTester tester) async {
    // ⚠️ 视口要够高把**整列**装下 —— 这些断言用 find.text 直接找,
    // ListView 视口外的行不会被构建。2026-08-19 加「收货地址」后
    // 「退出账号」被挤出 1000pt,测试报 findsNothing,看着像功能被删了,
    // 其实只是没进视口。判"某行在不在"时,视口不够 = 假阴性。
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 顺序 = 小程序 shezhi.wxml 的 cy-cell 顺序。
    const List<String> titles = <String>[
      '个人资料',
      '成为俱乐部主理人',
      '成为商家',
      '城瘾玩法',
      '我的喜欢',
      '声音与触感',
      '隐私与定位',
      '用户服务协议',
      '账号注销',
      '关于',
    ];
    final List<double> ys = <double>[];
    for (final String title in titles) {
      // findsWidgets 而非 findsOneWidget:「声音与触感」的副标题与标题同字,
      // 小程序 shezhi 同样如此。删除/改名仍会被 findsNothing 抓到。
      expect(
        find.text(title),
        findsWidgets,
        reason: '设置页缺少「$title」(小程序 shezhi 有此行)',
      );
      ys.add(tester.getTopLeft(find.text(title).first).dy);
    }
    // 行序自上而下,不允许与小程序顺序错位。
    for (int i = 1; i < ys.length; i++) {
      expect(
        ys[i] > ys[i - 1],
        isTrue,
        reason: '「${titles[i]}」排到了「${titles[i - 1]}」上面,与 shezhi 顺序不符',
      );
    }
    expect(find.text('退出账号'), findsOneWidget);
  });

  testWidgets('菜单标题与小程序逐行逐字一致', (WidgetTester tester) async {
    // ⚠️ 视口要够高把**整列**装下 —— 这些断言用 find.text 直接找,
    // ListView 视口外的行不会被构建。2026-08-19 加「收货地址」后
    // 「退出账号」被挤出 1000pt,测试报 findsNothing,看着像功能被删了,
    // 其实只是没进视口。判"某行在不在"时,视口不够 = 假阴性。
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 副标题文案同样来自 shezhi.wxml(description 属性),逐行核对。
    const Map<String, String> expectSub = <String, String>{
      '个人资料': '昵称、头像与介绍',
      '成为俱乐部主理人': '主理人身份 · 之后可创建俱乐部带团',
      '成为商家': '提供场地 · 参与招募 · 发布优惠',
      '城瘾玩法': '城市探索说明',
      '我的喜欢': '已收藏的主题',
      '声音与触感': '声音与触感',
      '隐私与定位': '管理漫游定位同意',
      '用户服务协议': '查看服务条款',
      '账号注销': '申请或撤销注销，注销后账号不可恢复',
      '关于': '版本、协议、联系与我的二维码',
    };
    expectSub.forEach((String title, String sub) {
      expect(
        find.text(sub),
        findsWidgets,
        reason: '「$title」的副标题应是「$sub」(与 shezhi description 对齐)',
      );
    });
  });

  testWidgets('素材署名两条许可条件离线可见,点「复制来源地址」进剪贴板', (WidgetTester tester) async {
    // 署名是 game-icons.net 的 CC BY 3.0 许可条件 —— 它没有网络依赖,
    // 也不该藏进二级页(真源 shezhi.wxml 独立页退役后放设置页底部)。
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add('${(call.arguments as Map<dynamic, dynamic>)['text']}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('素材署名'), findsOneWidget);
    expect(
      find.text('game-icons.net 游戏图标 · Creative Commons BY 3.0（要求署名）'),
      findsOneWidget,
    );
    expect(
      find.text('作者：Delapouite、Lorc、Skoll、Sbed、Quoting、Lord Berandas'),
      findsOneWidget,
    );
    expect(find.text('像素城市场景 · Luis Zuno（ansimuz）· CC0 1.0'), findsOneWidget);

    final Finder link = find.byKey(
      const Key('attribution-copy-https://game-icons.net/'),
    );
    await tester.scrollUntilVisible(
      link,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(copied, <String>['https://game-icons.net/']);
    expect(find.text('来源地址已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('iOS 26 声音与触感用真实原生 Switch 并保留六项顺序', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final _MemorySoundHapticsStore store = _MemorySoundHapticsStore();
    await tester.pumpWidget(
      _app(soundStore: store, liquidGlassSupported: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();

    expect(find.byType(AppleLiquidSwitch), findsNWidgets(6));
    expect(find.byType(CupertinoSwitch), findsNothing);
    const List<String> keys = <String>[
      'sound',
      'haptics',
      'airplane',
      'ocean',
      'raindrop',
      'forest',
    ];
    final List<double> ys = <double>[];
    for (final String key in keys) {
      final Finder row = find.byKey(Key('sound-haptics-row-$key'));
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      ys.add(tester.getTopLeft(row).dy);
    }
    for (int i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }

    final Semantics sound = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const Key('sound-haptics-row-sound')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(sound.properties.label, '声音');
    expect(sound.properties.toggled, isTrue);
  });

  testWidgets('旧系统用同语义 CupertinoSwitch，200% 字号仍可滚动访问六项', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(
      _app(
        soundStore: _MemorySoundHapticsStore(),
        liquidGlassSupported: false,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pumpAndSettle();

    expect(find.byType(AppleLiquidSwitch), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNWidgets(6));
    await tester.scrollUntilVisible(
      find.byKey(const Key('sound-haptics-row-forest')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('森林'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关先持久化再更新，关闭重开仍保留', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final _MemorySoundHapticsStore store = _MemorySoundHapticsStore();
    await tester.pumpWidget(
      _app(soundStore: store, liquidGlassSupported: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();

    tester
        .widget<AppleLiquidSwitch>(find.byType(AppleLiquidSwitch).first)
        .onChanged(false);
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(store.value.sound, isFalse);
    expect(
      tester
          .widget<AppleLiquidSwitch>(find.byType(AppleLiquidSwitch).first)
          .value,
      isFalse,
    );

    Navigator.of(tester.element(find.text('环境音'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppleLiquidSwitch>(find.byType(AppleLiquidSwitch).first)
          .value,
      isFalse,
    );
  });

  testWidgets('存储失败保留原值且不伪造成功', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    final _MemorySoundHapticsStore store = _MemorySoundHapticsStore(
      writeError: Exception('钥匙串不可用'),
    );
    await tester.pumpWidget(
      _app(soundStore: store, liquidGlassSupported: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();

    tester
        .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first)
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(store.value.sound, isTrue);
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first).value,
      isTrue,
    );
    expect(find.text('设置没保存，请重试'), findsOneWidget);
  });

  testWidgets('读取失败不拿默认值冒充当前设置，可重试', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    await tester.pumpWidget(
      _app(
        soundStore: _MemorySoundHapticsStore(readError: FormatException('坏数据')),
        liquidGlassSupported: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('声音与触感').first);
    await tester.pumpAndSettle();

    expect(find.text('声音与触感没读出来'), findsOneWidget);
    expect(find.byType(AppleLiquidSwitch), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNothing);
  });

  testWidgets('撤回按服务端回读→停止定位→本地 false 顺序完成并刷新 provider', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final List<String> events = <String>[];
    final Completer<void> gate = Completer<void>();
    final _PrivacyAccountApi api = _PrivacyAccountApi(
      events: events,
      gate: gate,
    );
    final _PrivacyMapStore store = _PrivacyMapStore(events: events);
    final _PrivacyRoamController roam = _PrivacyRoamController(events);
    await tester.pumpWidget(
      _app(privacyApi: api, privacyStore: store, roamController: roam),
    );
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(await container.read(mapPrivacyAgreementProvider.future), isTrue);

    await tester.tap(find.text('隐私与定位').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-revoke-button')));
    await tester.pump();

    expect(api.calls, 1);
    expect(events, isEmpty, reason: '服务端尚未回读前不得停止定位或改本地');
    final CyNativeButton busyButton = tester.widget<CyNativeButton>(
      find.byKey(const Key('privacy-revoke-button')),
    );
    expect(busyButton.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('privacy-revoke-button')),
      warnIfMissed: false,
    );
    expect(api.calls, 1, reason: '请求在途必须拦重复提交');
    await Navigator.of(tester.element(find.text('漫游定位'))).maybePop();
    await tester.pump();
    expect(find.text('撤回中…'), findsOneWidget, reason: '请求在途不能关闭 Sheet，让结果消失');
    expect(find.text('撤回中…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(events, <String>['server', 'stop', 'local:false']);
    expect(roam.stops, 1);
    expect(store.value, isFalse);
    expect(await container.read(mapPrivacyAgreementProvider.future), isFalse);
    expect(find.text('已撤回漫游定位同意'), findsOneWidget);
    expect(find.text('隐私与定位'), findsWidgets, reason: '成功后仍停留在同一 Sheet');
  });

  testWidgets('撤回网络失败不停止定位、不改本地、不关闭 Sheet，可重试', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final List<String> events = <String>[];
    final _PrivacyAccountApi api = _PrivacyAccountApi(
      events: events,
      error: Exception('网络不可用'),
    );
    final _PrivacyMapStore store = _PrivacyMapStore(events: events);
    final _PrivacyRoamController roam = _PrivacyRoamController(events);
    await tester.pumpWidget(
      _app(privacyApi: api, privacyStore: store, roamController: roam),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与定位').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('privacy-revoke-button')));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
    expect(roam.stops, 0);
    expect(store.value, isTrue);
    expect(find.text('撤回记录失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('隐私与定位'), findsWidgets);
    expect(
      tester
          .widget<CyNativeButton>(
            find.byKey(const Key('privacy-revoke-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('隐私 Sheet 保留文案与入口，按钮 44pt、VoiceOver、大字和 Reduce Motion', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    final List<String> events = <String>[];
    await tester.pumpWidget(
      _app(
        privacyApi: _PrivacyAccountApi(events: events),
        privacyStore: _PrivacyMapStore(events: events),
        roamController: _PrivacyRoamController(events),
        textScale: 2,
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与定位').first);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pumpAndSettle();

    expect(find.text('查看《用户隐私保护指引》'), findsOneWidget);
    final Finder button = find.byKey(const Key('privacy-revoke-button'));
    await tester.scrollUntilVisible(
      button,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(find.text('撤回漫游定位同意'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
