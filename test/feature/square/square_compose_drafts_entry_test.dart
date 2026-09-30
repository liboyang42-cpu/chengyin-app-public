// 发布帖文页顶栏的「草稿箱」入口回归。
//
// 原挂在 legacy_draft_recovery_test.dart 末尾;那条文件被 main 侧 #101
// (撤 #113 v1 社区侧)整份删除,本用例只钉「入口在/不在」,与旧草稿恢复无关,
// 所以随 rebase 迁出到独立文件。

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_compose_page.dart';
import 'package:chengyin_app/feature/square/square_local_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User.fromJson({'id': 7, 'nickname': '作者'}),
    initialized: true,
  );
}

void main() {
  testWidgets('★ 草稿箱:新建态顶栏有「草稿箱」入口并进草稿页;编辑态不给(gap-spec-roam 附14)', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = SquareLocalDraftStore(FlutterSecureStorage());
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget app(Widget page) {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => page),
          GoRoute(
            path: '/square/drafts',
            builder: (_, _) => const Scaffold(body: Text('草稿箱页')),
          ),
        ],
      );
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          squareLocalDraftStoreProvider.overrideWithValue(store),
          squareApiProvider.overrideWithValue(SquareApi(client)),
          featureFlagProvider.overrideWith((ref, name) => true),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    await tester.pumpWidget(app(const SquareComposePage()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('square-compose-drafts-entry')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('square-compose-drafts-entry')));
    await tester.pumpAndSettle();
    expect(find.text('草稿箱页'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      app(
        const SquareComposePage(
          initialPost: SquarePost(id: 5, memberId: 7, contents: '旧帖'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑帖文'), findsOneWidget, reason: '编辑态标题必须与真源一致');
    expect(
      find.byKey(const Key('square-compose-drafts-entry')),
      findsNothing,
      reason: '草稿是「新建」的存档;编辑态正文不回草稿槽,不给草稿入口',
    );
  });
}
