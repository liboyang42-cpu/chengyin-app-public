import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/feature/club/club_api_messages.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success-copy scope is asynchronous local fallback only and does not leak', () async {
    String resolve(String? server) => server ?? ClubApiLocalCopy.text('deleted', '已删除');
    final english = await ClubApiLocalCopy.run({'deleted': 'Deleted'}, () async {
      await Future<void>.delayed(Duration.zero);
      return resolve(null);
    });
    final raw = await ClubApiLocalCopy.run({'deleted': 'Deleted'}, () async {
      return resolve('已删除');
    });
    expect(english, 'Deleted');
    expect(raw, '已删除');
    expect(ClubApiLocalCopy.text('deleted', '已删除'), '已删除');
  });

  testWidgets('only explicitly local API fallbacks translate', (tester) async {
    final local = clubApiResponseFailure(null, 'publish', '发布失败');
    final raw = clubApiResponseFailure('发布失败', 'publish', '发布失败');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(clubApiErrorMessage(context, local)),
        Text(clubApiErrorMessage(context, raw)),
        Text(clubApiErrorMessage(context, ClubApiException('Server detail 42'))),
        Text(clubApiErrorMessage(context, ClubApiException('请求失败', isLocal: true))),
      ])),
    ));
    expect(find.text('Could not publish'), findsOneWidget);
    expect(find.text('发布失败'), findsOneWidget);
    expect(find.text('Server detail 42'), findsOneWidget);
    expect(find.text('Request failed'), findsOneWidget);
    expect(local, isA<ClubLocalApiFailure>());
    expect(raw, isNot(isA<ClubLocalApiFailure>()));
  });
}
