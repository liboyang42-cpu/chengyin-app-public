import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_voice_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantNpcApi {
  _Api(this.available);
  final bool available;
  @override
  Future<VoiceEnrollScript> voiceScript() async => VoiceEnrollScript(
    available: available, consentIndex: 0,
    lines: const ['服务端授权声明原文', 'Second server line', '第三句', '第四句', '第五句'],
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _host(bool available) => ProviderScope(
  overrides: [merchantNpcApiProvider.overrideWithValue(_Api(available))],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const MerchantNpcVoicePage(),
  ),
);
void main() {
  testWidgets('English recording UI preserves consent and requires all sentences', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(true));
    await tester.pumpAndSettle();
    expect(find.text('Record your voice'), findsOneWidget);
    expect(find.text('Authorization statement'), findsOneWidget);
    expect(find.text('服务端授权声明原文'), findsOneWidget);
    expect(find.text('Second server line'), findsOneWidget);
    expect(find.text('这一句是你本人的授权。念完并提交,即表示你同意城瘾用你的声音生成本店 AI 形象的语音。'), findsOneWidget);
    expect(find.text('Sentence 1 is still missing'), findsOneWidget);
    final submit = tester.widget<CyNativeButton>(find.byKey(const Key('merchant-npc-voice-submit')));
    expect(submit.onPressed, isNull);
  });
  testWidgets('unavailable voice service has no record action', (tester) async {
    await tester.pumpWidget(_host(false));
    await tester.pumpAndSettle();
    expect(find.text('Voice cloning is not available yet'), findsOneWidget);
    expect(find.byKey(const Key('merchant-npc-voice-record-0')), findsNothing);
  });
}
