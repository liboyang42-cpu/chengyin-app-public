import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_creator_api.dart';
import 'package:chengyin_app/feature/merchant/ai_node_assist.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements AiCreatorApi {
  _Api({this.error, this.data = const {}});
  final String? error;
  final Map<String, dynamic> data;
  int calls = 0;
  String? prompt;
  @override
  Future<Map<String, dynamic>> templateFill({required String shopName, required String extraNote,
    String category = '', String reward = '', String playStyle = '', int? validationMethod}) async {
    calls++;
    prompt = extraNote;
    if (error != null) throw Exception(error);
    return data;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> _open(WidgetTester tester, _Api api, {ValueChanged<AiNodeAssistResult?>? onResult}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [aiCreatorApiProvider.overrideWithValue(api)], child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) => Scaffold(body: CupertinoButton(child: const Text('open'), onPressed: () async {
      final result = await showAiNodeAssist(context, nodeName: '原始节点', validationMethod: 1);
      onResult?.call(result);
    }))),
  )));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
void main() {
  testWidgets('empty prompt localizes without making an AI request', (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('ai-node-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Describe the stop activity you want to generate first'), findsOneWidget);
    expect(api.calls, 0);
    expect(find.byKey(const Key('ai-node-apply')), findsNothing);
  });
  for (final error in ['请先描述想生成的节点玩法', 'Server generation unavailable']) {
    testWidgets('server AI error stays verbatim: $error', (tester) async {
      await _open(tester, _Api(error: error));
      await tester.enterText(find.byKey(const Key('ai-node-prompt')), '原始创作要求');
      await tester.tap(find.byKey(const Key('ai-node-generate')));
      await tester.pumpAndSettle();
      expect(find.text(error), findsOneWidget);
      expect(find.text('Describe the stop activity you want to generate first'), findsNothing);
    });
  }
  testWidgets('role restriction keeps server explanation and removes retry in English', (tester) async {
    await _open(tester, _Api(error: '当前身份暂不支持AI创作：原始原因'));
    await tester.enterText(find.byKey(const Key('ai-node-prompt')), '原始创作要求');
    await tester.tap(find.byKey(const Key('ai-node-generate')));
    await tester.pumpAndSettle();
    expect(find.text('当前身份暂不支持AI创作：原始原因'), findsOneWidget);
    expect(find.text('Apply to become a club leader or merchant in Settings to use this feature.'), findsOneWidget);
    expect(find.byKey(const Key('ai-node-retry')), findsNothing);
  });
  testWidgets('AI preview preserves generated content and returns draft only when applied', (tester) async {
    AiNodeAssistResult? result;
    final api = _Api(data: {'template': {'title': '原始生成标题', 'description': '原始生成描述', 'medalName': '原始勋章'}});
    await _open(tester, api, onResult: (value) => result = value);
    await tester.enterText(find.byKey(const Key('ai-node-prompt')), '原始创作要求');
    await tester.tap(find.byKey(const Key('ai-node-generate')));
    await tester.pumpAndSettle();
    expect(api.prompt, '原始创作要求');
    expect(find.text('原始生成标题'), findsOneWidget);
    expect(find.text('AI 生成内容,请核对后再发布'), findsOneWidget);
    expect(find.text('AI also returned medal name. This editor has no matching fields, so they were skipped.'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.byKey(const Key('ai-node-apply')));
    await tester.pumpAndSettle();
    expect(result?.title, '原始生成标题');
    expect(result?.description, '原始生成描述');
    expect(result?.medalName, '原始勋章');
  });
}
