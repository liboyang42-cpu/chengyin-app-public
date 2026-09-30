import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_insight.dart';
import 'package:chengyin_app/feature/merchant/merchant_ai_insight_page.dart';
import 'golden_theme.dart';

void main() {
  setUpAll(() async {
    final String family = const TextStyle(
      fontFamily: CupertinoIcons.iconFont,
      package: CupertinoIcons.iconFontPackage,
    ).fontFamily!;
    final FontLoader loader = FontLoader(family)
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await loader.load();
  });

  testWidgets('商家店铺参谋：事实与 AI 完整态', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 2000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantInsightProvider.overrideWith(
            (ref) async => MerchantInsight.fromJson(<String, dynamic>{
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
                    <String, dynamic>{'hour': 18, 'count': 2},
                  ],
                },
                'crowd': <String, dynamic>{
                  'members': 9,
                  'sexRatio': <String, dynamic>{'male': 0.4, 'female': 0.6},
                  'interestTop': <dynamic>['咖啡', 'citywalk', '艺术展'],
                },
                'supply': <String, dynamic>{
                  'activeOffers': 3,
                  'quotaUsedRate': 0.7,
                },
              },
              'ai': <String, dynamic>{
                'summary': '工作日下午客流最旺，适合联合周边主题主办方做一场轻量的咖啡漫游。',
                'audiences': <dynamic>[
                  <String, dynamic>{'label': '25-34岁女性', 'reason': '占比最高'},
                  <String, dynamic>{'label': '城市漫游爱好者', 'reason': '兴趣匹配'},
                ],
                'suggestions': <dynamic>[
                  <String, dynamic>{
                    'title': '下午咖啡漫游',
                    'type': 'topic_coop',
                    'timeSlot': '周三下午',
                    'audience': '周边白领',
                    'reason': '客流高峰和兴趣标签都与该主题匹配。',
                  },
                ],
              },
            }),
          ),
        ],
        child: MaterialApp(
          theme: merchantGoldenTheme(),
          debugShowCheckedModeBanner: false,
          home: MerchantAiInsightPage(onOpenSuggestion: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/merchant_ai_insight.png'),
    );
  });
}
