import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_decor.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_story_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_gallery_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_edit_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantApi {
  _Api(this.profile);
  final Map<String, dynamic> profile;
  MerchantDecor? saved;
  @override
  Future<Map<String, dynamic>> coopProfile() async => profile;
  @override
  Future<Map<String, dynamic>> merchantInfo() async => profile;
  @override
  Future<void> saveDecor(MerchantDecor decor) async { saved = decor; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_Api api, Widget child) => ProviderScope(
  overrides: [merchantApiProvider.overrideWithValue(api)],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  testWidgets('profile fields translate while merchant-written values stay original', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_Api({'name': '品牌名称', 'description': '介绍'}), const MerchantEditPage()));
    await tester.pumpAndSettle();
    expect(find.text('Store profile'), findsOneWidget);
    expect(find.text('Brand name'), findsOneWidget);
    expect(tester.widget<CupertinoTextField>(find.byKey(const Key('merchant-edit-name'))).controller!.text, '品牌名称');
    expect(tester.widget<CupertinoTextField>(find.byKey(const Key('merchant-edit-description'))).controller!.text, '介绍');
  });

  testWidgets('English tag picker persists original Chinese wire tag', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api({'id': 1, 'name': '原始店名', 'tags': '自定义原文'});
    await tester.pumpWidget(_host(api, const MerchantDecorPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Store tags'));
    await tester.tap(find.text('Store tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pet friendly'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(api.saved!.tags, ['自定义原文', '宠物友好']);
    expect(find.text('原始店名'), findsWidgets);
  });

  testWidgets('brand story editor preserves original story and length limit', (tester) async {
    await tester.pumpWidget(_host(_Api({'id': 1, 'description': '原文故事，保持不变。'}), const MerchantDecorStoryPage()));
    await tester.pumpAndSettle();
    expect(find.text('Brand story'), findsOneWidget);
    final field = tester.widget<CupertinoTextField>(find.byKey(const Key('merchant-decor-story-body')));
    expect(field.controller!.text, '原文故事，保持不变。');
    expect(field.placeholder, startsWith('Tell your store’s story in 80–200 characters'));
    expect(field.maxLength, 300);
  });

  testWidgets('gallery no-store state has English guidance', (tester) async {
    await tester.pumpWidget(_host(_Api({}), const MerchantDecorGalleryPage()));
    await tester.pumpAndSettle();
    expect(find.text('Store gallery'), findsOneWidget);
    expect(find.text('Gallery uploads are unavailable'), findsOneWidget);
    expect(find.text('This account has no store yet. Complete merchant onboarding before uploading store photos.'), findsOneWidget);
  });
}
