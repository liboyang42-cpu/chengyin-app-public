import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_city_node.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';
import 'package:chengyin_app/data/models/node_template.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_create_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_edit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_npc_avatar_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_node_strings.dart';
import 'package:chengyin_app/feature/merchant/node_template_edit_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

class _DeniedApi implements MerchantApi {
  int profileCalls = 0;
  @override
  Future<MerchantAccess> access() async => const MerchantAccess(
    active: true, merchantId: 1, merchantName: '原始店名', merchantLogo: null,
    roleCode: 'MERCHANT_CHECKIN', permissions: {'merchant:verify'},
  );
  @override
  Future<Map<String, dynamic>> merchantInfo() async { profileCalls++; return {}; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NpcApi implements MerchantNpcApi {
  @override
  Future<MerchantNpcProfile> myProfile() async => const MerchantNpcProfile(
    configured: true, name: '审核中', statusText: '审核中', auditStatus: 0,
    persona: '原始人设', knowledge: '原始菜单 32 元',
  );
  @override
  Future<VoiceEnrollScript> voiceScript() async => const VoiceEnrollScript(available: false);
  @override
  Future<NpcAvatarStatus> avatarStatus() async => const NpcAvatarStatus();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('node permission denial is English and does not load store data', (tester) async {
    final api = _DeniedApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantApiProvider.overrideWithValue(api)],
      child: _host(const MerchantCityNodeCreatePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your role cannot manage nodes'), findsOneWidget);
    expect(find.text('Ask the owner or manager to adjust your merchant team role'), findsOneWidget);
    expect(api.profileCalls, 0);
  });

  testWidgets('node applications preserve backend names and rejection reason', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [cityNodesProvider.overrideWith((ref) async => const CityNodeHome(
        used: 2, max: 3, applications: [CityNodeApplication(
          id: 1, poiName: '原始地点', applicationType: 2, status: 2, rejectReason: '后端原始驳回原因',
        )],
      ))],
      child: _host(const MerchantCityNodePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Active nodes 2/3'), findsOneWidget);
    expect(find.text('Node claim · 原始地点'), findsOneWidget);
    expect(find.text('Rejected: 后端原始驳回原因'), findsOneWidget);
    expect(find.byKey(const Key('city-node-cancel-claim-1')), findsNothing);
  });

  testWidgets('NPC server review text and merchant knowledge stay original', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantNpcApiProvider.overrideWithValue(_NpcApi())],
      child: _host(const MerchantNpcEditPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Store character'), findsOneWidget);
    expect(find.text('审核中'), findsWidgets);
    final field = tester.widget<CupertinoTextField>(find.byKey(const Key('merchant-npc-knowledge')));
    expect(field.controller!.text, '原始菜单 32 元');
    expect(find.text('Upload a character avatar'), findsOneWidget);
    expect(find.byKey(const Key('merchant-npc-voice-entry')), findsNothing);
  });

  testWidgets('unavailable 3D generation stays blocked with English guidance', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantNpcApiProvider.overrideWithValue(_NpcApi())],
      child: _host(const MerchantNpcAvatarPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3D character generation is not available yet'), findsOneWidget);
    expect(find.text('Choose photo and generate'), findsNothing);
  });

  testWidgets('template methods localize while validation codes remain unchanged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(child: _host(const NodeTemplateEditPage())));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title'), findsOneWidget);
    expect(find.text('GPS arrival'), findsOneWidget);
    await tester.tap(find.byKey(const Key('node-method-1')));
    await tester.pumpAndSettle();
    expect(find.text('Passphrase answer'), findsOneWidget);
    expect(NodeValidationMethod.secretWord.wire, 1);
    expect(NodeValidationMethod.posterCode.wire, 4);
    expect(const NodeTemplateDraft().validate(), '请填写标题');
  });

  testWidgets('only missing node names are translated', (tester) async {
    final absent = CityNode.fromJson({'id': 1});
    final present = CityNode.fromJson({'id': 2, 'name': '未命名据点'});
    await tester.pumpWidget(_host(Builder(builder: (context) => Column(children: [
      Text(merchantNodeName(context, absent)), Text(merchantNodeName(context, present)),
    ]))));
    expect(find.text('Unnamed node'), findsOneWidget);
    expect(find.text('未命名据点'), findsOneWidget);
    expect(present.hasNameFallback, isFalse);
  });
}
