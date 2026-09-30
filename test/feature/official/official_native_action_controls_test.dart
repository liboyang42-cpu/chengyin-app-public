import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/official/official_event_detail_page.dart';
import 'package:chengyin_app/feature/official/official_inbox_page.dart';

import '../../support/source_text.dart';

void main() {
  test('原生动作页可以构造', () {
    expect(const OfficialInboxPage(), isA<OfficialInboxPage>());
    expect(
      const OfficialEventDetailPage(id: 1),
      isA<OfficialEventDetailPage>(),
    );
  });

  test('官方活动入口使用 Apple 原生动作与加载控件', () {
    final Map<String, String> pages = <String, String>{
      '收件箱': codeOf('lib/feature/official/official_inbox_page.dart'),
      '详情': codeOf('lib/feature/official/official_event_detail_page.dart'),
      '列表': codeOf('lib/feature/official/official_events_page.dart'),
      '我发布的': codeOf('lib/feature/official/official_mine_page.dart'),
    };

    for (final MapEntry<String, String> entry in pages.entries) {
      expect(
        RegExp(
          r'\b(FilledButton|OutlinedButton|TextButton|IconButton|CircularProgressIndicator)\b',
        ).hasMatch(entry.value),
        isFalse,
        reason: '${entry.key}不应保留 Material 动作或加载控件',
      );
    }
    expect(pages['收件箱'], contains('CyNativeButton('));
    expect(pages['详情'], contains('CyNativeButton('));
    expect(pages['列表'], contains('CupertinoActivityIndicator'));
    expect(pages['我发布的'], contains('CupertinoButton('));

    final String publisher = codeOf(
      'lib/feature/official/official_publish_page.dart',
    );
    expect(
      publisher,
      contains('showCySystemDatePicker('),
      reason: '日期应优先走项目的 UIKit UIDatePicker 桥接',
    );
    expect(RegExp(r'\bCupertinoDatePicker\(').hasMatch(publisher), isFalse);
  });
}
