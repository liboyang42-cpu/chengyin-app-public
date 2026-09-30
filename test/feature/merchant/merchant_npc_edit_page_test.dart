// 门店形象的落点页(`/api/merchant/npc/profile` 的**唯一** App 调用方)。
//
// ★★ 这条接口的坑不在参数,在**可达性**:`MerchantNpcApi.myProfile()` 从
//   2026-08 就存在,但真正把它接进页面的只有这一页 —— 方法在了不等于
//   商家点得到,所以这里钉住「打开页 = 拉一次 profile」。
//
// ★ 另一条口径:拉不到时必须降级成**不给入口**,不是给一个点了必失败的入口。
//   声音/3D 两个开关各自 try/catch,一个挂了不许拖垮另一个。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_edit_page.dart';

class _FakeNpcApi implements MerchantNpcApi {
  _FakeNpcApi({
    this.profile = const MerchantNpcProfile(),
    this.failProfile = false,
    this.voiceAvailable = false,
  });

  final MerchantNpcProfile profile;
  final bool failProfile;
  final bool voiceAvailable;

  int profileCalls = 0;

  @override
  Future<MerchantNpcProfile> myProfile() async {
    profileCalls++;
    if (failProfile) throw MerchantNpcException('店铺形象没加载出来');
    return profile;
  }

  @override
  Future<VoiceEnrollScript> voiceScript() async =>
      VoiceEnrollScript(available: voiceAvailable);

  @override
  Future<NpcAvatarStatus> avatarStatus() async => const NpcAvatarStatus();

  // 这一组用例不碰提交;真被调到就炸,免得静默返回一个编造的「已提交」。
  @override
  Future<String> save(MerchantNpcProfile p) async =>
      throw UnimplementedError('本组用例不提交');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 按钮在 ListView 底部,测试视口装不下 —— 先滚到能看见再断言。
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

Widget _app(_FakeNpcApi api) => ProviderScope(
  overrides: [merchantNpcApiProvider.overrideWithValue(api)],
  child: const MaterialApp(home: MerchantNpcEditPage()),
);

void main() {
  testWidgets('★★ 打开页就拉一次 profile —— 这就是可达性本身', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.profileCalls, 1);
    await _scrollTo(tester, find.text('提交审核'));
    expect(find.text('提交审核'), findsOneWidget);
  });

  testWidgets('★ 没配过(configured:false)是空表单,不是报错页', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merchant-npc-name')), findsOneWidget);
    expect(
      find.textContaining('没加载出来'),
      findsNothing,
      reason: '把「没配过」当异常,第一次进来的商家看到的是报错页',
    );
  });

  testWidgets('★★ 已配过:名字读回来、审核态横幅出现,且保存说什么由后端下发', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(
      profile: const MerchantNpcProfile(
        configured: true,
        profileId: 9,
        name: '老周',
        persona: '说话慢一点',
        auditStatus: 0,
        statusText: '审核中,大约 1 个工作日',
      ),
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.profileCalls, 1);
    expect(
      find.text('审核中,大约 1 个工作日'),
      findsOneWidget,
      reason: '审核文案由后端下发,客户端不自己拼 —— 两端各写一套会出现两种说法',
    );
    await _scrollTo(tester, find.textContaining('保存后进入审核'));
    expect(
      find.textContaining('保存后进入审核'),
      findsOneWidget,
      reason: '保存 = 回到待审,必须在按钮上说清,不然改个错别字会以为立刻生效',
    );
    expect(find.text('老周'), findsOneWidget);
  });

  testWidgets('★ 接口挂了给重试口,不是空白页', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(failProfile: true);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('店铺形象没加载出来'), findsOneWidget);
    expect(find.byKey(const Key('merchant-npc-save')), findsNothing);
  });

  // 文案批 C:`pages/merchant/decor/ai-npc/index.wxml:53/68/160` 的标题与入口原句。
  // ★ 钉命名而不是钉像素:同一个字段两端叫两个名字(如「怎么说话」vs「性格设定」),
  //   在小程序里填过这一栏的商家到 App 会认不出来 —— 这是能断言的,值得断言。
  testWidgets('★★ 人格 / 声音两栏的标题与入口按小程序原句命名', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(
      voiceAvailable: true,
      profile: const MerchantNpcProfile(
        configured: true,
        profileId: 9,
        name: '老周',
      ),
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('性格设定'));
    expect(find.text('性格设定'), findsOneWidget);
    await _scrollTo(tester, find.text('角色声音'));
    expect(find.text('角色声音'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('让店铺角色用你的声音说话'));
    expect(
      find.textContaining('让店铺角色用你的声音说话'),
      findsOneWidget,
      reason: '入口那句是「录五句话」的用途说明,小程序同款',
    );
  });
}
