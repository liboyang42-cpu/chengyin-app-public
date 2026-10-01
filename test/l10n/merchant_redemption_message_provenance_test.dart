import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/scan_result.dart';
import 'package:chengyin_app/feature/merchant/scan_choice.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/l10n/app_localizations_zh.dart';

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();
  final cases = <(Map<String, dynamic>, ScanMessageFallback, String, String)>[
    ({'code': 500, 'data': {'needChapterChoice': true}},
      ScanMessageFallback.chapterChoice, '请选择要核销的章节', 'Choose a chapter to redeem'),
    ({'code': 500, 'data': {'needStationChoice': true}},
      ScanMessageFallback.stationChoice, '请选择要核销的站点', 'Choose a station to redeem'),
    ({'code': 200}, ScanMessageFallback.redeemed, '核销成功', 'Redemption successful'),
    ({'code': 500}, ScanMessageFallback.failed, '核销失败', 'Redemption failed'),
  ];

  for (final entry in cases) {
    test('${entry.$2}: absent or empty server message has explicit provenance', () {
      for (final body in [entry.$1, {...entry.$1, 'msg': null}, {...entry.$1, 'msg': ''}]) {
        final result = ScanResult.fromBody(body);
        expect(result.messageFallback, entry.$2);
        expect(result.message, entry.$3);
        expect(localizedScanMessage(result, zh), entry.$3);
        expect(localizedScanMessage(result, en), entry.$4);
      }
    });

    test('${entry.$2}: matching Chinese and English backend text stays original', () {
      for (final serverMessage in [entry.$3, entry.$4, '服务器独有说明', 'Server-specific detail']) {
        final result = ScanResult.fromBody({...entry.$1, 'msg': serverMessage});
        expect(result.messageFallback, isNull);
        expect(localizedScanMessage(result, en), serverMessage);
        expect(localizedScanMessage(result, zh), serverMessage);
      }
    });
  }

  test('existing direct constructor retains message without inferring source', () {
    const result = ScanResult(outcome: ScanOutcome.redeemed, message: '核销成功');
    expect(result.messageFallback, isNull);
    expect(localizedScanMessage(result, en), '核销成功');
  });
}
