// 公开口碑页坏深链不再红屏(b1-sim-merchant-4 P2)。
//
// 路由曾把解析不出的 `:merchantRowId` / `:ownerMemberId` 兜成 0,正好撞
// 页面构造期 assert → Debug 整屏英文断言、无出口。同 public-home 口径:
// 路由**不兜 0**,把 null 交给页面渲染「链接参数无效」态。
// 这里验证的是**路由那一半**:0 / 非数字深链必须落在评价页的错误态上,
// 且不发任何公开页请求。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_reviews_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _TrackingReviewApi implements MerchantReviewApi {
  int publicPageCalls = 0;

  @override
  Future<MerchantReviewPage> publicPage({
    required int merchantRowId,
    required int pageNum,
    required int pageSize,
  }) async {
    publicPageCalls += 1;
    throw StateError('坏深链不该发公开页请求');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopPublishApi implements PublishApi {
  @override
  Future<String> uploadImage(String filePath) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<({ProviderContainer container, _TrackingReviewApi api})> pumpGuest(
    WidgetTester tester,
  ) async {
    final _TrackingReviewApi api = _TrackingReviewApi();
    final ProviderContainer container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_GuestAuth.new),
        merchantReviewApiProvider.overrideWithValue(api),
        publishApiProvider.overrideWithValue(_NoopPublishApi()),
      ].cast(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (container: container, api: api);
  }

  for (final (String path, String label) in <(String, String)>[
    ('/merchant/reviews/public/0/41', 'merchantRowId=0'),
    ('/merchant/reviews/public/abc/41', 'merchantRowId 非数字'),
    ('/merchant/reviews/public/31/0', 'ownerMemberId=0'),
  ]) {
    testWidgets('深链 $path($label):落页内「链接参数无效」态，不发请求', (
      WidgetTester tester,
    ) async {
      final ({ProviderContainer container, _TrackingReviewApi api}) ctx =
          await pumpGuest(tester);
      ctx.container.read(appRouterProvider).go(path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        ctx.container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        path,
        reason: label,
      );
      expect(
        find.byType(MerchantPublicReviewsPage),
        findsOneWidget,
        reason: label,
      );
      expect(find.text('链接参数无效'), findsOneWidget, reason: label);
      expect(ctx.api.publicPageCalls, 0, reason: label);
    });
  }
}
