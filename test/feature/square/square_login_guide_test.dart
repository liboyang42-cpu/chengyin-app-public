// 「我的草稿」/「社区治理」:无 token 时后端返 401(有意拒绝),
// 页面必须说「登录后查看」并给去登录,不能渲成「加载失败」——
// 那会让游客以为是网络问题,反复重试(REPORT-sim-square 问题 4)。
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_drafts_page.dart';
import 'package:chengyin_app/feature/square/square_governance_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _unauthorized(String path) {
  final RequestOptions options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    response: Response<Object?>(requestOptions: options, statusCode: 401),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  testWidgets('草稿页 401 → 登录引导', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          squareDraftsProvider.overrideWith(
            (ref) async => throw _unauthorized('/api/v1/community/drafts'),
          ),
        ].cast(),
        child: const CupertinoApp(home: SquareDraftsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看我的草稿'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('草稿加载失败'), findsNothing);
    expect(find.textContaining('登录状态已失效'), findsNothing);
  });

  testWidgets('治理页 401 → 登录引导', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          squareEnforcementsProvider.overrideWith(
            (ref) async =>
                throw _unauthorized('/api/v1/community/me/enforcements'),
          ),
          squareNotificationsProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[],
          ),
        ].cast(),
        child: const CupertinoApp(home: SquareGovernancePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看社区处置记录'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('未能加载处置记录'), findsNothing);
    expect(find.textContaining('登录状态已失效'), findsNothing);
  });
}
