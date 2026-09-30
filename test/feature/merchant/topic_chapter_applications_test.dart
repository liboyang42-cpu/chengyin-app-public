// 主办方侧:审商家的章节承接申请 + 邀商家来接。
//
// ★★ 两处「不许把没拿到说成没有」:
//   · 申请 status 缺席 → 说「状态未知」且**不摆通过/拒绝按钮**
//     (兜成 0 会摆出一对按钮,点下去撞的是服务端的状态校验);
//   · 可邀请名单为空时,措辞**不能**说成「确实没有可邀请的商家」——
//     服务端对「不是本主题发布者」也返回空列表,那句话我们并不知道真假。
//
// ★ 距离拿不到就整行不显示,绝不兜 0 ——「约 0 米」会让人以为就在隔壁。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/topic_chapter_applications_page.dart';
import '../../support/source_text.dart';

const int kTopic = 42;

Widget page({
  List<Map<String, dynamic>> applications = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> invitable = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> nodes = const <Map<String, dynamic>>[],
  MerchantApi? api,
}) {
  return ProviderScope(
    overrides: [
      topicChapterApplicationsProvider(
        kTopic,
      ).overrideWith((ref) async => applications),
      invitableMerchantsProvider(kTopic).overrideWith((ref) async => invitable),
      pendingChapterNodesProvider(kTopic).overrideWith((ref) async => nodes),
      if (api != null) merchantApiProvider.overrideWithValue(api),
    ],
    child: const MaterialApp(
      home: TopicChapterApplicationsPage(topicId: kTopic),
    ),
  );
}

Map<String, dynamic> row(Map<String, dynamic> j) => <String, dynamic>{
  'id': 1,
  'merchantName': '拐角咖啡',
  'chapterName': '第一章 · 咖啡',
  ...j,
};

Map<String, dynamic> node(Map<String, dynamic> j) => <String, dynamic>{
  'id': 1,
  'name': '静安咖啡',
  'address': '乌鲁木齐路 1 号',
  'description': '招牌手冲',
  ...j,
};

