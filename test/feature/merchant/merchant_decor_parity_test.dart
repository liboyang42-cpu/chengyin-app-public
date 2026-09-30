import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_decor.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_gallery_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_story_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({this.profile, this.loadError});

  final Map<String, dynamic>? profile;
  final Object? loadError;
  MerchantDecor? savedDecor;
  List<String>? savedGallery;
  String? savedStoryTitle;
  Map<String, String?>? savedBrand;

  @override
  Future<Map<String, dynamic>> coopProfile() async {
    if (loadError != null) throw loadError!;
    return profile ?? <String, dynamic>{};
  }

  @override
  Future<void> saveDecor(MerchantDecor decor) async {
    savedDecor = decor;
  }

  @override
  Future<void> saveDecorGallery(List<String> gallery) async {
    savedGallery = List<String>.of(gallery);
  }

  @override
  Future<void> saveDecorStoryTitle(String storyTitle) async {
    savedStoryTitle = storyTitle;
  }

  @override
  Future<String> updateMerchant({
    String? logo,
    String? name,
    String? description,
    String? derivatives,
    String? website,
    String? preference,
  }) async {
    savedBrand = <String, String?>{
      'logo': logo,
      'name': name,
      'description': description,
      'derivatives': derivatives,
      'website': website,
      'preference': preference,
    };
    return '已保存';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _profile({
  Object gallery = '["a.jpg","b.jpg"]',
  Object tags = '安静;夜间开放',
}) => <String, dynamic>{
  'id': 7,
  'memberId': 100096,
  'name': '夜归咖啡',
  'logo': 'logo.jpg',
  'description': '和这条街一起醒着。',
  'derivatives': '限定饮品',
  'website': 'https://example.com',
  'preference': '无糖',
  'coverImage': 'cover.jpg',
  'cityRole': '巷口的夜间补给站',
  'slogan': '一杯咖啡的城市',
  'storyTitle': '夜归的灯',
  'gallery': gallery,
  'tags': tags,
  'businessStatus': 1,
  'capacity': 20,
  'availableTime': '周五夜间',
  'chargeType': 0,
  'locationVerified': 1,
  'sysCategoryList': <Map<String, dynamic>>[
    <String, dynamic>{'categoryName': '咖啡'},
  ],
};

Widget _app(_FakeMerchantApi api, String initialLocation) {
  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/merchant/decor',
        builder: (_, _) => const MerchantDecorPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'story',
            builder: (_, _) => const MerchantDecorStoryPage(),
          ),
          GoRoute(
            path: 'gallery',
            builder: (_, _) => const MerchantDecorGalleryPage(),
          ),
        ],
      ),
      GoRoute(path: '/merchant/apply', builder: (_, _) => const Text('商家入驻页')),
      GoRoute(
        path: '/merchant/coop-profile',
        builder: (_, _) => const Text('承接设置页'),
      ),
      GoRoute(
        path: '/coop/perk-templates',
        builder: (_, _) => const Text('常备权益页'),
      ),
      GoRoute(
        path: '/merchant/city-nodes',
        builder: (_, _) => const Text('城市节点页'),
      ),
      GoRoute(
        path: '/merchant/subscription',
        builder: (_, _) => const Text('升级权益页'),
      ),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
    child: MaterialApp.router(
      theme: ThemeData(platform: TargetPlatform.iOS),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('根页先读现有装修，修改 slogan 不覆盖相册与标签', (WidgetTester tester) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor'));
    await tester.pumpAndSettle();

    expect(find.text('品牌资料'), findsOneWidget);
    expect(find.text('资料完整度'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('品牌内容'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('品牌内容'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('承接与经营(B2B 撮合)'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('承接与经营(B2B 撮合)'), findsOneWidget);
    expect(find.text('故事标题'), findsNothing, reason: '小程序已删这个根页字段');

    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('一句话 slogan'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('一句话 slogan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('merchant-decor-field-input')),
      '新 slogan',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(api.savedDecor?.slogan, '新 slogan');
    expect(api.savedDecor?.gallery, <String>['a.jpg', 'b.jpg']);
    expect(api.savedDecor?.tags, <String>['安静', '夜间开放']);
  });

  testWidgets('根页的品牌故事与门店相册分别进三级页', (WidgetTester tester) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('品牌故事'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantDecorStoryPage), findsOneWidget);
    expect(find.text('保存品牌故事'), findsOneWidget);

    await tester.tap(find.byKey(const Key('merchant-story-back')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.tap(find.text('门店相册 · 16:9'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantDecorGalleryPage), findsOneWidget);
    expect(find.text('最多 9 张 · 保存后同步到公开主页'), findsOneWidget);
  });

  testWidgets('品牌故事只编辑正文，保存带回未编辑的品牌字段和标题', (WidgetTester tester) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor/story'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merchant-decor-story-body')), findsOneWidget);
    expect(find.byKey(const Key('merchant-decor-story-title')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('merchant-decor-story-body')),
      '新的品牌故事',
    );
    await tester.tap(find.text('保存品牌故事'));
    await tester.pumpAndSettle();

    expect(api.savedStoryTitle, '夜归的灯');
    expect(api.savedBrand, <String, String?>{
      'logo': 'logo.jpg',
      'name': '夜归咖啡',
      'description': '新的品牌故事',
      'derivatives': '限定饮品',
      'website': 'https://example.com',
      'preference': '无糖',
    });
  });

  testWidgets('相册页删图后只保存 canonical gallery，不提交空 decor', (
    WidgetTester tester,
  ) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor/gallery'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merchant-gallery-image-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('merchant-gallery-delete-0')));
    await tester.pump();
    await tester.tap(find.text('保存相册'));
    await tester.pumpAndSettle();

    expect(api.savedGallery, <String>['b.jpg']);
    expect(api.savedDecor, isNull);
  });

  testWidgets('相册页有未保存修改时,返回先过「还没有保存」那道闸', (WidgetTester tester) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor/gallery'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-gallery-delete-0')));
    await tester.pump();

    // 第一次返回:拦下来,说清丢了什么。
    await tester.tap(find.byKey(const Key('merchant-gallery-back')));
    await tester.pumpAndSettle();
    expect(find.text('还没有保存'), findsOneWidget);
    expect(find.text('离开后，本次相册修改不会保留。'), findsOneWidget);

    // 继续编辑:留在页上,删掉的图还等着保存。
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantDecorGalleryPage), findsOneWidget);
    expect(api.savedGallery, isNull);

    // 放弃修改:这次才真的走。
    await tester.tap(find.byKey(const Key('merchant-gallery-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(MerchantDecorGalleryPage), findsNothing);
    expect(api.savedGallery, isNull);
  });

  testWidgets('相册页没改过时返回不拦', (WidgetTester tester) async {
    final api = _FakeMerchantApi(profile: _profile());
    await tester.pumpWidget(_app(api, '/merchant/decor/gallery'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('merchant-gallery-back')));
    await tester.pumpAndSettle();

    expect(find.text('还没有保存'), findsNothing);
    expect(find.byType(MerchantDecorGalleryPage), findsNothing);
  });

  testWidgets('根页、故事、相册各自显示空店铺态', (WidgetTester tester) async {
    for (final location in <String>[
      '/merchant/decor',
      '/merchant/decor/story',
      '/merchant/decor/gallery',
    ]) {
      await tester.pumpWidget(
        _app(_FakeMerchantApi(profile: const {}), location),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('这个账号还没有店铺'),
        findsOneWidget,
        reason: location,
      );
    }
  });

  testWidgets('根页、故事、相册各自显示可重试错态', (WidgetTester tester) async {
    for (final location in <String>[
      '/merchant/decor',
      '/merchant/decor/story',
      '/merchant/decor/gallery',
    ]) {
      await tester.pumpWidget(
        _app(_FakeMerchantApi(loadError: Exception('断网')), location),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('加载失败'), findsOneWidget, reason: location);
      expect(find.text('重新载入'), findsOneWidget, reason: location);
    }
  });
}
