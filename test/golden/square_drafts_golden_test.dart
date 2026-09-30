// 草稿箱整页快照：本机草稿区（单条删除/清空入口）+ 服务器草稿区四态。
// 更新基准图：flutter test --update-goldens test/golden/square_drafts_golden_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_draft.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_drafts_page.dart';
import 'package:chengyin_app/feature/square/square_local_draft_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User.fromJson({'id': 7, 'nickname': '作者'}),
    initialized: true,
  );
}

class _FakeSquareAdapter implements HttpClientAdapter {
  _FakeSquareAdapter(this.items);
  final List<Map<String, dynamic>> items;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'code': 200,
      'data': <String, dynamic>{'items': items, 'nextCursor': null},
    }),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

Widget _app(SquareApi api) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(() => _Auth()),
    secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
    squareApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    theme: goldenTheme(),
    debugShowCheckedModeBanner: false,
    home: const SquareDraftsPage(),
  ),
);

void main() {
  const store = SquareLocalDraftStore(FlutterSecureStorage());

  Future<void> seedLocal() async {
    await store.save(
      7,
      const SquareDraft(
        workflowId: 'gold-new',
        contents: '周末梧桐区City Walk，还没写完',
        pics: <String>[],
      ),
    );
    await store.save(
      7,
      const SquareDraft(
        workflowId: 'gold-21',
        id: 21,
        sourceLifecycle: 'PUBLISHED',
        contents: '把结尾那段改成雨天版本',
      ),
    );
  }

  final serverItems = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 31,
      'authorId': 7,
      'body': '夜跑三公里打卡（未发布）',
      'lifecycle': 'DRAFT',
      'version': 1,
    },
    <String, dynamic>{
      'id': 32,
      'authorId': 7,
      'body': '被限制的那条，需要改了重审',
      'lifecycle': 'LIMITED',
      'version': 3,
    },
  ];

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await seedLocal();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Map<String, dynamic>>? items,
  }) async {
    setGoldenViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        SquareApi(
          DioClient(TokenStore(const FlutterSecureStorage()))
            ..dio.httpClientAdapter = _FakeSquareAdapter(items ?? serverItems),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('删前：本机草稿区 + 服务器草稿区', (tester) async {
    await pump(tester);
    await expectLater(
      find.byType(SquareDraftsPage),
      matchesGoldenFile('goldens/page_square_drafts_before.png'),
    );
  });

  testWidgets('单条删除的二次确认框', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('square-local-draft-more:new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这条本机草稿'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_square_drafts_confirm.png'),
    );
  });

  testWidgets('清空全部的二次确认框（含条数与不可恢复）', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('square-local-drafts-clear-all')));
    await tester.pumpAndSettle();
    expect(find.text('共 2 条，删除后不可恢复。'), findsOne);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_square_drafts_clear_confirm.png'),
    );
  });

  testWidgets('删后：本机只剩一条，清空入口仍在', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('square-local-draft-more:21')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这条本机草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('把结尾那段改成雨天版本'), findsNothing);
    await expectLater(
      find.byType(SquareDraftsPage),
      matchesGoldenFile('goldens/page_square_drafts_after_delete.png'),
    );
  });

  testWidgets('空态：全删光后回到整页空态且无清空入口', (tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await pump(tester, items: const <Map<String, dynamic>>[]);
    expect(
      find.byKey(const Key('square-local-drafts-clear-all')),
      findsNothing,
    );
    expect(find.text('暂无草稿或待复审内容'), findsOne);
    await expectLater(
      find.byType(SquareDraftsPage),
      matchesGoldenFile('goldens/page_square_drafts_empty.png'),
    );
  });
}
