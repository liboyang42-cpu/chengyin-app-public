// 全屏图片查看器:序号、翻页、关闭、朗读标签。
//
// ★ 小程序帖文里点图走 `wx.previewImage`,第几张、能不能缩放都不归我们管;
//   App 这层是自己的 —— 所以这些都必须有断言。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_image_viewer.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

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
  const List<String> urls = <String>[
    'https://img.test/one.jpg',
    'https://img.test/two.jpg',
    'https://img.test/three.jpg',
  ];

  testWidgets('打开即定位到指定张,序号与朗读标签都对', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: CupertinoButton(
              onPressed: () =>
                  showSquareImageViewer(context, urls: urls, initialIndex: 1),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-image-viewer')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('第 2 张，共 3 张'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('左右翻页会更新序号,关闭回到原页面', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: CupertinoButton(
              onPressed: () => showSquareImageViewer(context, urls: urls),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('square-image-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('square-image-viewer')), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('只有一张图时不显示页码胶囊', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: CupertinoButton(
              onPressed: () =>
                  showSquareImageViewer(context, urls: <String>[urls.first]),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('square-image-viewer-count')), findsNothing);
  });

  testWidgets('广场卡片里的图能点开查看器', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareApiProvider.overrideWithValue(_NoopSquareApi()),
          squareFeedPageProvider.overrideWith(
            (ref, mode) async => SquareFeedPage(
              items: <SquarePost>[
                SquarePost(
                  id: 3,
                  memberId: 11,
                  memberNickname: '阿兰',
                  contents: '两张图',
                  pics: <String>[urls[0], urls[1]],
                ),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: SquareListPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-pic-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('square-image-viewer')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });
}
