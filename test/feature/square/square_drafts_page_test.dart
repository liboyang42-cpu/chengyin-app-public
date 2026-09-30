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

import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';

class _RevisionsApi implements SquareApi {
  @override
  Future<List<Map<String, dynamic>>> revisions(int postId) async =>
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
        <String, dynamic>{'id': 2},
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('★ 编辑历史是纯告知:出页内轻提示,不弹 alert(S7)', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          squareApiProvider.overrideWithValue(_RevisionsApi()),
          squareDraftsProvider.overrideWith(
            (ref) async => const SquareFeedPage(
              items: <SquarePost>[
                SquarePost(id: 7, memberId: 1, contents: '草稿一'),
              ],
              hasMore: false,
            ),
          ),
        ].cast(),
        child: const CupertinoApp(home: SquareDraftsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.clock));
    await tester.pumpAndSettle();

    expect(find.text('已保留 2 个不可变修订版本'), findsOneWidget);
    expect(
      find.byType(CupertinoAlertDialog),
      findsNothing,
      reason: 'S7:纯告知不弹 alert',
    );
  });

  test('审核中和已移除内容不能进入编辑器', () {
    expect(squarePostEditableFromWorkspace('CHECKING'), isFalse);
    expect(squarePostEditableFromWorkspace('REMOVED'), isFalse);
    expect(squareWorkspaceStatusLabel('CHECKING'), contains('暂不可编辑'));
    expect(squareWorkspaceStatusLabel('REMOVED'), contains('申诉'));
  });

  test('后端允许编辑的生命周期保持可编辑', () {
    for (final lifecycle in <String>[
      'DRAFT',
      'PUBLISHED',
      'LIMITED',
      'HIDDEN',
    ]) {
      expect(
        squarePostEditableFromWorkspace(lifecycle),
        isTrue,
        reason: lifecycle,
      );
    }
  });

  group('草稿箱删除', () {
    late _DraftApiRecorder recorder;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      recorder = _DraftApiRecorder();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _Auth()),
            secureStorageProvider.overrideWithValue(
              const FlutterSecureStorage(),
            ),
            squareApiProvider.overrideWithValue(SquareApi(_client(recorder))),
          ],
          child: const MaterialApp(home: SquareDraftsPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('本机草稿出现在列表里并可单条删除', (tester) async {
      const store = SquareLocalDraftStore(FlutterSecureStorage());
      await store.save(
        7,
        const SquareDraft(workflowId: 'w-a', contents: '待删草稿甲'),
      );
      await store.save(
        7,
        const SquareDraft(
          workflowId: 'w-b',
          id: 21,
          sourceLifecycle: 'PUBLISHED',
          contents: '修改稿乙',
        ),
      );

      await pump(tester);
      expect(find.text('待删草稿甲'), findsOne);
      expect(find.text('修改稿乙'), findsOne);
      expect(find.text('未保存到服务器 · 仅存在这台设备'), findsOne);
      expect(find.text('本机修改稿 · 尚未同步到服务器'), findsOne);
      expect(find.byKey(const Key('square-local-drafts-clear-all')), findsOne);

      await tester.tap(
        find.byKey(const ValueKey('square-local-draft-more:21')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条本机草稿'));
      await tester.pumpAndSettle();
      expect(find.text('删除这条本机草稿？'), findsOne);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('修改稿乙'), findsNothing);
      expect(find.text('待删草稿甲'), findsOne);
      expect(await store.read(7, postId: 21), isNull);
      expect(await store.read(7), isNotNull);
    });

    testWidgets('取消二次确认不会删除本机草稿', (tester) async {
      const store = SquareLocalDraftStore(FlutterSecureStorage());
      await store.save(
        7,
        const SquareDraft(workflowId: 'w-c', contents: '别删我'),
      );

      await pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('square-local-draft-more:new')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条本机草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
      await tester.pumpAndSettle();

      expect(find.text('别删我'), findsOne);
      expect(await store.read(7), isNotNull);
    });

    testWidgets('清空全部一次确认删光本机草稿，空态后入口隐藏', (tester) async {
      const store = SquareLocalDraftStore(FlutterSecureStorage());
      await store.save(
        7,
        const SquareDraft(workflowId: 'w-d', contents: '草稿一'),
      );
      await store.save(
        7,
        const SquareDraft(
          workflowId: 'w-e',
          id: 21,
          sourceLifecycle: 'PUBLISHED',
          contents: '草稿二',
        ),
      );

      await pump(tester);
      await tester.tap(find.byKey(const Key('square-local-drafts-clear-all')));
      await tester.pumpAndSettle();
      expect(find.text('清空全部本机草稿？'), findsOne);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '全部删除'));
      await tester.pumpAndSettle();

      expect(find.text('草稿一'), findsNothing);
      expect(find.text('草稿二'), findsNothing);
      expect(await store.read(7), isNull);
      expect(await store.read(7, postId: 21), isNull);
      // 两区皆空 → 保持整页空态，且不再显示清空入口。
      expect(find.text('暂无草稿或待复审内容'), findsOne);
      expect(
        find.byKey(const Key('square-local-drafts-clear-all')),
        findsNothing,
      );
    });

    testWidgets('服务器草稿行有删除入口并调 DELETE 端点', (tester) async {
      recorder.draftItems.add(<String, dynamic>{
        'id': 31,
        'authorId': 7,
        'body': '服务器草稿甲',
        'lifecycle': 'DRAFT',
        'version': 2,
      });

      await pump(tester);
      expect(find.text('服务器草稿甲'), findsOne);
      await tester.tap(
        find.byKey(const ValueKey('square-server-draft-more:31')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
      await tester.pumpAndSettle();

      expect(recorder.deletedPaths, <String>['/api/creativesquare/delete']);
      expect(find.text('服务器草稿甲'), findsNothing);
    });

    testWidgets('服务器删除失败时如实报错，不伪装已删除', (tester) async {
      recorder.draftItems.add(<String, dynamic>{
        'id': 32,
        'authorId': 7,
        'body': '删不掉的草稿',
        'lifecycle': 'DRAFT',
        'version': 0,
      });
      recorder.deleteFails = true;

      await pump(tester);
      await tester.tap(
        find.byKey(const ValueKey('square-server-draft-more:32')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除这条草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('删除失败'), findsOne);
      expect(find.text('删不掉的草稿'), findsOne);
    });
  });
}

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User.fromJson({'id': 7, 'nickname': '作者'}),
    initialized: true,
  );
}

class _DraftApiRecorder implements HttpClientAdapter {
  final List<Map<String, dynamic>> draftItems = <Map<String, dynamic>>[];
  bool deleteFails = false;
  final List<String> deletedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    String body;
    // main 侧删除走旧契约 `POST /api/creativesquare/delete`(表单 id),
    // 不再是 v1 的 `DELETE /api/v1/community/posts/{id}`(见 #101 撤 v1)。
    if (o.method == 'POST' && o.path == '/api/creativesquare/delete') {
      deletedPaths.add(o.path);
      if (deleteFails) {
        body = jsonEncode({'code': 503, 'msg': '服务器没能响应删除请求'});
      } else {
        final FormData form = o.data as FormData;
        final String rawId = form.fields
            .firstWhere((MapEntry<String, String> f) => f.key == 'id')
            .value;
        final int? id = int.tryParse(rawId);
        draftItems.removeWhere((row) => row['id'] == id);
        body = jsonEncode({'code': 200, 'msg': '已删除'});
      }
    } else {
      body = jsonEncode({
        'code': 200,
        'data': <String, dynamic>{'items': draftItems, 'nextCursor': null},
      });
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioClient _client(_DraftApiRecorder recorder) {
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = recorder;
  return client;
}
