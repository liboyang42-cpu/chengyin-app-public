// B1 二轮报告 N1:POI 详情把 401(需登录)说成「据点暂时打不开…稍后可以
// 重新读取」—— 重试对游客永远是死路,且没有登录入口。
//
// 修法与 #208 同口径(同 stamp-album/camera/nearby):`/api/city/nodes/{id}`
// 契约 auth=required(真源 get-auth-matrix-contract.test.js:42),游客短路
// 掉注定 401 的请求,页内登录门负责解释与登入口;真故障(502/拒连)才给重试。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixed_auth.dart';

final AuthState _guest = guestAuthState;
final AuthState _signedIn = signedInAuthState();

class _NodeDetailRoamApi extends RoamApi {
  _NodeDetailRoamApi(this.onNodeDetail)
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final Future<CityNodeDetail> Function(int poiId) onNodeDetail;
  int nodeDetailCalls = 0;

  @override
  Future<CityNodeDetail> nodeDetail(int poiId) async {
    nodeDetailCalls += 1;
    return onNodeDetail(poiId);
  }

  @override
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(
    int merchantId,
  ) async => const (RoamMerchantInfo(id: 1), null);
}

DioException _http(int status) => DioException(
  type: DioExceptionType.badResponse,
  requestOptions: RequestOptions(path: '/api/city/nodes/1'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/city/nodes/1'),
    statusCode: status,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required AuthState auth,
  required _NodeDetailRoamApi api,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => FixedAuth(auth)),
        roamApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: RoamPoiDetailPage(poiId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('游客进 POI 详情:落在登录门,注定 401 的请求一个不发', (WidgetTester tester) async {
    final api = _NodeDetailRoamApi((_) async => throw UnimplementedError());
    await _pump(tester, auth: _guest, api: api);

    expect(find.byKey(const Key('roam-poi-login-gate')), findsOneWidget);
    expect(find.text('登录后查看这个据点'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    // N1 前症:「稍后可以重新读取」对游客是永远按不动的死路。
    expect(find.textContaining('稍后可以重新读取'), findsNothing);
    expect(api.nodeDetailCalls, 0);
  });

  testWidgets('登录态读到 401(token 失效):同样走登录门,不假称重试', (WidgetTester tester) async {
    await _pump(
      tester,
      auth: _signedIn,
      api: _NodeDetailRoamApi((_) => throw _http(401)),
    );

    expect(find.byKey(const Key('roam-poi-login-gate')), findsOneWidget);
    expect(find.text('登录后查看这个据点'), findsOneWidget);
    expect(find.textContaining('稍后可以重新读取'), findsNothing);
  });

  testWidgets('登录态读到 502:这才是真故障,给「据点暂时打不开 + 重试」', (WidgetTester tester) async {
    await _pump(
      tester,
      auth: _signedIn,
      api: _NodeDetailRoamApi((_) => throw _http(502)),
    );

    expect(find.byKey(const Key('roam-poi-login-gate')), findsNothing);
    expect(find.text('据点暂时打不开'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
