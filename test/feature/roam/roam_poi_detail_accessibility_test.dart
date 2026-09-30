import 'dart:ui' as ui;

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/city_node_detail.dart';
import 'package:chengyin_app/data/models/roam_merchant_info.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/roam/roam_poi_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixed_auth.dart';

class _GalleryRoamApi extends RoamApi {
  _GalleryRoamApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  @override
  Future<CityNodeDetail> nodeDetail(int poiId) async => CityNodeDetail(
    poiId: poiId,
    name: '武康大楼',
    status: 1,
    merchantId: 31,
    lat: 31.2,
    lng: 121.4,
  );

  @override
  Future<(RoamMerchantInfo, RoamFeatured?)> publicMerchantDetail(
    int merchantId,
  ) async => const (
    RoamMerchantInfo(
      id: 31,
      name: '梧桐咖啡',
      gallery: <String>[
        'https://img.example/store-1.jpg',
        'https://img.example/store-2.jpg',
      ],
    ),
    null,
  );
}

void main() {
  testWidgets('店铺相册每张预览图都是有名称的 44pt 按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          // N1 后游客在页内登录门前短路,本测试测的是登录后的相册,
          // 所以要固定为登录态。
          authControllerProvider.overrideWith(
            () => FixedAuth(signedInAuthState()),
          ),
          roamApiProvider.overrideWithValue(_GalleryRoamApi()),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const RoamPoiDetailPage(poiId: 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const Key previewKey = Key('roam-gallery-preview-0');
    final Finder preview = find.byKey(previewKey);
    expect(preview, findsOneWidget);
    expect(tester.getSize(preview).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(preview).height, greaterThanOrEqualTo(44));
    final previewData = tester.getSemantics(preview).getSemanticsData();
    expect(previewData.label, '预览店铺图片 1，共 2 张');
    expect(previewData.hasAction(ui.SemanticsAction.tap), isTrue);

    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('关闭图片预览'), findsOneWidget);
    semantics.dispose();
  });
}
