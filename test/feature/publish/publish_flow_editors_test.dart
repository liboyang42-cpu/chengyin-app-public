import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/publish/ai_draft_logic.dart';
import 'package:chengyin_app/feature/publish/publish_page.dart';
import 'package:chengyin_app/feature/publish/publish_pro_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dio());

  @override
  Future<List<Club>> my() async => <Club>[];
}

class _FakePublishApi extends PublishApi {
  _FakePublishApi() : super(_dio());
}

DioClient _dio() => DioClient(TokenStore(const FlutterSecureStorage()));

void main() {
  test('快速配置只把已确认地点的草稿交给专业编辑器', () {
    final PublishDraft draft = buildQuickPublishDraft(
      mode: 2,
      title: '静安夜游',
      description: '找到街区的三个暗号',
      nodes: const <ConfirmedNode>[
        ConfirmedNode(
          name: '武定路口',
          description: '找门牌',
          address: '武定路 100 号',
          longitude: '121.45',
          latitude: '31.23',
        ),
      ],
    );

    expect(draft.productType, kProductFreeExplore);
    expect(draft.publishMode, 'ai_simple');
    expect(draft.chapters.single.nodes.single.name, '武定路口');
    expect(draft.chapters.single.nodes.single.longitude, '121.45');
    expect(draft.chapters.single.nodes.single.address, '武定路 100 号');
  });

  testWidgets('快速编辑器保留从 Sheet 选中的自由探索语义', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PublishPage(mode: 2))),
    );
    await tester.pumpAndSettle();

    expect(find.text('快速配置'), findsOneWidget);
    expect(find.text('自由探索 · 章节承接路线'), findsOneWidget);
    expect(find.text('确认地点，进入编辑器 →'), findsOneWidget);
    final CupertinoButton enter = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, '确认地点，进入编辑器 →'),
    );
    expect(enter.onPressed, isNull, reason: '没有一个真实点位时不能越过确认');
  });

  testWidgets('专业编辑器初始模式来自 Sheet，不再默认改回城市定向', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          publishApiProvider.overrideWithValue(_FakePublishApi()),
        ].cast(),
        child: const MaterialApp(home: PublishProPage(mode: 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自由探索'), findsWidgets);
  });

  testWidgets('专业编辑器接住快速配置的标题与点位', (WidgetTester tester) async {
    final PublishDraft initial = buildQuickPublishDraft(
      mode: 2,
      title: '静安夜游',
      description: '找到街区的暗号',
      nodes: const <ConfirmedNode>[
        ConfirmedNode(
          name: '武定路口',
          description: '找门牌',
          longitude: '121.45',
          latitude: '31.23',
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          publishApiProvider.overrideWithValue(_FakePublishApi()),
        ].cast(),
        child: MaterialApp(home: PublishProPage(initialDraft: initial)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('静安夜游'), findsOneWidget);
    expect(find.textContaining('武定路口'), findsWidgets);
  });
}
