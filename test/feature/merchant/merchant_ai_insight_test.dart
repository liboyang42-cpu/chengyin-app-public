import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_insight.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/feature/merchant/merchant_ai_insight_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';

void main() {
  MerchantInsight sample({bool withAi = true}) =>
      MerchantInsight.fromJson(<String, dynamic>{
        'generatedAt': '14:25',
        'facts': <String, dynamic>{
          'window': '近30天',
          'sampleMembers': 12,
          'lowSample': false,
          'checkin': <String, dynamic>{
            'total': 18,
            'redeemRate': 0.5,
            'repeatRate': 0.25,
            'avgWaitMinutes': 12,
            'hourBuckets': <dynamic>[
              <String, dynamic>{'hour': 10, 'count': 1},
              <String, dynamic>{'hour': 14, 'count': 4},
            ],
          },
          'crowd': <String, dynamic>{
            'members': 9,
            'sexRatio': <String, dynamic>{'male': 0.4, 'female': 0.6},
            'interestTop': <dynamic>['咖啡', 'citywalk'],
          },
          'supply': <String, dynamic>{'activeOffers': 3, 'quotaUsedRate': 0.7},
        },
        if (withAi)
          'ai': <String, dynamic>{
            'summary': '工作日下午客流最旺',
            'audiences': <dynamic>[
              <String, dynamic>{'label': '25-34岁女性', 'reason': '占比最高'},
            ],
            'suggestions': <dynamic>[
              <String, dynamic>{
                'title': '下午咖啡漫游',
                'type': 'topic_coop',
                'timeSlot': '周三下午',
                'audience': '白领',
                'reason': '客流与时段匹配',
              },
            ],
          }
        else
          'aiError': '今日 AI 次数已用完',
      });

  Widget app(MerchantInsight insight, {ValueChanged<String>? onOpen}) {
    return ProviderScope(
      overrides: [merchantInsightProvider.overrideWith((ref) async => insight)],
      child: MaterialApp(
        theme: AppTheme.merchantLight(),
        home: MerchantAiInsightPage(onOpenSuggestion: onOpen),
      ),
    );
  }

  test('没有值不冒充真实 0，建议类型只映射白名单目标', () {
    final MerchantInsight insight = MerchantInsight.fromJson(<String, dynamic>{
      'facts': <String, dynamic>{
        'checkin': <String, dynamic>{'total': 0},
        'crowd': <String, dynamic>{'members': 0},
        'supply': <String, dynamic>{'activeOffers': 0},
      },
    });

    expect(insight.facts.checkin.redeemRate, isNull);
    expect(insight.facts.checkin.redeemRateText, '—');
    expect(insight.facts.checkin.segmentFillCount, 0);
    expect(MerchantInsightSuggestion.routeFor('topic_coop'), '/merchant/coop');
    expect(MerchantInsightSuggestion.routeFor('decor'), '/merchant/decor');
    expect(MerchantInsightSuggestion.routeFor('content'), '/publish/pro');
    expect(MerchantInsightSuggestion.routeFor('invented'), isNull);
  });

  testWidgets('页面按小程序次序展示事实、客群、AI 与建议', (WidgetTester tester) async {
    String? opened;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(
      app(sample(), onOpen: (String route) => opened = route),
    );
    await tester.pumpAndSettle();

    expect(find.text('店铺参谋'), findsOneWidget);
    expect(find.text('生成于 14:25，次日更新'), findsOneWidget);
    expect(find.text('到店打卡'), findsOneWidget);
    expect(find.text('核销率 50%'), findsOneWidget);
    expect(find.text('到店顾客'), findsOneWidget);
    expect(find.text('复购率 25%'), findsOneWidget);
    expect(find.text('合作席位'), findsOneWidget);
    expect(find.text('席位已用 70%'), findsOneWidget);
    expect(find.text('到店时段'), findsOneWidget);
    expect(find.text('平均等待 12分钟'), findsOneWidget);
    expect(find.text('客群构成'), findsOneWidget);
    expect(find.text('男 40% · 女 60%'), findsOneWidget);
    expect(find.text('经营解读'), findsOneWidget);
    expect(find.text('工作日下午客流最旺'), findsOneWidget);
    expect(find.text('建议活动'), findsOneWidget);

    final double metricTop = tester.getTopLeft(find.text('到店打卡')).dy;
    final double hoursTop = tester.getTopLeft(find.text('到店时段')).dy;
    final double crowdTop = tester.getTopLeft(find.text('客群构成')).dy;
    final double aiTop = tester.getTopLeft(find.text('经营解读')).dy;
    final double suggestionTop = tester.getTopLeft(find.text('建议活动')).dy;
    expect(metricTop, lessThan(hoursTop));
    expect(hoursTop, lessThan(crowdTop));
    expect(crowdTop, lessThan(aiTop));
    expect(aiTop, lessThan(suggestionTop));

    await tester.ensureVisible(find.text('一键去办'));
    await tester.tap(find.text('一键去办'));
    expect(opened, '/merchant/coop');
  });

  testWidgets('AI 失败只降级解读区，事实区仍完整展示', (WidgetTester tester) async {
    await tester.pumpWidget(app(sample(withAi: false)));
    await tester.pumpAndSettle();

    expect(find.text('到店打卡'), findsOneWidget);
    expect(find.text('核销率 50%'), findsOneWidget);
    expect(find.text('今日 AI 次数已用完，上方经营数据不受影响'), findsOneWidget);
    expect(find.text('建议活动'), findsNothing);
  });

  testWidgets('直接深链打开时非商家仍走商家角色门禁', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantInsightProvider.overrideWith(
            (ref) async => throw MerchantApiException('仅商家可访问'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.merchantLight(),
          home: const MerchantAiInsightPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你还不是商家'), findsOneWidget);
    expect(find.text('申请入驻通过后,这里会显示你的经营数据'), findsOneWidget);
    expect(find.text('到店打卡'), findsNothing);
  });

  // ★ 品牌手册/copy_parity:这两块是**后端下发的真实主体**,
  //   小程序 `ai-insight` 的第 3、4 段;App 此前一处都没渲染(visual_parity C12b/C12c)。
  testWidgets('推荐主题与推荐商家两块照小程序渲染并各自导航', (WidgetTester tester) async {
    final List<String> opened = <String>[];
    final MerchantInsight insight = MerchantInsight.fromJson(<String, dynamic>{
      'facts': <String, dynamic>{
        'window': '近30天',
        'checkin': <String, dynamic>{'total': 18},
        'crowd': <String, dynamic>{'members': 9},
        'supply': <String, dynamic>{'activeOffers': 3},
      },
      'recommendedTopics': <dynamic>[
        <String, dynamic>{'topicId': 7, 'name': '梧桐区咖啡漫游'},
      ],
      'recommendedPartners': <dynamic>[
        <String, dynamic>{
          'merchantId': 3,
          'memberId': 100096,
          'name': '静安咖啡',
          'cityRole': '咖啡馆',
          'slogan': '一杯咖啡的城市',
          'category': '咖啡',
          'distanceM': 1250,
          'tags': '安静，适合工作;宠物友好、超出不摆',
          'reason': '客群重合',
          'businessStatus': 1,
        },
      ],
    });
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    await tester.pumpWidget(
      app(insight, onOpen: (String route) => opened.add(route)),
    );
    await tester.pumpAndSettle();

    expect(find.text('为你推荐的主题'), findsOneWidget);
    expect(find.text('梧桐区咖啡漫游'), findsOneWidget);
    expect(find.text('自由探索'), findsOneWidget);
    expect(find.text('招商中'), findsOneWidget);
    // 理由缺席时用小程序那句兜底。
    expect(find.text('平台招商中的自由探索主题'), findsOneWidget);

    expect(find.text('推荐联动的商家'), findsOneWidget);
    expect(find.text('静安咖啡'), findsOneWidget);
    expect(find.text('营业中'), findsOneWidget);
    expect(find.text('可联动'), findsOneWidget);
    expect(find.text('咖啡馆'), findsOneWidget);
    expect(find.text('一杯咖啡的城市'), findsOneWidget);
    // 距离一位小数、tags 全角逗号/顿号都要切开,且最多 3 枚。
    expect(find.text('1.3km · 咖啡'), findsOneWidget);
    expect(find.text('安静'), findsOneWidget);
    expect(find.text('适合工作'), findsOneWidget);
    expect(find.text('宠物友好'), findsOneWidget);
    expect(find.text('超出不摆'), findsNothing);
    expect(find.text('客群重合'), findsOneWidget);

    // 主题 → 合作中心;商家 → **canonical member 主页**,不是商家档案 id。
    await tester.ensureVisible(find.text('去申请承接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去申请承接'));
    await tester.ensureVisible(find.text('发起接洽'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发起接洽'));
    expect(opened, <String>[
      '/merchant/coop',
      '/merchant/public-home/member/100096',
    ]);
  });

  testWidgets('★ 拿不到 memberId 时接洽按钮置灰，不送用户去猜出来的主页', (
    WidgetTester tester,
  ) async {
    String? opened;
    final MerchantInsight insight = MerchantInsight.fromJson(<String, dynamic>{
      'facts': <String, dynamic>{
        'checkin': <String, dynamic>{'total': 18},
        'crowd': <String, dynamic>{'members': 9},
        'supply': <String, dynamic>{'activeOffers': 3},
      },
      'recommendedPartners': <dynamic>[
        <String, dynamic>{'merchantId': 3, 'name': '无主体商家'},
      ],
    });
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    await tester.pumpWidget(
      app(insight, onOpen: (String route) => opened = route),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('发起接洽'));
    await tester.tap(find.text('发起接洽'));
    expect(opened, isNull);
  });

  testWidgets('没有时段数据时显示小程序原空态', (WidgetTester tester) async {
    final MerchantInsight empty = MerchantInsight.fromJson(<String, dynamic>{
      'facts': <String, dynamic>{
        'window': '近30天',
        'checkin': <String, dynamic>{'total': 0, 'hourBuckets': <dynamic>[]},
        'crowd': <String, dynamic>{'members': 0},
        'supply': <String, dynamic>{'activeOffers': 0},
      },
      'aiError': 'AI 解读暂不可用',
    });
    await tester.pumpWidget(app(empty));
    await tester.pumpAndSettle();

    expect(find.text('还没有到店数据'), findsOneWidget);
    expect(find.text('先去合作中心承接一个主题，玩家到店打卡后这里就有数据了'), findsOneWidget);
    // 空态要给一条真能走的下一步(小程序 .empty-cta)。
    expect(find.text('去合作中心看看'), findsOneWidget);
    expect(find.text('客群构成'), findsNothing);
  });

  testWidgets('营销页在优惠券之后提供店铺参谋入口并打开三级页', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/merchant/marketing',
      routes: <RouteBase>[
        GoRoute(
          path: '/merchant/marketing',
          builder: (_, _) => const MerchantMarketingPage(),
        ),
        GoRoute(
          path: '/merchant/marketing/ai-insight',
          builder: (_, _) => const Scaffold(body: Text('参谋目标页')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantMarketingProvider.overrideWith(
            (ref) async => const MerchantMarketing(couponCount: 2),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.merchantLight(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('店铺参谋'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('优惠券')).dy,
      lessThan(tester.getTopLeft(find.text('店铺参谋')).dy),
    );
    expect(
      tester.getTopLeft(find.text('店铺参谋')).dy,
      lessThan(tester.getTopLeft(find.text('我的内容')).dy),
    );
    await tester.tap(find.text('店铺参谋'));
    await tester.pumpAndSettle();
    expect(find.text('参谋目标页'), findsOneWidget);
  });

  testWidgets('非商家只显示角色门禁，不暴露店铺参谋入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantMarketingProvider.overrideWith(
            (ref) async => throw MerchantApiException('商家信息不存在'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.merchantLight(),
          home: const MerchantMarketingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你还不是商家'), findsOneWidget);
    expect(find.text('店铺参谋'), findsNothing);
  });
}
