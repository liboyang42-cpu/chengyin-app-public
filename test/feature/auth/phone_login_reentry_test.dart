import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_gate.dart';
import 'package:chengyin_app/feature/auth/phone_login_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// F1(#213 回归)复现 + 钉死:守卫/登录门(`requireLogin`)进来的用户
/// 点登录弹窗里的「手机号登录」,手机号表单必须真的上屏。
///
/// 旧实现是 sheet 叠 sheet:外层登录弹窗自 `e6e9cd4b`(#213)起走 B1 原生承载,
/// 内层再 present 一次必被原生 `already_presented` 静默吞掉
/// (`cy_native_sheet.dart` 一次只一个 sheet),按钮零反馈。
/// 本文件用「有状态的假原生承载器」模拟真机 present 语义 —— 第一个 sheet
/// 没关之前第二次 present 抛 `already_presented`,死按钮在测试里可复现。
const MethodChannel _channel = MethodChannel(
  'native_liquid_glass/native_flutter_sheet',
);

final List<String> _calls = <String>[];

/// 模拟 iOS 15+ 原生承载:一次只允许一个 sheet 处于已呈现状态。
/// 「二次 present 被吞」是机械事实,不是这里造的策略 —— Swift 侧
/// `already_presented` 就是这么回的。
void _mockNativePresenter() {
  _calls.clear();
  var busy = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (MethodCall call) async {
        _calls.add(call.method);
        switch (call.method) {
          case 'present':
            if (busy) {
              throw PlatformException(code: 'already_presented');
            }
            busy = true;
            return null;
          case 'dismiss':
            busy = false;
            // 真机在关闭动画结束回调里回 'dismissed';测试里同步补发。
            await TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .handlePlatformMessage(
                  _channel.name,
                  _channel.codec.encodeMethodCall(
                    const MethodCall('dismissed'),
                  ),
                  (ByteData? _) {},
                );
            return null;
          case 'reveal':
          case 'restored':
            return null;
        }
        return null;
      });
  addTearDown(_clearMockHandler);
}

class _PhoneAuth extends AuthController {
  _PhoneAuth({this.succeeds = false});

  final bool succeeds;
  int attempts = 0;
  String? lastPhone;

  @override
  AuthState build() => const AuthState(initialized: true);

  @override
  Future<String?> loginWithPhone(String phone, String code) async {
    attempts += 1;
    lastPhone = phone;
    if (succeeds) {
      state = AuthState(
        initialized: true,
        user: User(id: 1, nickname: '用户', avatar: '', role: 'player'),
      );
    }
    return succeeds ? null : '手机号或验证码不正确';
  }
}

/// 宿主按钮直接 `await requireLogin(...)`,登完把收敛结果写上屏 ——
/// 验证调用方的 await 语义没被修坏(登录成功要继续原动作)。
class _GateHost extends ConsumerStatefulWidget {
  const _GateHost({required this.auth});

  final AuthController Function() auth;

  @override
  ConsumerState<_GateHost> createState() => _GateHostState();
}

class _GateHostState extends ConsumerState<_GateHost> {
  String _result = 'idle';

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [authControllerProvider.overrideWith(widget.auth)],
      child: MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          brightness: Brightness.dark,
        ),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, _) =>
                      TextButton(
                        onPressed: () async {
                          final bool ok = await requireLogin(context, ref);
                          if (context.mounted) {
                            setState(() => _result = ok ? '继续原动作' : '放弃');
                          }
                        },
                        child: const Text('open'),
                      ),
                ),
                Text(_result),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpGate(
  WidgetTester tester,
  AuthController Function() auth,
) async {
  await tester.pumpWidget(_GateHost(auth: auth));
}

Future<void> _openLoginSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // 外层登录弹窗已由承载打开,标题在屏。
  expect(find.text('登录城瘾'), findsOneWidget);
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(CupertinoTextField).first, '13800138000');
  await tester.enterText(find.byType(CupertinoTextField).last, '123456');
  await tester.tap(find.text('登录'));
  await tester.pumpAndSettle();
}

