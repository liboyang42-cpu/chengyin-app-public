import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/explore_completion.dart';
import 'package:chengyin_app/feature/orders/completion_display.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity gate fallback records provenance without changing server messages', () {
    final missing = ActivityDetail.fromJson({'gate': true, 'clubId': 7});
    expect(missing.gateMessageIsLocal, isTrue);
    final supplied = ActivityDetail.fromJson({'gate': true, 'clubId': 7, 'message': '来自俱乐部的活动，加入后查看'});
    expect(supplied.gateMessageIsLocal, isFalse);
    expect(supplied.gateMessage, '来自俱乐部的活动，加入后查看');
    expect(ActivityDetail.fromJson({'gate': true, 'message': ''}).gateMessage, '');
  });

  testWidgets('order completion translates local progress and preserves supplied names', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        final completion = ExploreCompletion.fromJson({
          'completed': false, 'requiredChapterCount': 3, 'redeemedChapterCount': 1,
          'stamps': <Map<String, dynamic>>[], 'awards': {'credited': false, 'items': <dynamic>[]},
        });
        expect(completionProgressLabel(context, completion), contains('1/3'));
        expect(completionAwardsEmptyLabel(context, completion), contains('3'));
        expect(completionStampLabel(context, ExploreStamp.fromJson({'chapterId': 2})), 'Chapter 2');
        expect(completionStampLabel(context, ExploreStamp.fromJson({'chapterId': 2, 'title': '章节 2'})), '章节 2');
        final revisit = ExploreRevisit.fromJson({'clubId': 7, 'clubName': '主办俱乐部'});
        expect(completionClubLabel(context, revisit), '主办俱乐部');
        final zero = ExploreCompletion.fromJson({'requiredChapterCount': 0, 'stamps': <dynamic>[]});
        expect(completionProgressLabel(context, zero), isNull);
        return const SizedBox();
      }),
    ));
    expect(tester.takeException(), isNull);
  });
}
