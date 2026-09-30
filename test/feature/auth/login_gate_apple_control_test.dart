import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/auth/login_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

Widget _host({
  required TargetPlatform platform,
  required Future<bool> Function() availability,
  AuthController Function()? authOverride,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      if (authOverride != null)
        authControllerProvider.overrideWith(authOverride),
    ],
    child: MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                showLoginSheet(context, appleSignInAvailability: availability),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

class _AppleLoginAuth extends AuthController {
  _AppleLoginAuth({this.error, this.succeeds = false});

  final String? error;
  final bool succeeds;
  int attempts = 0;

  @override
  AuthState build() => const AuthState(initialized: true);

  @override
  Future<String?> loginWithApple() async {
    attempts += 1;
    state = AuthState(
      initialized: true,
      user: succeeds
          ? User(id: 1, nickname: '用户', avatar: '', role: 'player')
          : null,
    );
    return error;
  }
}

void main() {
  testWidgets('iOS 登录 Sheet 保持入口顺序并复用包的 Apple 标准按钮', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(platform: TargetPlatform.iOS, availability: () async => true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInWithAppleButton), findsOneWidget);
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
  });

  testWidgets('非 iOS 不显示 Apple 入口且不调用可用性探测', (WidgetTester tester) async {
    int checks = 0;
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.android,
        availability: () async {
          checks += 1;
          return true;
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInWithAppleButton), findsNothing);
    expect(find.text('通过 Apple 登录'), findsNothing);
    expect(checks, 0);
  });

  testWidgets('旧 iOS 不支持时不暴露无效 Apple 入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(platform: TargetPlatform.iOS, availability: () async => false),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInWithAppleButton), findsNothing);
    expect(find.text('通过 Apple 登录'), findsNothing);
  });

  testWidgets('Apple 控件命中区不小于 44pt、有 VoiceOver 语义并支持禁用', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: AppleSignInControl(
              loading: false,
              availability: () async => true,
              onPressed: () async {
                taps += 1;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder button = find.byType(SignInWithAppleButton);
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('通过 Apple 登录'), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(taps, 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: AppleSignInControl(
            loading: true,
            availability: () async => true,
            onPressed: () async {
              taps += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<SignInWithAppleButton>(button).onPressed, isNull);
  });

  testWidgets('Apple 登录按钮按 Sheet 明暗背景选择官方对比样式', (WidgetTester tester) async {
    Future<void> pumpWith(Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            platform: TargetPlatform.iOS,
          ),
          home: Scaffold(
            body: AppleSignInControl(
              loading: false,
              availability: () async => true,
              onPressed: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(Brightness.light);
    expect(
      tester
          .widget<SignInWithAppleButton>(find.byType(SignInWithAppleButton))
          .style,
      SignInWithAppleButtonStyle.black,
    );

    await pumpWith(Brightness.dark);
    expect(
      tester
          .widget<SignInWithAppleButton>(find.byType(SignInWithAppleButton))
          .style,
      SignInWithAppleButtonStyle.white,
    );
  });

  testWidgets('Apple 授权取消静默留在 Sheet，错误可读且成功回原落点', (WidgetTester tester) async {
    final _AppleLoginAuth canceled = _AppleLoginAuth();
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.iOS,
        availability: () async => true,
        authOverride: () => canceled,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通过 Apple 登录'));
    await tester.pumpAndSettle();
    expect(canceled.attempts, 1);
    expect(find.text('登录城瘾'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    final _AppleLoginAuth failed = _AppleLoginAuth(error: 'Apple 登录失败,请稍后重试');
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.iOS,
        availability: () async => true,
        authOverride: () => failed,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通过 Apple 登录'));
    await tester.pump();
    expect(failed.attempts, 1);
    expect(find.text('Apple 登录失败,请稍后重试'), findsOneWidget);
    expect(find.text('登录城瘾'), findsOneWidget);

    final _AppleLoginAuth succeeded = _AppleLoginAuth(succeeds: true);
    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.iOS,
        availability: () async => true,
        authOverride: () => succeeded,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通过 Apple 登录'));
    await tester.pumpAndSettle();
    expect(succeeded.attempts, 1);
    expect(find.text('登录城瘾'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('防误报：当前控件是 Flutter 标准外观，不是 UIKit PlatformView', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: AppleSignInControl(
            loading: false,
            availability: () async => true,
            onPressed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInWithAppleButton), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
  });
}
