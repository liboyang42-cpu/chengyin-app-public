// 商家域整页快照。今天新建了 8 个商家页面,此前**一张图都没看过** ——
// 逻辑和文案反复验过,但"长什么样"完全没验。这份补上。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_merchant_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/chapter_application.dart';
import 'package:chengyin_app/data/models/merchant_city_node.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/data/models/merchant_ledger.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/feature/merchant/merchant_chapters_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/merchant/merchant_ledger_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';
import '../feature/merchant/merchant_access_fixtures.dart';
import '../support/fake_crm_console_api.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      // ★ 必须用商家浅色主题 —— 路由那边就是这么包的(app_router.dart:_merchantLight)。
      theme: merchantGoldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

/// ★ [goldenPath] 必须是**字面量**,别在这里拼 `'goldens/$name.png'` ——
/// `no_orphan_goldens_test` 靠在测试源码里找文件名字面量来判断基线有没有人引用,
/// 插值出来的名字它一个都看不见,8 张图会全被判成孤儿(2026-08-19 实撞)。
Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('商家工作台:有数据', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // ★ 工作台的根是 `/api/merchant/access/me`(2026-09-19):岗位决定
        //   这一页摆什么。给店主全权限,拍出来才是「一个人能看到的满配工作台」。
        merchantAccessProvider.overrideWith((ref) async => ownerAccess()),
        // 消息角标同理:merchantUnreadProvider 也会真发请求。
        //   给 3 条未读,顺便把角标拍进基准图。
        merchantUnreadProvider.overrideWith((ref) async => 3),
        // ★ 工作台新增的「最新动态」块会**真发请求** ——
        //   不给替身的话这张基准图打的是真网络(实测抛
        //   MissingPluginException:secure_storage 在测试里没有实现)。
        //   顺便把这块拍进图:只让它消失等于没验证过它。
        merchantEventsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{'content': '静安咖啡 核销 1 张', 'time': '10:24'},
            <String, dynamic>{'content': '结算到账 ¥38.50', 'time': '昨天'},
          ],
        ),
        merchantDashboardProvider.overrideWith(
          (ref) async => MerchantDashboard.fromJson(<String, dynamic>{
            'revenue': '12840.00',
            'pendingOrders': 3,
            'revenue7d': <dynamic>[
              <String, dynamic>{'date': '13', 'amount': '320.00'},
              <String, dynamic>{'date': '14', 'amount': '880.00'},
              <String, dynamic>{'date': '15', 'amount': '0.00'},
              <String, dynamic>{'date': '16', 'amount': '1240.00'},
              <String, dynamic>{'date': '17', 'amount': '640.00'},
              <String, dynamic>{'date': '18', 'amount': '1580.00'},
              <String, dynamic>{'date': '19', 'amount': '420.00'},
            ],
          }),
        ),
        // ★ 营业状态现在是读回来的 —— 拍图必须给它一个确定值,
        //   否则拍到的是「状态读取中…」那一帧,基准图就成了假证据。
        businessStatusProvider.overrideWith(
          (ref) async => (open: true, text: '营业中'),
        ),
        merchantTodoProvider.overrideWith(
          (ref) async => MerchantTodo.fromJson(<String, dynamic>{
            'pendingVerify': 2,
            'pendingOrders': 3,
            'verifiedCount': 41,
          }),
        ),
        // ★ 工作台新增的「我的项目」块也**真发请求**(2026-09-17):
        //   少给一个替身,基准图打的就是真网络 —— dio 的超时 Timer 会活过
        //   widget 树,这条 golden 直接红在「A Timer is still pending」,
        //   跟像素没关系。三个替身缺一不可。
        merchantJoinedProjectsProvider.overrideWith(
          (ref) async => const <TopicRegistration>[
            TopicRegistration(
              id: 410,
              topicId: 91,
              topicName: '我承接的夜游',
              status: 1,
            ),
          ],
        ),
        merchantHostedProjectsProvider.overrideWith(
          (ref) async => const <MyProject>[
            MyProject(id: 52, bizType: 'topic', title: '我主办的主题'),
          ],
        ),
        gameSessionApiProvider.overrideWithValue(
          const _OfflineGameGateway(),
        ),
      ], const MerchantHomePage()),
      'goldens/merchant_home.png',
    );
  });

  testWidgets('★ 商家工作台:还不是商家(身份态,不是错误)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // 「还不是商家」现在是**身份态**读出来的:access/me 回了 active=false +
        // applicationState=NONE(名下没有申请行),不是 dashboard 抛「商家信息不存在」。
        merchantAccessProvider.overrideWith(
          (ref) async => noApplicationAccess(),
        ),
        merchantDashboardProvider.overrideWith(
          (ref) async => throw MerchantApiException('商家信息不存在'),
        ),
        // 未入驻态也会渲 AppBar 的消息角标 —— 同样要替身。
        // ★ 这里给 null(拿不到未读数),顺便验证「拿不到时不显示角标」。
        merchantUnreadProvider.overrideWith((ref) async => null),
      ], const MerchantHomePage()),
      'goldens/merchant_home_not_merchant.png',
    );
  });

  testWidgets('★ 台账:金额四态同屏(破折号/待定/正数/退款中)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // 「退款售后」入口读 /api/merchant/access/me;这张基线图只画金额四态,
        // 不注入能力位(不注入会真发请求 → 测试里留 pending timer)。入口本身
        // 由 merchant_finance_entry_parity_test 的行为用例覆盖。
        merchantAftercareEntryProvider.overrideWith((ref) async => false),
        merchantRedemptionsProvider('all').overrideWith(
          (ref) async => MerchantRedemptionPage.fromJson(<String, dynamic>{
            'summary': <String, dynamic>{
              'count': 12,
              'pendingAmount': '340.00',
              // arrivedAmount 故意缺席 → 应显示破折号
            },
            'rows': <dynamic>[
              <String, dynamic>{
                'recordKey': 'a',
                'topicName': '夜跑咖啡',
                'chapterName': '第一章',
                'storeName': '静安店',
                'settlementAmount': '38.50',
                'displayState': 'SETTLED',
              },
              <String, dynamic>{
                'recordKey': 'b',
                'topicName': '晨间面包',
                'settlementAmount': null,
                'displayState': 'PENDING_SETTLEMENT',
              },
              <String, dynamic>{
                'recordKey': 'c',
                'topicName': '免费体验局',
                'settlementAmount': '0.00',
                'displayState': 'NO_CASH_SETTLEMENT',
                'noCashReason': '该章节为免费体验',
              },
              <String, dynamic>{
                'recordKey': 'd',
                'topicName': '退款中的一单',
                'settlementAmount': '-20.00',
                'displayState': 'SETTLED',
                'refundState': 'REFUNDING',
              },
            ],
          }),
        ),
      ], const MerchantLedgerPage()),
      'goldens/merchant_ledger.png',
    );
  });

  testWidgets('★ 营销:券没人领过(核销率整行不显示)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // 营销首页现在先过一道 access/me(没 marketing:read 就不发那一枪),
        // 不桩这一层快照会发真请求。
        merchantAccessProvider.overrideWith((ref) async => marketingAccess()),
        merchantMarketingProvider.overrideWith(
          (ref) async => MerchantMarketing.fromJson(<String, dynamic>{
            'coupons': <String, dynamic>{
              'couponCount': 2,
              'received': 0,
              'verified': 0,
            },
            'content': <String, dynamic>{
              'topicCount': 3,
              'freeExploreCount': 1,
              'activityCount': 5,
            },
            'funnel': <dynamic>[
              <String, dynamic>{'step': '曝光', 'count': 1240, 'rate': '1'},
              <String, dynamic>{'step': '进店', 'count': 320, 'rate': '0.258'},
              <String, dynamic>{'step': '核销', 'count': 41, 'rate': '0.033'},
            ],
          }),
        ),
      ], const MerchantMarketingPage()),
      'goldens/merchant_marketing.png',
    );
  });

  testWidgets('★ 成为节点:配额用满', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        cityNodesProvider.overrideWith(
          (ref) async => CityNodeHome.fromJson(<String, dynamic>{
            'used': 3,
            'max': 3,
            'nodes': <dynamic>[
              <String, dynamic>{
                'poiId': 1,
                'name': '静安咖啡',
                'templateTitle': '城市暗号',
                'tags': '咖啡 · 漫游',
                'validationMethod': 4,
                'status': 1,
              },
              <String, dynamic>{
                'poiId': 2,
                'name': '徐汇书店',
                'templateTitle': '书店问答',
                'validationMethod': 3,
                'status': 0,
              },
            ],
            'applications': <dynamic>[
              <String, dynamic>{
                'id': 9,
                'name': '虹口面包房',
                'applicationType': 2,
                'auditStatus': 2,
                'auditReason': '地址与营业执照不符',
              },
            ],
          }),
        ),
      ], const MerchantCityNodePage()),
      'goldens/merchant_city_nodes.png',
    );
  });

  testWidgets('客户名册:含不给手机号的一条', (WidgetTester tester) async {
    final String sixDaysAgo = DateTime.now()
        .subtract(const Duration(days: 6, hours: 1))
        .toIso8601String();
    await _shot(
      tester,
      _app([
        // 能力位(`/api/merchant/access/me`)与名册 / 分群 / 券 / 触达历史都得桩:
        // ★ 不桩的话这一页会在快照里发真请求,留下 pending timer 把用例判红
        //   (和「图不一样」是两回事,别混淆)。
        merchantCrmAccessProvider.overrideWith(
          (ref) async => const MerchantCrmAccess(
            active: true,
            canReadCrm: true,
            canSegmentCrm: true,
            canExportCrm: true,
            canWriteMarketing: true,
            canManageCoupons: true,
          ),
        ),
        merchantCrmConsoleApiProvider.overrideWithValue(
          FakeCrmConsoleApi(
            page: FakeCrmConsoleApi.pageOf(
              <Map<String, dynamic>>[
                FakeCrmConsoleApi.rowJson(
                  name: '张三',
                  tier: 'repeat',
                  lastTime: sixDaysAgo,
                  lastAction: '核销了夜跑咖啡路线',
                ),
                // ★ 不给手机号的那条:行上要说清「为什么不给」,不是留白。
                //   (空名字的行会被 fail-closed 拦在页面外,这里拍不出来。)
                FakeCrmConsoleApi.rowJson(
                  memberId: 43,
                  name: '林青',
                  phone: null,
                  contactHint: '客户未授权手机号',
                  latestNote: '想报下个月的夜跑',
                  tier: 'new',
                  sourceType: 'ACTIVITY',
                  lastTime: sixDaysAgo,
                  lastAction: '报名了城市定向',
                ),
              ],
              segmentCounts: <String, dynamic>{'all': 12, 'monthlyNew': 3},
            ),
          ),
        ),
      ], const MerchantCustomerPage()),
      'goldens/merchant_customers.png',
    );
  });

  testWidgets('承接申请:三种状态同屏', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        myChapterApplicationsProvider.overrideWith(
          (ref) async => <ChapterApplication>[
            ChapterApplication.fromJson(<String, dynamic>{
              'id': 1,
              'topicName': '夜跑咖啡',
              'chapterName': '第一章',
              'status': 0,
            }),
            // ★ 主办方邀请 —— 文案要与"已通过"不同
            ChapterApplication.fromJson(<String, dynamic>{
              'id': 2,
              'topicName': '晨间面包',
              'status': 1,
              'source': 1,
            }),
            ChapterApplication.fromJson(<String, dynamic>{
              'id': 3,
              'topicName': '午后书店',
              'status': 2,
              'auditRemark': '门店照片不清晰',
            }),
          ],
        ),
      ], const MerchantChaptersPage()),
      'goldens/merchant_chapters.png',
    );
  });

  testWidgets('合作中心:可承接列表', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        recruitingRoutesProvider.overrideWith(
          (ref) async => <RecruitingRoute>[
            RecruitingRoute.fromJson(<String, dynamic>{
              'id': 1,
              'name': '静安夜跑路线',
              'merchantSignUpEndDate': '2026-09-30 23:59:59',
            }),
            // ★ 没给截止日 —— 那一行不该显示
            RecruitingRoute.fromJson(<String, dynamic>{
              'id': 2,
              'name': '徐汇咖啡巡礼',
            }),
          ],
        ),
      ], const MerchantCoopPage()),
      'goldens/merchant_coop.png',
    );
  });
}

/// golden 里只为了「不发请求」—— 除 loadMerchantEntries 外都不该被调到。
class _OfflineGameGateway implements GameSessionGateway {
  const _OfflineGameGateway();

  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async =>
      const <MerchantGameEntry>[];

  @override
  Future<MerchantGameProjection> loadMerchantView({required int activityId}) =>
      throw UnimplementedError('golden 不验这条');

  @override
  Future<GameSessionReceipt> submitAndReadReceipt(GameSessionCommand command) =>
      throw UnimplementedError('golden 不验这条');

  @override
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) => throw UnimplementedError('golden 不验这条');
}
