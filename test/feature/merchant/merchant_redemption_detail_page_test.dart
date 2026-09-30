// 核销详情页的错误态。
//
// ★ 这一页进来的路是「台账点一行」,失败时用户看到的**只有这一屏** ——
//   所以上屏的必须是能看懂的话:哪一步失败 + 下一步做什么。
//   b1 报告 P2-1 实拍的是同一类毛病(502 时整段英文 DioException 糊在中文页面上)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_finance.dart';
import 'package:chengyin_app/feature/merchant/merchant_redemption_detail_page.dart';
import '../../golden/golden_theme.dart';

/// 生产里 502 就是这个形状(dio 的 validateStatus 走 `DioException.badResponse`)。
/// ⚠️ 手搓 `DioException(...)` 的 message 是 null,toString 里没有状态码,测不出真身。
DioException _badResponse502(String path) => DioException.badResponse(
  statusCode: 502,
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 502,
  ),
);

class _ThrowingApi implements MerchantApi {
  _ThrowingApi(this.error);
  final Object error;

  @override
  Future<MerchantRedemptionView> redemptionDetail({
    required String recordId,
    String recordType = 'redemption',
  }) async => throw error;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, Object error) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[
        merchantApiProvider.overrideWithValue(_ThrowingApi(error)),
      ].cast(),
      child: MaterialApp(
        theme: merchantGoldenTheme(),
        home: const MerchantRedemptionDetailPage(
          recordType: 'redemption',
          recordId: '1',
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★ 502:说「网络异常」,不把英文 DioException 甩上屏', (WidgetTester t) async {
    await _pump(t, _badResponse502('/api/merchant/finance/redemption-detail'));

    expect(find.text('网络异常，请稍后重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    // 网络故障别贴「这条记录不属于当前商家」——那是另一种失败的病。
    expect(find.text('这条记录不属于当前商家,或已被移除'), findsNothing);
  });

  testWidgets('★ 记录不可见:照后端原话说,不给点了没用的重试', (WidgetTester t) async {
    await _pump(t, MerchantApiException('记录不可见'));

    expect(find.text('核销记录不可见'), findsOneWidget);
    expect(find.text('这条记录不属于当前商家,或已被移除'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}
