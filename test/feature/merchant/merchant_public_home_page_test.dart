// 商家公开主页(别人看到的一面)。
//
// ★ businessStatus 缺席(null)不等于「已打烊」(0)——后端字段本来就可能没填,
//   界面不该替商家宣称一个不知道的状态。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_home_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

class _FakeMerchantApi implements MerchantApi {
  int? requestedMemberId;

  @override
  Future<Map<String, dynamic>> merchantPublicHomeByMember(int memberId) async {
    requestedMemberId = memberId;
    return <String, dynamic>{'memberId': memberId, 'name': '静安咖啡'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 用后端 /api/config/features 实际下发的键形喂开关，锁住页面读的键名。
class _StaticFeatureFlags extends FeatureFlagsNotifier {
  _StaticFeatureFlags(this._flags);
  final Map<String, bool> _flags;

  @override
  Map<String, bool> build() => _flags;
}

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(theme: merchantGoldenTheme(), home: home),
  );
}

void main() {
  test('公开主页以 memberId 请求后端，不用商家档案 id', () async {
    final api = _FakeMerchantApi();
    final container = ProviderContainer(
      overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
    );
    addTearDown(container.dispose);

    final data = await container.read(
      merchantPublicHomeProvider(100096).future,
    );

    expect(api.requestedMemberId, 100096);
    expect(data['memberId'], 100096);
  });

  testWidgets('★ businessStatus 缺席时不显示营业中/已打烊', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantPublicHomeProvider(7).overrideWith(
          (ref) async => <String, dynamic>{
            'id': 7,
            'name': '静安咖啡',
            // businessStatus 故意缺席
          },
        ),
      ], const MerchantPublicHomePage(memberId: 7)),
    );
    await tester.pumpAndSettle();

    expect(find.text('静安咖啡'), findsOneWidget);
    expect(find.text('营业中'), findsNothing);
    expect(find.text('已打烊'), findsNothing);
  });

  testWidgets('businessStatus 明确给出时按值展示', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantPublicHomeProvider(8).overrideWith(
          (ref) async => <String, dynamic>{
            'id': 8,
            'name': '徐汇书店',
            'businessStatus': 1,
            'slogan': '一杯咖啡的城市',
            'gallery': 'a.jpg;b.jpg',
            'tags': '安静;适合工作',
          },
        ),
      ], const MerchantPublicHomePage(memberId: 8)),
    );
    await tester.pumpAndSettle();

    expect(find.text('营业中'), findsOneWidget);
    expect(find.text('一杯咖啡的城市'), findsOneWidget);
    expect(find.text('安静'), findsOneWidget);
    expect(find.text('适合工作'), findsOneWidget);
  });

  testWidgets('★ 缺参深链落「链接参数无效」态，不去打一个猜出来的 id', (WidgetTester tester) async {
    final api = _FakeMerchantApi();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantApiProvider.overrideWithValue(api),
      ], const MerchantPublicHomePage()),
    );
    await tester.pumpAndSettle();

    // 对齐小程序 `state === 'invalid'`:说清是**链接**的问题,不猜主体 ID
    // (猜错会把人送到别人主页),也不给一个点了没用的重试。
    expect(find.text('链接参数无效'), findsOneWidget);
    expect(find.text('这个链接缺少商家或据点信息，无法确定要打开哪一页。'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(api.requestedMemberId, isNull);
  });

  testWidgets('★ 不可公开是业务空态，不是可重试的故障', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantPublicHomeProvider(
          999,
        ).overrideWith((ref) async => throw MerchantApiException('商家不存在或未开放')),
      ], const MerchantPublicHomePage(memberId: 999)),
    );
    await tester.pumpAndSettle();

    expect(find.text('商家不存在或未开放'), findsOneWidget);
    expect(find.text('这家店暂时无法查看，去首页看看其他城市内容。'), findsOneWidget);
    expect(find.text('重试'), findsNothing, reason: '这家店不会因为再点一次就出现');
  });

  testWidgets('★★ 网络失败不能说成「这家不存在」', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantPublicHomeProvider(
          7,
        ).overrideWith((ref) async => throw Exception('网络异常，请稍后重试')),
      ], const MerchantPublicHomePage(memberId: 7)),
    );
    await tester.pumpAndSettle();

    // 「没查到」与「这家不存在」是两件事:后者是事实,前者只是这次没成功。
    expect(find.text('商家不存在或未开放'), findsNothing);
    expect(find.textContaining('网络异常'), findsWidgets);
    expect(find.text('重试'), findsOneWidget);
  });

  // ★ #276 P1-2 锁键名:后端 /api/config/features 下发的键是 shopNpcChat
  //   (真源 NpcFeatureFlags.KEY_SHOP_CHAT = feature.flag.shopNpcChat;
  //   ApiConfigController data.put("shopNpcChat", …))。
  //   merchantNpcChat 这个键后端**从不返回**,曾经错位导致「聊聊」恒不可达。
  group('「聊聊」入口只认后端真源键 shopNpcChat', () {
    Future<void> pumpWithFlags(
      WidgetTester tester,
      Map<String, bool> flags,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      await tester.pumpWidget(
        _app(<dynamic>[
          featureFlagsProvider.overrideWith(() => _StaticFeatureFlags(flags)),
          merchantPublicHomeProvider(
            7,
          ).overrideWith(
            (ref) async => <String, dynamic>{
              'id': 7,
              'name': '静安咖啡',
              'npc': <String, dynamic>{
                'name': '店小二',
                'greeting': '欢迎光临',
              },
            },
          ),
        ], const MerchantPublicHomePage(memberId: 7)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shopNpcChat=true(后端实际口径)→ 出现「聊聊」', (tester) async {
      await pumpWithFlags(tester, <String, bool>{'shopNpcChat': true});
      expect(find.text('店小二'), findsOneWidget);
      expect(find.byKey(const Key('merchant-npc-chat-entry')), findsOneWidget);
      expect(find.text('聊聊'), findsOneWidget);
    });

    testWidgets('只有 merchantNpcChat=true(后端从不返回的错键)→ 不开入口,形象卡仍在', (tester) async {
      await pumpWithFlags(tester, <String, bool>{'merchantNpcChat': true});
      expect(find.text('店小二'), findsOneWidget);
      expect(find.text('聊聊'), findsNothing);
    });
  });

  // ★ #276 P1-3:线上 12 商家 public-home 的 `npc` 字段全空/缺席
  //   (后端 resolveForMerchant 只回「已过审且启用」的形象,商家没配就是 null,
  //   契约写明「取不到就留 null,主页整块不渲染」)。
  //   App 端的义务是不白屏、不报错占位,店信息照常渲染。
  testWidgets('npc 字段全空时整页优雅降级:无形象卡、无占位报错', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _app(<dynamic>[
        featureFlagsProvider.overrideWith(
          () => _StaticFeatureFlags(<String, bool>{'shopNpcChat': true}),
        ),
        merchantPublicHomeProvider(7).overrideWith(
          (ref) async => <String, dynamic>{
            'id': 7,
            'name': '静安咖啡',
            'npc': null, // 后端显式下发 null
          },
        ),
      ], const MerchantPublicHomePage(memberId: 7)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'npc 空不许炸页');
    expect(find.text('静安咖啡'), findsOneWidget);
    expect(find.text('聊聊'), findsNothing);
    expect(find.text('店小二'), findsNothing);
  });
}