/// 点位审核必须真的打到 `auditChapterNode` —— 界面吞掉参数就等于没审。
class _FakeMerchantApi implements MerchantApi {
  final List<Map<String, dynamic>> audits = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> auditChapterNode({
    required int nodeId,
    required bool approve,
    String? reason,
  }) async {
    audits.add(<String, dynamic>{
      'nodeId': nodeId,
      'approve': approve,
      'reason': reason,
    });
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('★★ 审核按钮只给待审核的', () {
    testWidgets('status=0 → 通过/拒绝都在', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          applications: <Map<String, dynamic>>[
            row(<String, dynamic>{'status': 0}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-approve-1')), findsOneWidget);
      expect(find.byKey(const Key('owner-reject-1')), findsOneWidget);
    });

    testWidgets('拒绝理由用 Cupertino sheet 与系统键盘输入框', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          applications: <Map<String, dynamic>>[
            row(<String, dynamic>{'status': 0}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('owner-reject-1')));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byKey(const Key('owner-reject-reason')),
          matching: find.byType(CupertinoPageScaffold),
        ),
        findsOneWidget,
      );
      final CupertinoTextField field = tester.widget<CupertinoTextField>(
        find.byKey(const Key('owner-reject-reason')),
      );
      expect(field.textInputAction, TextInputAction.newline);
      expect(field.minLines, 3);
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const Key('owner-reject-confirm')),
            )
            .minimumSize,
        const Size.fromHeight(44),
      );
    });

    testWidgets('status=1 已通过 → 不摆按钮', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          applications: <Map<String, dynamic>>[
            row(<String, dynamic>{'status': 1}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-approve-1')), findsNothing);
      expect(find.byKey(const Key('owner-reject-1')), findsNothing);
      expect(find.text('已通过'), findsOneWidget);
    });

    testWidgets('★★ status 缺席 → 说「状态未知」,一个按钮都不摆', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          applications: <Map<String, dynamic>>[row(const <String, dynamic>{})],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('状态未知'),
        findsOneWidget,
        reason: '兜成"待审核"就是把不知道说成一个确定状态',
      );
      expect(find.byKey(const Key('owner-approve-1')), findsNothing);
      expect(find.byKey(const Key('owner-reject-1')), findsNothing);
    });

    testWidgets('邀请来的要单独说明 —— 它是我自己邀的,已预先批准', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          applications: <Map<String, dynamic>>[
            row(<String, dynamic>{'status': 1, 'source': 1}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('你邀请来的'), findsOneWidget);
    });
  });

  group('★★ 可邀请名单', () {
    testWidgets('空名单的措辞留了余地 —— 不是发布者时服务端也返回空', (WidgetTester tester) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('可邀请'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-invitable-empty')), findsOneWidget);
    });

    testWidgets('★ 距离缺席时整行不显示,不写「约 0 米」', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          invitable: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'memberId': 88,
              'name': '拐角咖啡',
              'chapterId': 7,
              'chapterName': '第一章 · 咖啡',
            },
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('可邀请'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-invitable-88-7')), findsOneWidget);
      expect(find.textContaining('约 0 米'), findsNothing);
      expect(find.textContaining('米'), findsNothing);
    });

    testWidgets('有距离时显示', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          invitable: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'memberId': 88,
              'name': '拐角咖啡',
              'chapterId': 7,
              'chapterName': '第一章 · 咖啡',
              'distance': 420.6,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('可邀请'));
      await tester.pumpAndSettle();
      expect(find.text('约 421 米'), findsOneWidget);
    });
  });

  group('★★ 点位待审(商家交上来的内容准入)', () {
    Future<void> openNodesTab(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('点位待审'));
      await tester.pumpAndSettle();
    }

    testWidgets('列表渲名字/地址/说明,通过与驳回都在', (WidgetTester tester) async {
      await tester.pumpWidget(
        page(
          nodes: <Map<String, dynamic>>[
            node(<String, dynamic>{
              'id': 1,
              'name': '静安咖啡',
              'address': '乌鲁木齐路 1 号',
              'description': '招牌手冲',
            }),
          ],
        ),
      );
      await openNodesTab(tester);

      expect(find.byKey(const Key('owner-node-1')), findsOneWidget);
      expect(find.text('静安咖啡'), findsOneWidget);
      expect(find.text('乌鲁木齐路 1 号'), findsOneWidget);
      expect(find.byKey(const Key('owner-node-approve-1')), findsOneWidget);
      expect(find.byKey(const Key('owner-node-reject-1')), findsOneWidget);
    });

    testWidgets('★★ 通过前必须说清「准入,非背书」—— 真源原话', (WidgetTester tester) async {
      final _FakeMerchantApi api = _FakeMerchantApi();
      await tester.pumpWidget(
        page(api: api, nodes: <Map<String, dynamic>>[node(<String, dynamic>{})]),
      );
      await openNodesTab(tester);

      await tester.tap(find.byKey(const Key('owner-node-approve-1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('不代表平台或主办方为商家背书'),
        findsOneWidget,
        reason: '只说「确认通过」会让人以为平台替商家做了担保',
      );

      await tester.tap(find.text('确认通过'));
      await tester.pumpAndSettle();

      expect(api.audits.single['nodeId'], 1);
      expect(api.audits.single['approve'], isTrue);
      expect(api.audits.single['reason'], isNull);
      expect(find.text('点位已通过'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★★ 驳回不写理由就按不动,填了才把 reason 发出去', (WidgetTester tester) async {
      final _FakeMerchantApi api = _FakeMerchantApi();
      await tester.pumpWidget(
        page(api: api, nodes: <Map<String, dynamic>>[node(<String, dynamic>{})]),
      );
      await openNodesTab(tester);

      await tester.tap(find.byKey(const Key('owner-node-reject-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-reject-reason')), findsOneWidget);
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const Key('owner-reject-confirm')),
            )
            .onPressed,
        isNull,
        reason: '空理由发出去,商家会收到一条什么都没说的驳回',
      );

      await tester.enterText(
        find.byKey(const Key('owner-reject-reason')),
        '照片看不清',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('owner-reject-confirm')));
      await tester.pumpAndSettle();

      expect(api.audits.single['approve'], isFalse);
      expect(api.audits.single['reason'], '照片看不清');
      expect(find.text('点位已驳回'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('★ 空态措辞留余地 —— 不说成「确实没人交」', (WidgetTester tester) async {
      await tester.pumpWidget(page());
      await openNodesTab(tester);
      expect(find.byKey(const Key('owner-pending-nodes-empty')), findsOneWidget);
      expect(find.textContaining('暂时没有待审的商家点位'), findsOneWidget);
    });

    testWidgets('★ 读失败 = 错误态,不许渲染成「没有待审」', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            topicChapterApplicationsProvider(
              kTopic,
            ).overrideWith((ref) async => const <Map<String, dynamic>>[]),
            invitableMerchantsProvider(
              kTopic,
            ).overrideWith((ref) async => const <Map<String, dynamic>>[]),
            pendingChapterNodesProvider(
              kTopic,
            ).overrideWith((ref) async => throw Exception('接口挂了')),
          ].cast(),
          child: const MaterialApp(
            home: TopicChapterApplicationsPage(topicId: kTopic),
          ),
        ),
      );
      await openNodesTab(tester);
      expect(find.text('待审点位没读出来'), findsOneWidget);
      expect(find.byKey(const Key('owner-pending-nodes-empty')), findsNothing);
    });
  });

  group('★ 源码上的两条硬约束', () {
    final String code = codeOf(
      'lib/feature/merchant/topic_chapter_applications_page.dart',
    );

    test('★★ 定位失败不许拦住可邀请名单 —— 服务端明确"不当错误"', () {
      // 取定位必须包在 try 里,失败时仍然发请求(只是不排距离)。
      expect(code.contains('currentMapLocationProvider'), isTrue);
      expect(
        code.contains('} catch (_) {'),
        isTrue,
        reason: '定位失败直接抛出去的话,整块可邀请名单会被一个可选参数拦死',
      );
    });

    test('拒绝必须能带理由 —— 只说「已拒绝」商家不知道改什么', () {
      expect(code.contains("Key('owner-reject-reason')"), isTrue);
      expect(code.contains('reason: reason'), isTrue);
    });
  });
}
