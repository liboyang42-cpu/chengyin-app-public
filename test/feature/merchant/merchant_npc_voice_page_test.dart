// 门店形象的声音入口(`/api/merchant/npc/voice/status` 在 App 的两个落点之一)。
//
// ★★ 这条接口存在的**唯一理由是异步**:`voice/enroll` 提交成功只代表
//   「录好了」,克隆还在供应商那边跑,商家必须能问到进度。
//
// ★ 另一条口径:供应商没接(available:false)时给空态,**不给录音入口** ——
//   让人录完五句才失败是最差的做法(直调也挡,页面注释原话)。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_voice_page.dart';

class _FakeNpcApi implements MerchantNpcApi {
  _FakeNpcApi({this.available = false, this.fail = false});

  final bool available;
  final bool fail;

  int scriptCalls = 0;

  @override
  Future<VoiceEnrollScript> voiceScript() async {
    scriptCalls++;
    if (fail) throw MerchantNpcException('录音脚本没加载出来');
    return VoiceEnrollScript(
      available: available,
      lines: const <String>['这是授权声明', '第二句', '第三句', '第四句', '第五句'],
      consentIndex: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 提交按钮在列表底部,测试视口装不下 —— 先滚到能看见再断言。
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
  child: const MaterialApp(home: MerchantNpcVoicePage()),
);

void main() {
  testWidgets('★★ 打开页就拉录音脚本 —— 声音入口的可达性', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(available: true);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(api.scriptCalls, 1);
    expect(
      find.byKey(const Key('merchant-npc-voice-record-0')),
      findsOneWidget,
    );
    await _scrollTo(tester, find.text('提交这五句'));
    expect(find.byKey(const Key('merchant-npc-voice-submit')), findsOneWidget);
    expect(
      find.textContaining('还差第 1 句'),
      findsOneWidget,
      reason: '五句不齐要当场说清差哪句,不是让人点了提交才被打回',
    );
  });

  testWidgets('★★ 供应商没接:直说 + 不给录音入口', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(available: false);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('声音克隆还没开放'), findsOneWidget);
    expect(
      find.byKey(const Key('merchant-npc-voice-record-0')),
      findsNothing,
      reason: '开了入口再失败,等于让人白录五句',
    );
  });

  testWidgets('★ 脚本拉不到给重试口', (WidgetTester tester) async {
    final _FakeNpcApi api = _FakeNpcApi(fail: true);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('没能读到录音脚本'), findsOneWidget);
    expect(find.text('提交这五句'), findsNothing);
  });

  // 文案批 C:三档状态的正话逐字取自小程序
  // `pages/merchant/decor/ai-npc/index.wxml:177-188`(那边上传录音、这边录五句,
  // 状态机是同一套)。这三句只在「提交成功之后的进度页」出现,而进到那一步要真录
  // 五段音频 —— 不假造录音,按仓内 gate 的做法直接钉源码字面量,改字就红。
  test('★ 声音三档状态与刷新动作的原句与小程序逐字一致', () {
    final String src = File(
      'lib/feature/merchant/merchant_npc_voice_page.dart',
    ).readAsStringSync();
    expect(src, contains('merchantVoiceCheckStatus'));
    for (final String line in <String>[
      '声音正在生成，可以先返回继续装修店铺。',
      '角色的声音已准备好。',
      '声音生成失败，请重新选择清晰的录音。',
      '查询生成状态',
    ]) {
      expect(<String>[AppLocalizationsZh().merchantVoiceGenerating, AppLocalizationsZh().merchantVoiceReady, AppLocalizationsZh().merchantVoiceFailed, AppLocalizationsZh().merchantVoiceCheckStatus].any((text) => text.contains(line)), isTrue, reason: '小程序原句缺了「$line」');
    }
  });
}
