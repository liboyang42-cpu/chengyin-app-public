// AI 帮写节点内容 —— v5.2「整表填充」(`/api/ai/template/fill`)。
//
// ★★★ 换端点的依据不是猜的:小程序真源里
//   `grep -rn 'ai/node/generate' pages/ utils/` **零调用方**,
//   而 `/api/ai/template/fill` 恰有一个(`pages/publish/temp/index.js:834`)。
//   旧端点那三个字段(description/questionName/questionAnswer)是它的子集。
//
// ★★★ 后端两条拒绝文案**性质完全不同**(ApiAiController:38/41):
//   · 「当前身份暂不支持AI创作…」→ 身份问题,**重试永远不会成功** ⇒ 不给重试钮
//   · 「AI 服务暂时不可用,请稍后重试」→ 故障 ⇒ 给重试钮
//   合并成一句「生成失败,请重试」,前一种的人会一直点一个死按钮。
//
// ★ 入参 `prompt` 是**必填**:真源 `:826-827` 空着就报「请先描述想生成的节点玩法」,
//   压根不发请求。所以浮层不再打开即生成。
//
// ⚠️ 生产 AI **已通电**(2026-08-20 读生产进程 environ 实测:
//   CHENGYIN_AI_API_KEY 未注入,但 yml 回退到 CHENGYIN_DEEPSEEK_API_KEY,
//   而那个已注入)。所以这不是"接一个必然失败的按钮"。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_creator_api.dart';
import 'package:chengyin_app/feature/merchant/ai_node_assist.dart';
import 'package:chengyin_app/feature/merchant/node_template_edit_page.dart';

class _FakeAi implements AiCreatorApi {
  _FakeAi({this.data, this.err});
  final Map<String, dynamic>? data;
  final Object? err;

  int calls = 0;

