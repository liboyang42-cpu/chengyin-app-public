// 商家 CRM 运营台 —— 客户名册 / 批量标签 / 分群 / 合规触达。
//
// ★★ 判据是「用户在这一页点得到」,不是「接口方法已加」:
//   每条用例都从**界面**点进去,再看请求发没发、发了几次、发的是什么。
//   依据 = 小程序只读快照 `pages/merchant/customer/index.js`(行号见各条注释)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';

import '../../golden/golden_theme.dart';
import '../../support/fake_crm_console_api.dart';

/// 全套能力(店主的岗位)。**不是默认值** —— 默认全 false 是员工岗。
const MerchantCrmAccess _fullAccess = MerchantCrmAccess(
  active: true,
  canReadCrm: true,
  canSegmentCrm: true,
  canExportCrm: true,
  canWriteMarketing: true,
  canManageCoupons: true,
);

Widget _app(FakeCrmConsoleApi api, {MerchantCrmAccess access = _fullAccess}) {
  return ProviderScope(
    // ★ 同一条用例里连着 pump 两棵树时:不带 key 会复用同一个 State,
    //   initState 不再跑 —— 第二棵树看起来"没加载"。给每棵树一个新身份。
    key: UniqueKey(),
    // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
    overrides: [
      merchantCrmAccessProvider.overrideWith((ref) async => access),
      merchantCrmConsoleApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      theme: merchantGoldenTheme(),
      home: const MerchantCustomerPage(),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  // 触达面板张开后这一页很高,矮视口会先撞 RenderFlex 溢出而不是撞判据。
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(CyNativeNotice.hide);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Finder _field(String placeholder) => find.byWidgetPredicate(
  (Widget w) => w is CupertinoTextField && w.placeholder == placeholder,
  description: '输入框「$placeholder」',
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String label) =>
    _tap(tester, find.text(label));

/// 名册里有一位客户(选人 / 拨号类判据要有行可点)。
FakeCrmConsoleApi _withRows() => FakeCrmConsoleApi(
  page: FakeCrmConsoleApi.pageOf(<Map<String, dynamic>>[
    FakeCrmConsoleApi.rowJson(),
  ]),
);

/// 点弹窗里的按钮。半屏底部也有一个「发送」,`find.text` 会撞两个 —— 只认弹窗里那个。
Future<void> _tapInDialog(WidgetTester tester, String label) async {
  final Finder target = find.descendant(
    of: find.byType(CupertinoAlertDialog),
    matching: find.text(label),
  );
  expect(target, findsOneWidget, reason: '弹窗里应有「$label」');
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('能力位(快照 loadAccess)', () {
    testWidgets('★★ 没有客户查看权限:说清是岗位问题,且一次名册请求都不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(
        tester,
        _app(api, access: const MerchantCrmAccess(active: true)),
      );

      expect(find.text('当前岗位没有客户查看权限'), findsOneWidget);
      expect(
        api.queries,
        isEmpty,
        reason: '没权限还去打名册 = 每进一次页面白挨一个 403',
      );
    });

    testWidgets('★★ 有读没写:批量标签 / 合规触达 / 导出三个入口都不摆', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(
        tester,
        _app(
          api,
          access: const MerchantCrmAccess(active: true, canReadCrm: true),
        ),
      );
      expect(api.queries.length, 1, reason: '能读就把名册拉起来');

      await _tapText(tester, '管理');
      expect(find.text('更多筛选'), findsOneWidget);
      expect(find.text('批量标签'), findsNothing);
      expect(find.text('合规触达'), findsNothing);
      expect(
        find.text('导出'),
        findsNothing,
        reason: '没有 canExportCrm 的岗位点导出必被后端拒',
      );
    });

    testWidgets('★ 没有券管理能力:触达面板不给「商家优惠券」渠道', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi(
        segmentRows: <CrmSavedSegment>[
          const CrmSavedSegment(id: 5, name: '复购客'),
        ],
      );
      await _pump(
        tester,
        _app(
          api,
          access: const MerchantCrmAccess(
            active: true,
            canReadCrm: true,
            canWriteMarketing: true,
            // canManageCoupons 明确 false
          ),
        ),
      );

      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');

      expect(find.text('客户合规触达'), findsOneWidget);
      expect(find.text('站内活动消息'), findsOneWidget);
      expect(
        find.text('商家优惠券'),
        findsNothing,
        reason: '选不了券也不该摆一个点下去只能撞「请选择有效优惠券」的渠道',
      );
    });
  });

  group('搜索与分段(快照 _customerQuery)', () {
    testWidgets('★ 输入走 300ms 防抖:窗口里一个请求都不发,到点只发一次', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));
      expect(api.queries.length, 1, reason: '首屏一页');

      await tester.enterText(_field('搜索姓名或手机号'), '张');
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.queries.length, 1, reason: '还在防抖窗口里,每敲一个字打一次接口既浪费、回来还可能乱序');

      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      expect(api.queries.length, 2);
      expect(api.queries.last.keyword, '张');
      expect(api.queries.last.pageNum, 1, reason: '换关键词要回到第一页');
    });

    testWidgets('★ 回车立即搜,不干等防抖', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));

      await tester.enterText(_field('搜索姓名或手机号'), '林');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(api.queries.length, 2);
      expect(api.queries.last.keyword, '林');
    });

    testWidgets('★ 点「回头客」chip:请求带 segment=repeat', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));

      await _tapText(tester, '回头客');

      expect(api.queries.last.segment, 'repeat');
      expect(api.queries.last.pageNum, 1);
    });
  });

  group('批量打标签(快照 submitBatchTag / index.js:750)', () {
    testWidgets('★★ 校验:没选客户 / 空标签名都不许发请求', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '批量标签');

      expect(find.text('已选 0 / 100'), findsOneWidget);
      await _tapText(tester, '添加');
      expect(find.text('请先选择客户'), findsOneWidget);

      await _tapText(tester, '张三');
      expect(find.text('已选 1 / 100'), findsOneWidget);
      await _tapText(tester, '添加');
      expect(find.text('请输入1至16字标签名称'), findsOneWidget);

      expect(
        api.batchTags,
        isEmpty,
        reason: '本地就能判的错不该打后端;打了等于拿 400 换一句提示',
      );
    });

    testWidgets('★★ 选中 → 填名 → 提交:请求体是选中的人 + 幂等号,成功后清空并重取名册', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '批量标签');

      await _tapText(tester, '张三');
      await tester.enterText(_field('输入标签名称'), '夜跑常客');
      final int queriesBefore = api.queries.length;
      await _tapText(tester, '添加');

      expect(api.batchTags.length, 1);
      expect(api.batchTags.single.ids, <int>[42]);
      expect(api.batchTags.single.tagName, '夜跑常客');
      expect(
        api.batchTags.single.requestId.startsWith('crm-batch-tag-'),
        isTrue,
        reason: '后端按 requestId 幂等(快照 createRequestId)',
      );
      expect(find.text('标签已添加'), findsOneWidget);
      expect(
        _field('输入标签名称'),
        findsNothing,
        reason: '打完了要退出选择态(批量条整条收掉),不然下一批会带着上一批的人',
      );
      expect(
        api.queries.length,
        queriesBefore + 1,
        reason: '标签要出现在行上,得把名册重取一遍',
      );
    });

    testWidgets('★ 再点一次 = 取消选择', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '批量标签');

      await _tapText(tester, '张三');
      expect(find.text('已选 1 / 100'), findsOneWidget);
      await _tapText(tester, '张三');
      expect(find.text('已选 0 / 100'), findsOneWidget);
    });
  });

  group('保存分群(快照 saveCurrentSegment / index.js:779)', () {
    testWidgets('★★ 保存:filter 是当前筛选(全部折成 null),成功后重拉分群列表', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '更多筛选');

      // 先把筛选改成「回头客」,保存的 filter 必须跟着变。
      await _tapText(tester, '回头客');
      await tester.enterText(_field('命名当前筛选'), '回头客们');
      await _tap(tester, find.ancestor(
        of: find.text('保存分群'),
        matching: find.byType(CupertinoButton),
      ));

      expect(api.savedSegments.length, 1);
      expect(api.savedSegments.single.name, '回头客们');
      expect(api.savedSegments.single.filter.segment, 'repeat');
      expect(
        api.savedSegments.single.requestId.startsWith('crm-segment-'),
        isTrue,
      );
      expect(find.text('分群已保存'), findsOneWidget);
    });

    testWidgets('★★ 名称为空:提示且一个请求都不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '更多筛选');

      await _tap(tester, find.ancestor(
        of: find.text('保存分群'),
        matching: find.byType(CupertinoButton),
      ));

      expect(find.text('请输入1至30字分群名称'), findsOneWidget);
      expect(api.savedSegments, isEmpty);
    });
  });

  group('合规触达(快照 previewCampaign / submitCampaign / index.js:926,962,988)', () {
    FakeCrmConsoleApi seeded() => FakeCrmConsoleApi(
      segmentRows: <CrmSavedSegment>[
        const CrmSavedSegment(id: 5, name: '复购客'),
      ],
    );

    testWidgets('★★ 预览:请求体只有 segmentId + channel(不带客户端名单)', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      await _tapText(tester, '预览人数');

      expect(api.previews.length, 1);
      expect(api.previews.single.segmentId, 5);
      expect(api.previews.single.channel, 'IN_APP');
      expect(find.text('分群 12 人（单次上限 200）'), findsOneWidget);
      expect(find.text('本次预计可触达 9 人'), findsOneWidget);
    });

    testWidgets('★ 分群读失败:触达面板里也要说清并给重试', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded()
        ..failures['segments'] = '网络连接失败，保存分群未更新';
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');

      // 触达用的分群就是「已保存分群」那一份:读不到还让人点空选择器最坏。
      expect(find.text('保存分群暂未更新'), findsOneWidget);
      expect(find.text('网络连接失败，保存分群未更新'), findsOneWidget);
    });

    testWidgets('★★ 创建并发送要先过二次确认:取消 = 一个请求都不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      await tester.enterText(_field('触达标题'), '周末夜跑提醒');
      await tester.enterText(_field('触达内容（不填写手机号等敏感信息）'), '本周六晚 7 点,老地方集合。');
      await _tapText(tester, '创建并发送');

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('确认发送?'), findsOneWidget);
      await _tapText(tester, '取消');

      expect(api.creates, isEmpty);
      expect(api.dispatches, isEmpty, reason: '群发不可撤回,没确认就发等于误触一次事故');
    });

    testWidgets('★★ 确认后:先创建再投放,参数与顺序都对', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      await tester.enterText(_field('触达标题'), '周末夜跑提醒');
      await tester.enterText(_field('触达内容（不填写手机号等敏感信息）'), '本周六晚 7 点,老地方集合。');
      await _tapText(tester, '创建并发送');
      await _tapText(tester, '发送');

      expect(api.creates.length, 1);
      expect(api.creates.single.segmentId, 5);
      expect(api.creates.single.channel, 'IN_APP');
      expect(api.creates.single.couponId, isNull, reason: '站内消息不带券');
      expect(api.creates.single.title, '周末夜跑提醒');
      expect(api.creates.single.content, '本周六晚 7 点,老地方集合。');
      expect(
        api.creates.single.requestId.startsWith('crm-campaign-'),
        isTrue,
      );
      expect(api.dispatches, <int>[7], reason: '创建拿到 id 之后才投放');
      expect(find.text('发送成功'), findsOneWidget);
    });

    testWidgets('★★ 发送后重拉历史失败:屏上已有的历史不许被清掉', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi(
        segmentRows: <CrmSavedSegment>[
          const CrmSavedSegment(id: 5, name: '复购客'),
        ],
        campaignRows: <CrmCampaignTask>[
          CrmCampaignTask.tryParse(<String, dynamic>{
            'id': 21,
            'status': 'SUCCESS',
            'title': '上次的夜跑提醒',
            'recipientCount': 12,
            'deliveredCount': 12,
          })!,
        ],
      );
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      expect(find.text('上次的夜跑提醒'), findsOneWidget);

      // 发送成功后页面会重拉一次历史(快照同序)—— 这一次让它失败。
      api.failures['campaigns'] = '网络连接失败，触达历史未更新';
      await tester.enterText(_field('触达标题'), '周末夜跑提醒');
      await tester.enterText(_field('触达内容（不填写手机号等敏感信息）'), '本周六晚 7 点。');
      await _tapText(tester, '创建并发送');
      await _tapText(tester, '发送');

      expect(
        find.text('上次的夜跑提醒'),
        findsOneWidget,
        reason: '刷新失败是「这次没更新」,不是「没有历史」—— 清屏会让人以为历史丢了'
            '(快照 index.js:1020 的形状不对就 return,保留旧数据)',
      );
    });

    testWidgets('★★ 重试只在「部分完成 + 还有可重试的人」时才摆,点了打对 id', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded()
        ..task = CrmCampaignTask.tryParse(<String, dynamic>{
          'id': 7,
          'status': 'PARTIAL_FAILED',
          'recipientCount': 12,
          'deliveredCount': 9,
          'failedCount': 3,
          'retryableCount': 3,
        })!;
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      await tester.enterText(_field('触达标题'), '周末夜跑提醒');
      await tester.enterText(_field('触达内容（不填写手机号等敏感信息）'), '本周六晚 7 点。');
      await _tapText(tester, '创建并发送');
      await _tapText(tester, '发送');

      expect(find.text('部分完成'), findsOneWidget);
      await _tapText(tester, '重试可重试 3 人');
      expect(api.retries, <int>[7]);
    });

    testWidgets('★★ 全部完成时不摆重试(点了必被后端拒)', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded();
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');
      await tester.enterText(_field('触达标题'), '周末夜跑提醒');
      await tester.enterText(_field('触达内容（不填写手机号等敏感信息）'), '本周六晚 7 点。');
      await _tapText(tester, '创建并发送');
      await _tapText(tester, '发送');

      expect(find.text('发送成功'), findsOneWidget);
      expect(find.textContaining('重试可重试'), findsNothing);
    });

    testWidgets('★ 历史里点一条:读它的回执(GET campaigns/{id})', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = seeded()
        ..campaignRows = <CrmCampaignTask>[
          CrmCampaignTask.tryParse(<String, dynamic>{
            'id': 8,
            'title': '周末提醒',
            'recipientCount': 12,
            'deliveredCount': 12,
          })!,
        ];
      await _pump(tester, _app(api));
      await _tapText(tester, '管理');
      await _tapText(tester, '合规触达');

      await _tapText(tester, '周末提醒');

      expect(api.details, <int>[8]);
    });
  });

  group('空态四档(快照 _emptyCopy —— 四句文案不能糊成一句)', () {
    testWidgets('★★ 搜不到 / 这一段没人 / 一个客户都没有:三档各不相同', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi();
      await _pump(tester, _app(api));
      expect(find.text('还没有客户'), findsOneWidget, reason: '一个客户都没有 → 指路合作中心');

      await tester.enterText(_field('搜索姓名或手机号'), '张');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();
      expect(find.text('没搜到这个客户'), findsOneWidget);
      expect(find.text('换个姓名再试试'), findsOneWidget);

      await _tapText(tester, '清除搜索');
      await _tapText(tester, '回头客');
      expect(find.text('暂时没有回头客客户'), findsOneWidget);
    });

    testWidgets('★★ 有统计没名单 / 连统计都没有:两档各说各的,不用 0 冒充', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi(
        page: FakeCrmConsoleApi.pageOf(
          const <Map<String, dynamic>>[],
          total: 12,
          segmentCounts: <String, dynamic>{'all': 12},
        ),
      );
      await _pump(tester, _app(api));
      expect(find.text('客户名单这次没取回来'), findsOneWidget);
      expect(find.textContaining('统计里有 12 位客户'), findsOneWidget);

      final FakeCrmConsoleApi noCounts = FakeCrmConsoleApi(
        page: FakeCrmConsoleApi.pageOf(
          const <Map<String, dynamic>>[],
          total: 0,
          segmentCounts: const <String, dynamic>{},
        ),
      );
      await _pump(tester, _app(noCounts));
      expect(find.text('客户统计暂未取到'), findsOneWidget);
      expect(
        find.textContaining('不会用 0 代替缺失的客户计数'),
        findsOneWidget,
      );
    });
  });
  group('定向广播(快照 cu-cast)', () {
    testWidgets('★★ 底栏入口:说清发给「当前筛选这批人」,点开是半屏', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));

      expect(find.byKey(const Key('merchant-crm-cast')), findsOneWidget);
      expect(find.text('当前筛选 · 1 人'), findsOneWidget);
      expect(
        find.text('只发这批人,不是全场广播'),
        findsOneWidget,
        reason: '商家点之前就得知道发给谁,不是「一键全场」',
      );

      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      expect(
        find.text('定向广播'),
        findsNWidgets(2),
        reason: '底栏入口 + 半屏标题各一处 = 半屏真弹起来了',
      );
      expect(
        find.text('1 人 · 点发送先核一遍可触达人数'),
        findsOneWidget,
        reason: '草稿期只给估算,真值等服务端预览',
      );
    });

    testWidgets('★★ 没有营销权限:底栏整个不出现', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(
        tester,
        _app(
          api,
          access: const MerchantCrmAccess(active: true, canReadCrm: true),
        ),
      );

      expect(find.byKey(const Key('merchant-crm-cast')), findsNothing);
    });

    testWidgets('★★ 预览请求体 = 当前筛选;取消 = 一个 send 都不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));
      await tester.enterText(_field('搜索姓名或手机号'), '张');
      await tester.pumpAndSettle();

      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '本周六晚 7 点,老地方集合。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');

      expect(api.broadcastPreviews.length, 1);
      expect(api.broadcastPreviews.single.scope, 'ALL');
      expect(api.broadcastPreviews.single.keyword, '张');
      expect(api.broadcastPreviews.single.groups, isEmpty);
      expect(
        find.textContaining('将发送给 10 位已同意接收商家消息的客户'),
        findsWidgets,
        reason: '预览文案必须来自服务端真值,不是本地估算',
      );
      expect(
        find.textContaining('发送后无法撤回。'),
        findsOneWidget,
        reason: '确认框要说清这一发撤不回来',
      );

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await _tapText(tester, '再想想');
      expect(
        api.broadcasts,
        isEmpty,
        reason: '广播不可撤回,没确认就发等于误触一次事故',
      );
    });

    testWidgets('★★ 确认后发送:内容按输入的原文,requestId 带 crm-broadcast- 前缀', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows();
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '本周六晚 7 点,老地方集合。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');
      await _tapInDialog(tester, '发送');

      expect(api.broadcasts.length, 1);
      expect(api.broadcasts.single.content, '本周六晚 7 点,老地方集合。');
      expect(
        api.broadcasts.single.requestId.startsWith('crm-broadcast-'),
        isTrue,
      );
      expect(find.text('已发送'), findsOneWidget);
    });

    testWidgets('★★ 队伍分组:人数就地从名单聚合,选谁发谁', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = FakeCrmConsoleApi(
        page: FakeCrmConsoleApi.pageOf(<Map<String, dynamic>>[
          FakeCrmConsoleApi.rowJson(name: '张三')..['teamName'] = '夜跑队',
          FakeCrmConsoleApi.rowJson(memberId: 43, name: '李四')
            ..['teamName'] = '夜跑队',
          FakeCrmConsoleApi.rowJson(memberId: 44, name: '王五')
            ..['teamName'] = '骑行队',
        ]),
      );
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await _tapText(tester, '队伍');

      expect(find.text('夜跑队'), findsOneWidget);
      expect(find.text('2 人'), findsOneWidget);
      await _tapText(tester, '夜跑队');
      expect(find.text('还没选'), findsNothing);

      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');

      expect(api.broadcastPreviews.single.scope, 'TEAM');
      expect(api.broadcastPreviews.single.groups, <String>['夜跑队']);
    });

    testWidgets('★★ 今天的额度用完:说清每天几条,且不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows()
        ..broadcastPreview = const CrmBroadcastPreview(
          audienceCount: 30,
          consentedCount: 12,
          noConsentCount: 18,
          frequencyLimitedCount: 0,
          deliverableCount: 10,
          recipientLimit: 500,
          merchantDailyLimit: 3,
          merchantDailyUsed: 3,
          merchantDailyRemaining: 0,
          filterTotalCount: 30,
        );
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');

      expect(find.text('今天的广播次数用完了'), findsOneWidget);
      expect(find.textContaining('每天最多发 3 条广播'), findsOneWidget);
      expect(api.broadcasts, isEmpty);
    });

    testWidgets('★★ 这批人现在收不到:说清原因(未同意/已收过),且不发', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows()
        ..broadcastPreview = const CrmBroadcastPreview(
          audienceCount: 30,
          consentedCount: 0,
          noConsentCount: 30,
          frequencyLimitedCount: 4,
          deliverableCount: 0,
          recipientLimit: 500,
          merchantDailyLimit: 3,
          merchantDailyUsed: 0,
          merchantDailyRemaining: 3,
          filterTotalCount: 30,
        );
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');

      expect(find.text('这批客户现在收不到'), findsOneWidget);
      expect(find.textContaining('将发送给 0 位'), findsWidgets);
      expect(
        find.textContaining('另有 4 位今日已收到过'),
        findsWidgets,
        reason: '频控要跟「未同意」分开说,不然商家以为客户全跑了',
      );
      expect(api.broadcasts, isEmpty);
    });

    testWidgets('★ 预览失败:半屏里说清失败的是预览,还能原地重试', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows()
        ..failures['previewBroadcast'] = '网络连接失败，广播预览未更新';
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');

      expect(find.text('网络连接失败，广播预览未更新'), findsOneWidget);
      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: '预览都没出结果就弹确认,商家是在瞎确认',
      );
      expect(api.broadcasts, isEmpty);
    });

    testWidgets('★★ 发送失败后重试:复用同一个 requestId,不会多发一条', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows()
        ..failures['sendBroadcast'] = '网络连接失败，广播未发出';
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');
      await _tapInDialog(tester, '发送');
      expect(find.text('网络连接失败，广播未发出'), findsOneWidget);

      api.failures.remove('sendBroadcast');
      await _tapText(tester, '发送');
      await _tapInDialog(tester, '发送');

      expect(api.broadcasts.length, 2);
      expect(
        api.broadcasts[1].requestId,
        api.broadcasts[0].requestId,
        reason: '同一份草稿重试要复用同一个幂等号,否则服务端会当成两条',
      );
      expect(find.text('已发送'), findsOneWidget);
    });

    testWidgets('★★ 结果块只认服务端回执:四个数都来自回执', (WidgetTester tester) async {
      final FakeCrmConsoleApi api = _withRows()
        ..broadcastResult = const CrmBroadcastResult(
          id: 9,
          status: 'PARTIAL_FAILED',
          audienceCount: 30,
          consentedCount: 12,
          noConsentCount: 18,
          frequencySkippedCount: 2,
          deliveredCount: 9,
          failedCount: 1,
        );
      await _pump(tester, _app(api));
      await _tap(tester, find.byKey(const Key('merchant-crm-cast')));
      await tester.enterText(
        _field('第 3 站商家临时排队,先去第 4 站,回头再补。'),
        '周六见。',
      );
      await tester.pumpAndSettle();
      await _tapText(tester, '发送');
      await _tapInDialog(tester, '发送');

      expect(find.text('部分送达'), findsOneWidget);
      expect(find.text('送达 9 位 · 未同意跳过 18 位'), findsOneWidget);
      expect(find.text('今日已收跳过 2 位 · 失败 1 位'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });
  });
}
