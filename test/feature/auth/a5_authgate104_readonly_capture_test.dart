// A5 iOS 27 外观首遍复核(a5-ios27-authgate-104)· 撞面只读面的渲染取证。
//
// #471 在途改 `phone_login_sheet.dart`、#472 在途改 `club_topic_detail_page.dart`
// ⇒ 本轮**只复核不改**(写单撞面条款)。本文件把两面的现状逐值锁住并出图,
// 供 critic 读数,也给 merge 后的下一轮留漂移警报。
//
// 先例:#413/#295 bench 口径 —— 默认只跑轻量断言(任何机器绿),出图:
//   BENCH_CAPTURE=1 flutter test test/feature/auth/a5_authgate104_readonly_capture_test.dart
// 产物 `out/bench_a5_104_*.png`(复核留档,非 golden 基准)。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_list_page.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';
import 'package:chengyin_app/feature/club/club_login_gate.dart';

import '../../golden/golden_theme.dart';

bool get _capture => Platform.environment['BENCH_CAPTURE'] == '1';
const Key _benchKey = Key('bench-a5-104-readonly');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

Future<void> _save(WidgetTester tester, String name) async {
  if (!_capture) return;
  final RenderRepaintBoundary render = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_benchKey));
  final ui.Image image = await render.toImage(pixelRatio: 2);
  addTearDown(image.dispose);
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  Directory('out').createSync(recursive: true);
  File(
    'out/bench_a5_104_$name.png',
  ).writeAsBytesSync(bytes.buffer.asUint8List());
}

Widget _wrap(WidgetTester tester, Widget home) {
  setGoldenViewport(tester, const Size(390, 844));
  return RepaintBoundary(
    key: _benchKey,
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

class _ManualAuthApi extends Fake implements AuthApi {
  int calls = 0;
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> sendSmsCode(String phone) {
    calls += 1;
    pending = Completer<Map<String, dynamic>>();
    return pending!.future;
  }
}

void main() {
  group('登录弹层(#474 面·#471 在途 → 只读锁)', () {
    Future<void> openSheet(WidgetTester tester, _ManualAuthApi auth) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[authApiProvider.overrideWithValue(auth)].cast(),
          // 宿主照 test/golden/pages_account_golden_test.dart 的弹层台:
          // Scaffold + FilledButton,sheet 里的 Text 才吃得到 MaterialApp 主题
          // (裸 Builder 宿主会让 DefaultTextStyle 依赖件渲染成调试态豆腐块)。
          child: _wrap(
            tester,
            Scaffold(
              body: Builder(
                builder: (BuildContext context) => Center(
                  child: FilledButton(
                    onPressed: () => showPhoneLoginSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        '13800138000',
      );
    }

    testWidgets('常态:文字动作 textPrimary(真源无底文字动作形态的现状锁)', (
      WidgetTester tester,
    ) async {
      await openSheet(tester, _ManualAuthApi());
      final Text label = tester.widget<Text>(find.text('获取验证码'));
      expect(label.style!.color, CyTokens.textPrimary);
      expect(
        tester.getSize(find.text('获取验证码')),
        isNotNull,
      ); // 按钮 minimumSize 44 由 #474 落码,这里只锁颜色现状
      await _save(tester, 'sheet_idle');
    });

    testWidgets('在途:「发送中…」textDisabled(#474 三态现状)', (
      WidgetTester tester,
    ) async {
      final _ManualAuthApi auth = _ManualAuthApi();
      await openSheet(tester, auth);
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      final Text label = tester.widget<Text>(find.text('发送中…'));
      expect(label.style!.color, CyTokens.textDisabled);
      await _save(tester, 'sheet_sending');
      auth.pending!.complete(<String, dynamic>{'code': 200});
      await tester.pumpAndSettle();
    });

    testWidgets('成后「重新发送」回 textPrimary(#474 三态现状)', (
      WidgetTester tester,
    ) async {
      final _ManualAuthApi auth = _ManualAuthApi();
      await openSheet(tester, auth);
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      auth.pending!.complete(<String, dynamic>{'code': 200});
      await tester.pumpAndSettle();
      final Text label = tester.widget<Text>(find.text('重新发送'));
      expect(label.style!.color, CyTokens.textPrimary);
      await _save(tester, 'sheet_sent');
    });
  });

  testWidgets('club 登录门(#473 面·#472 在途 → 只读锁):StatusView 共用件直出', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(
          tester,
          CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('活动详情')),
            child: SafeArea(
              child: ClubLoginGate(message: '登录后查看活动详情', onSignedIn: () {}),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('登录后查看活动详情'), findsOneWidget);
    expect(find.text('这一步需要登录，登录完会自动回到这一页。'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    await _save(tester, 'club_gate');
  });

  testWidgets('官方活动入口带(#475 面):导航栏右缘 44pt 整带文字钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          activityListProvider.overrideWith((ref) async => const <Activity>[]),
          // 页面构造只读 provider;API 不被调用,给个能构造的实例即可。
          activityApiProvider.overrideWithValue(
            ActivityApi(DioClient(TokenStore(const FlutterSecureStorage()))),
          ),
        ].cast(),
        child: _wrap(tester, const ActivityListPage()),
      ),
    );
    await _settle(tester);
    final entry = find.byKey(const Key('activities-official-entry'));
    expect(entry, findsOneWidget);
    final Rect barRect = tester.getRect(find.byType(CupertinoNavigationBar));
    final Rect entryRect = tester.getRect(entry);
    expect(entryRect.top, greaterThanOrEqualTo(barRect.top));
    expect(entryRect.bottom, lessThanOrEqualTo(barRect.bottom));
    expect(
      tester.widget<CupertinoButton>(entry).minimumSize,
      const Size.square(CyTokens.btnH),
    );
    // A5-104 新锁:文字盒不许横向吃满导航栏(Center 无 widthFactor 会把入口
    // 推到屏幕正中、命中区盖全栏)—— 入口必须贴右缘。
    expect(
      entryRect.center.dx,
      greaterThan(barRect.center.dx + 60),
      reason: '官方活动入口不在右半栏,横向又被撑满了',
    );
    expect(entryRect.right, closeTo(barRect.right, 16));
    await _save(tester, 'official_entry');
  });
}