  /// 最后一次真的发给接口的载荷 —— 钉「发的是真源那几个字段名」。
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> templateFill({
    required String shopName,
    required String extraNote,
    String category = '',
    String reward = '',
    String playStyle = '',
    int? validationMethod,
  }) async {
    calls++;
    lastBody = <String, dynamic>{
      'shopName': shopName,
      'category': category,
      'reward': reward,
      'playStyle': playStyle,
      'validationMethod': validationMethod,
      'extraNote': extraNote,
    };
    if (err != null) throw err!;
    return data ?? <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<AiNodeAssistResult?> _open(
  WidgetTester t,
  _FakeAi api, {
  String prompt = '让玩家在店门口找暗号',
  bool generate = true,
  bool apply = false,
}) async {
  AiNodeAssistResult? out;
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[aiCreatorApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () async {
                out = await showAiNodeAssist(c, nodeName: '静安咖啡·手冲');
              },
              child: const Text('开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
  if (prompt.isNotEmpty) {
    await t.enterText(find.byKey(const Key('ai-node-prompt')), prompt);
  }
  if (generate) {
    await t.tap(find.byKey(const Key('ai-node-generate')));
    await t.pumpAndSettle();
  }
  if (apply) {
    await t.tap(find.byKey(const Key('ai-node-apply')));
    await t.pumpAndSettle();
  }
  return out;
}

Future<void> _openEditor(WidgetTester t, _FakeAi api) async {
  await t.binding.setSurfaceSize(const Size(390, 1400));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[aiCreatorApiProvider.overrideWithValue(api)].cast(),
      child: const MaterialApp(home: NodeTemplateEditPage()),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 身份被拒:不给重试钮,给「怎么换身份」', (WidgetTester t) async {
    final api = _FakeAi(err: Exception('当前身份暂不支持AI创作,请切换到俱乐部或商家身份'));
    await _open(t, api);
    expect(
      find.byKey(const Key('ai-node-retry')),
      findsNothing,
      reason: '重试永远不会成功 —— 摆一个死按钮',
    );
    expect(
      find.textContaining('申请成为俱乐部主理人或商家'),
      findsOneWidget,
      reason: '要告诉他怎么才能用,而不是只说不行',
    );
    expect(api.calls, 1);
  });

  testWidgets('★★ 服务故障:给重试钮,点了真的再调一次', (WidgetTester t) async {
    final api = _FakeAi(err: Exception('AI 服务暂时不可用,请稍后重试'));
    await _open(t, api);
    expect(find.byKey(const Key('ai-node-retry')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai-node-retry')));
    await t.pumpAndSettle();
    expect(api.calls, 2, reason: '重试钮点了不调接口 = 假按钮');
  });

  testWidgets('★ 没写想做什么就点生成:不发请求,并说清缺什么', (WidgetTester t) async {
    final api = _FakeAi(data: <String, dynamic>{'title': '不该被用到'});
    await _open(t, api, prompt: '', generate: true);
    expect(
      api.calls,
      0,
      reason: '真源 :826 空 prompt 压根不发请求;自己发出去等于替用户瞎编一句',
    );
    expect(find.textContaining('请先描述想生成的节点玩法'), findsOneWidget);
  });

  testWidgets('★★ 生成为空时说实话,不给「填进表单」', (WidgetTester t) async {
    await _open(t, _FakeAi(data: <String, dynamic>{}));
    expect(
      find.byKey(const Key('ai-node-apply')),
      findsNothing,
      reason: '空结果塞进表单 = 用户以为 AI 写了东西',
    );
    expect(find.textContaining('没生成出内容'), findsOneWidget);
  });

  testWidgets('★ 有结果时先预览再填,不直接保存', (WidgetTester t) async {
    await _open(
      t,
      _FakeAi(
        data: <String, dynamic>{
          'template': <String, dynamic>{
            'title': '吧台手冲打卡',
            'description': '在吧台点一杯当日手冲',
            'questionName': '今天的豆子产地是?',
            'questionAnswer': '埃塞俄比亚',
          },
        },
      ),
    );
    expect(find.text('在吧台点一杯当日手冲'), findsOneWidget);
    // 说清会发生什么:填进表单,还能改。
    expect(find.text('填进表单(还能改)'), findsOneWidget);
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(
      t
          .widget<CupertinoButton>(find.byKey(const Key('ai-node-apply')))
          .minimumSize,
      const Size.fromHeight(44),
    );
  });

  testWidgets('★★ 编辑页:整张表落进表单,且不覆盖商家已经写过的', (WidgetTester t) async {
    final api = _FakeAi(
      data: <String, dynamic>{
        'template': <String, dynamic>{
          'title': 'AI 写的标题',
          'description': 'AI 写的描述',
          'questionName': 'AI 写的题目',
          'questionAnswer': 'AI 写的答案',
          'optionA': '选项甲',
          'optionB': '选项乙',
          'feedbackText': 'AI 写的反馈',
          'validationMethod': 3,
        },
      },
    );
    await _openEditor(t, api);

    // 商家先自己写一格,验证「AI 不覆盖」。
    await t.enterText(
      find.widgetWithText(CupertinoTextField, '给这个玩法起个名字'),
      '商家自己写的标题',
    );
    await t.pump();

    await t.tap(find.byKey(const Key('ai-node-assist')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai-node-prompt')), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('ai-node-prompt')),
      '做一个找暗号的玩法',
    );
    await t.tap(find.byKey(const Key('ai-node-generate')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai-node-apply')));
    await t.pumpAndSettle();

    // 发出去的载荷逐字对齐真源字段名。
    expect(api.lastBody?['extraNote'], '做一个找暗号的玩法');
    expect(api.lastBody?['shopName'], isNotNull);
    expect(api.lastBody?['category'], '');
    expect(api.lastBody?['playStyle'], '');

    expect(find.text('AI 写的描述'), findsOneWidget);
    expect(find.text('AI 写的题目'), findsOneWidget);
    expect(find.text('选项甲'), findsOneWidget);
    expect(find.text('选项乙'), findsOneWidget);
    expect(find.text('AI 写的反馈'), findsOneWidget);
    // ★ 负控:AI 顺手回了暗号栏,但这次验证方式是"选择题" ——
    //   表单按方式只摆要填的栏,暗号那一格不该出现。
    expect(
      find.text('AI 写的答案'),
      findsNothing,
      reason: '换成选择题后,暗号那一栏不该出现在表单上',
    );
    // ★ 负控:商家自己写的那格没被 AI 顶掉。
    expect(
      find.text('商家自己写的标题'),
      findsOneWidget,
      reason: '商家写的比 AI 生成的要紧',
    );
    expect(find.text('AI 写的标题'), findsNothing);
  });

  testWidgets('★ 表单放不下的字段要说出来,不静默丢', (WidgetTester t) async {
    await _open(
      t,
      _FakeAi(
        data: <String, dynamic>{
          'template': <String, dynamic>{
            'questionName': '题目',
            'medalName': '咖啡猎人',
            'hint1': '看看吧台',
            'storyText': '一段故事',
          },
        },
      ),
    );
    expect(find.byKey(const Key('ai-node-skipped')), findsOneWidget);
    expect(find.textContaining('勋章名'), findsOneWidget);
  });

  test('★★ 外壳解包:template / node / 裸表三种都认,template 优先', () {
    expect(
      AiNodeAssistResult.fromResponse(<String, dynamic>{
        'template': <String, dynamic>{'title': 'T'},
        'node': <String, dynamic>{'title': 'N'},
      }).title,
      'T',
    );
    expect(
      AiNodeAssistResult.fromResponse(<String, dynamic>{
        'node': <String, dynamic>{'title': 'N'},
      }).title,
      'N',
    );
    expect(
      AiNodeAssistResult.fromResponse(<String, dynamic>{'title': 'B'}).title,
      'B',
    );
  });

  test('★★ 空判照真源六格:装饰性字段有内容也不算「生成成功」', () {
    // 真源 :857 只看这六格。
    expect(AiNodeAssistResult.fromJson(<String, dynamic>{}).isEmpty, isTrue);
    expect(
      AiNodeAssistResult.fromJson(<String, dynamic>{'description': '  '}).isEmpty,
      isTrue,
      reason: '只有空白也算空 —— 空白塞进表单和没写一样,但用户会以为写了',
    );
    expect(
      AiNodeAssistResult.fromJson(<String, dynamic>{
        'questionName': '题目',
      }).isEmpty,
      isFalse,
    );
    // 负控:只有 title(不在那六格里)时**仍算空** —— 否则页面会给一个空表单。
    expect(
      AiNodeAssistResult.fromJson(<String, dynamic>{'title': '只有标题'}).isEmpty,
      isTrue,
    );
  });
}