void _clearMockHandler() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// 每条用例收尾必须清零平台覆写(foundation 变量守卫在 addTearDown 之前跑)。
void _finish(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('iOS 15+ 原生承载下点「手机号登录」:表单必须上屏,且不开二次 present', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _mockNativePresenter();
    await _pumpGate(tester, _PhoneAuth.new);
    await _openLoginSheet(tester);

    final int presentBefore = _calls.where((String m) => m == 'present').length;
    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();

    // 死按钮回归点:表单必须真的上屏。
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    // 且不得再走一次原生 present(sheet 不叠 sheet)。
    expect(_calls.where((String m) => m == 'present').length, presentBefore);
    _finish(tester);
  });

  testWidgets('手机号表单可退回登录方式列表,外层弹窗不消失', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _mockNativePresenter();
    await _pumpGate(tester, _PhoneAuth.new);
    await _openLoginSheet(tester);

    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();
    expect(find.text('获取验证码'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-sheet-phone-back')));
    await tester.pumpAndSettle();

    // 收起表单回到方式列表;登录弹窗仍在,微信/Apple 入口可点。
    expect(find.text('获取验证码'), findsNothing);
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.text('微信登录'), findsOneWidget);
    // 展开/收起全程零二次 present、零 dismiss。
    expect(_calls.where((String m) => m == 'present').length, 1);
    expect(_calls.where((String m) => m == 'dismiss').length, 0);
    _finish(tester);
  });

  testWidgets('原生承载下手机号登录成功:弹窗关闭且 requireLogin 收敛为已登录', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _mockNativePresenter();
    final _PhoneAuth auth = _PhoneAuth(succeeds: true);
    await _pumpGate(tester, () => auth);
    await _openLoginSheet(tester);

    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();
    await _fillAndSubmit(tester);

    expect(auth.attempts, 1);
    expect(auth.lastPhone, '13800138000');
    // 弹窗整体关闭,露出原页;调用方 await 收敛为已登录。
    expect(find.text('登录城瘾'), findsNothing);
    expect(find.text('获取验证码'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('继续原动作'), findsOneWidget);
    _finish(tester);
  });

  testWidgets('登录失败留在表单内就地报错,不关弹窗', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _mockNativePresenter();
    final _PhoneAuth auth = _PhoneAuth();
    await _pumpGate(tester, () => auth);
    await _openLoginSheet(tester);

    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();
    await _fillAndSubmit(tester);

    expect(auth.attempts, 1);
    expect(find.text('手机号或验证码不正确'), findsOneWidget);
    expect(find.text('登录城瘾'), findsOneWidget); // 弹窗还开着
    _finish(tester);
  });

  testWidgets('iOS 13–14 回退路径(unsupported)行为一致', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          if (call.method == 'present') {
            throw PlatformException(code: 'unsupported');
          }
          return null;
        });
    addTearDown(_clearMockHandler);
    await _pumpGate(tester, _PhoneAuth.new);
    await _openLoginSheet(tester);

    await tester.tap(find.text('手机号登录'));
    await tester.pumpAndSettle();
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    _finish(tester);
  });

  testWidgets('/login 整页的手机号登录弹层合同不变(无外层 sheet 时仍可独立打开)', (
    WidgetTester tester,
  ) async {
    // 报告称 /login 页面同按钮正常:整页没有外层 sheet,showPhoneLoginSheet
    // 独立打开的路径不许被本修复改坏。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    _mockNativePresenter();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showPhoneLoginSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('手机号登录'), findsOneWidget); // 表单标题
    expect(find.text('获取验证码'), findsOneWidget);
    final List<CupertinoTextField> fields = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .toList();
    expect(fields[0].keyboardType, TextInputType.phone);
    expect(fields[0].maxLength, 11);
    expect(fields[1].maxLength, 6);
    _finish(tester);
  });
}
