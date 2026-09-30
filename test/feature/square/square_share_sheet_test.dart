// 分享面板:复制链接 / 系统分享。
//
// ★ 小程序帖文只能把内容交给微信(`open-type="share"`);App 是独立客户端,
//   分享出口必须有一条不依赖社交平台的(复制链接),链接与小程序落地页同源。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';
import 'package:chengyin_app/feature/square/square_share_sheet.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _NoopSquareApi implements SquareApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('分享链接与小程序落地页同源', () {
    expect(squareShareUrl(7), 'https://api.example.invalid/square/7');
  });

  testWidgets('点分享先出面板,两条出路都在;复制链接写进剪贴板并给回执', (WidgetTester tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareApiProvider.overrideWithValue(_NoopSquareApi()),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 7, memberId: 11, contents: '分享我'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-post-share-7')));
    await tester.pumpAndSettle();
    expect(find.text('分享这条动态'), findsOneWidget);
    expect(find.byKey(const Key('square-share-copy')), findsOneWidget);
    expect(find.byKey(const Key('square-share-system')), findsOneWidget);
    expect(copied, isEmpty, reason: '只是打开面板,还没选');

    await tester.tap(find.byKey(const Key('square-share-copy')));
    await tester.pumpAndSettle();
    expect(copied, <String>['https://api.example.invalid/square/7']);
    expect(find.text('链接已复制'), findsOneWidget);
  });
}
