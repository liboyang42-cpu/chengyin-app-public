// A5 iOS 27 外观首遍复核(a5-ios27-authgate-104)· 注销页「获取验证码」三态。
//
// 覆盖 #474 落点之一 `lib/feature/account/deregister_page.dart`:
//   真源 components/cy/scene-settings-deregister/index.wxml:14
//   `.deregister-code-send` —— 行尾**下划线文字动作**(font-label 12pt、
//   text-title 色、左内衬 space-3=12pt、min-height=btnH=44pt),三态文案
//   「获取验证码/发送中…/重新发送」;在途置灰用换色(App 纪律,不降透明度)。
//   复核前 App 侧是灰胶囊 CyNativeButton + 静态「获取验证码」,在途态不可见。
//
// 先例:#413/#295 bench 口径 —— 默认只跑轻量断言(任何机器绿),出图:
//   BENCH_CAPTURE=1 flutter test test/feature/account/deregister_sms_a5_bench_test.dart
// 产物 `out/bench_a5_104_deregister_*.png`(复核留档,非 golden 基准)。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/auth_api.dart';
import 'package:chengyin_app/data/models/deregistration.dart';
import 'package:chengyin_app/feature/account/deregister_page.dart';

import '../../golden/golden_theme.dart';
import '../../support/fixed_auth.dart';

bool get _capture => Platform.environment['BENCH_CAPTURE'] == '1';
const Key _benchKey = Key('bench-a5-104-deregister');

class _EligibleAccountApi extends Fake implements AccountApi {
  @override
  Future<DeregistrationStatus> deregisterStatus() async =>
      const DeregistrationStatus(status: 'NORMAL', blockers: <String>[]);

  @override
  Future<DeregistrationStatus> deregisterPrecheck() async =>
      const DeregistrationStatus(status: 'ELIGIBLE', blockers: <String>[]);

  @override
  Future<void> agreeCancellationNotice(String requestId) async {}
}

/// 手动完成的 AuthApi:在途窗口内的连点都被锁住。
class _ManualAuthApi extends Fake implements AuthApi {
  int calls = 0;
  final List<Completer<Map<String, dynamic>>> _pending = [];

  Completer<Map<String, dynamic>> get latest => _pending.last;

  @override
  Future<Map<String, dynamic>> sendSmsCode(String phone) {
    calls += 1;
    final Completer<Map<String, dynamic>> c = Completer<Map<String, dynamic>>();
    _pending.add(c);
    return c.future;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

Future<void> _toVerifyStep(WidgetTester tester, _ManualAuthApi auth) async {
  setGoldenViewport(tester, const Size(390, 844));
  final ThemeData theme = goldenTheme();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _benchKey,
      child: ProviderScope(
        overrides: <dynamic>[
          accountApiProvider.overrideWithValue(_EligibleAccountApi()),
          authApiProvider.overrideWithValue(auth),
          // PR 给注销页加了页内登录门(B1 P1-2)——不挂登录态会先撞门。
          signedInAuthOverride(),
        ].cast(),
        child: MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: const DeregisterPage(),
        ),
      ),
    ),
  );
  await _settle(tester);
  // 须知 → 勾选 → 下一步,进短信验证步。
  await tester.tap(find.byType(CupertinoCheckbox));
  await _settle(tester);
  await tester.tap(find.text('下一步'));
  await _settle(tester);
  await tester.enterText(
    find.byKey(const Key('deregister-phone-field')),
    '13800138000',
  );
  await _settle(tester);
}

/// 按钮里的 Text(三态文案的载体)。
Text _sendLabel(WidgetTester tester) => tester.widget<Text>(
  find.descendant(
    of: find.byKey(const Key('deregister-send-code')),
    matching: find.byType(Text),
  ),
);

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
    'out/bench_a5_104_deregister_$name.png',
  ).writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  testWidgets('真源 `.deregister-code-send` 逐值:12pt 下划线文字动作 + 44pt 触控高', (
    WidgetTester tester,
  ) async {
    await _toVerifyStep(tester, _ManualAuthApi());

    final CupertinoButton button = tester.widget(
      find.byKey(const Key('deregister-send-code')),
    );
    expect(button.minimumSize, const Size(44, CyTokens.btnH));
    expect(button.padding, const EdgeInsets.only(left: CyTokens.space3));

    final Text label = _sendLabel(tester);
    expect(label.data, '获取验证码');
    final TextStyle style = label.style!;
    expect(style.fontSize, CyTokens.typeLabel); // 真源 font-label = 24rpx
    expect(style.decoration, TextDecoration.underline);
    expect(style.color, CyTokens.textPrimary); // 真源 text-title
    expect(
      tester.getSize(find.byKey(const Key('deregister-send-code'))).height,
      greaterThanOrEqualTo(44),
    );
    await _save(tester, 'idle');
  });

  testWidgets('在途:「发送中…」换 textDisabled 不降透明度;五连点只发 1 条', (
    WidgetTester tester,
  ) async {
    final _ManualAuthApi auth = _ManualAuthApi();
    await _toVerifyStep(tester, auth);

    final Finder button = find.byKey(const Key('deregister-send-code'));
    for (int i = 0; i < 5; i++) {
      await tester.tap(button);
      await tester.pump();
    }
    expect(auth.calls, 1, reason: '在途锁(#474)不许被外观复核改动放松');

    final Text label = _sendLabel(tester);
    expect(label.data, '发送中…');
    expect(label.style!.color, CyTokens.textDisabled); // 换色纪律
    expect(label.style!.decoration, TextDecoration.underline); // 真源只降亮不撤线
    expect(
      tester.widget<CupertinoButton>(button).onPressed,
      isNull,
      reason: '在途期间不可再点',
    );
    await _save(tester, 'sending');

    auth.latest.complete(<String, dynamic>{'code': 200, 'msg': 'ok'});
    // notice 2400ms 自动隐藏的定时器必须跨掉,否则 teardown 报 pending timer。
    await tester.pumpAndSettle();
  });

  testWidgets('成功后「重新发送」回 textPrimary,可再发(真源无冷却)', (WidgetTester tester) async {
    final _ManualAuthApi auth = _ManualAuthApi();
    await _toVerifyStep(tester, auth);

    final Finder button = find.byKey(const Key('deregister-send-code'));
    await tester.tap(button);
    await tester.pump();
    auth.latest.complete(<String, dynamic>{'code': 200, 'msg': 'ok'});
    // 跨掉 notice 定时器后再断言。
    await tester.pumpAndSettle();

    Text label = _sendLabel(tester);
    expect(label.data, '重新发送');
    expect(label.style!.color, CyTokens.textPrimary);
    await _save(tester, 'sent');

    await tester.tap(button);
    await tester.pump();
    expect(auth.calls, 2);
    auth.latest.completeError(Exception('短信服务未配置'));
    await tester.pumpAndSettle();

    // 失败回「获取验证码」(smsSent 不翻 true,对齐真源失败口径)。
    label = _sendLabel(tester);
    expect(label.data, '获取验证码');
  });
}
