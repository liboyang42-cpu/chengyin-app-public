import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/settings/about_page.dart';

class _LoggedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

Widget _app({AboutPage page = const AboutPage()}) {
  return ProviderScope(
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_LoggedOutAuth.new),
    ].cast(),
    child: MaterialApp(home: page),
  );
}

void main() {
  testWidgets('联系我们打开 Apple 原生操作 Sheet', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系我们'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('拨打 15229020419'), findsOneWidget);
    expect(find.text('复制电话号码'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('拨打客服电话交给系统 tel launcher', (WidgetTester tester) async {
    final List<Uri> launched = <Uri>[];
    final List<String> copied = <String>[];
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        page: AboutPage(
          launchContactUri: (Uri uri) async {
            launched.add(uri);
            return true;
          },
          copyContactText: (String text) async => copied.add(text),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系我们'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拨打 15229020419'));
    await tester.pumpAndSettle();

    expect(launched, <Uri>[Uri(scheme: 'tel', path: '15229020419')]);
    expect(copied, isEmpty);
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets('复制客服电话写入系统剪贴板并给出可达反馈', (WidgetTester tester) async {
    final List<Uri> launched = <Uri>[];
    final List<String> copied = <String>[];
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        page: AboutPage(
          launchContactUri: (Uri uri) async {
            launched.add(uri);
            return true;
          },
          copyContactText: (String text) async => copied.add(text),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系我们'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制电话号码'));
    await tester.pumpAndSettle();

    expect(copied, <String>['15229020419']);
    expect(launched, isEmpty);
    expect(find.text('电话号码已复制'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('取消只关闭 Sheet，不拨号也不写剪贴板', (WidgetTester tester) async {
    final List<Uri> launched = <Uri>[];
    final List<String> copied = <String>[];
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        page: AboutPage(
          launchContactUri: (Uri uri) async {
            launched.add(uri);
            return true;
          },
          copyContactText: (String text) async => copied.add(text),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系我们'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(launched, isEmpty);
    expect(copied, isEmpty);
  });
}
