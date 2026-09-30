import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _retiredRoute = '/coop/mybiz';

void _expectNoRetiredMybizEntry(String source, {required String sourceName}) {
  expect(
    source,
    isNot(contains(_retiredRoute)),
    reason: '$sourceName 不得重新暴露已退役的 $_retiredRoute 用户入口',
  );
}

void main() {
  test('合作业务页不得重新暴露已退役的 mybiz 入口', () {
    final files = Directory('lib/feature')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      _expectNoRetiredMybizEntry(
        file.readAsStringSync(),
        sourceName: file.path,
      );
    }
  });

  test('商家资金入口已落到台账而不是旧 mybiz 页', () {
    final merchantHome = File(
      'lib/feature/merchant/merchant_home_page.dart',
    ).readAsStringSync();

    expect(
      merchantHome,
      contains("context.push('/merchant/ledger?view=settlement')"),
    );
    _expectNoRetiredMybizEntry(
      merchantHome,
      sourceName: 'lib/feature/merchant/merchant_home_page.dart',
    );
  });

  test('负控: 任一功能页重新 push 旧 mybiz 路由必须判红', () {
    const mutatedSource = "onTap: () => context.push('/coop/mybiz')";

    expect(
      () => _expectNoRetiredMybizEntry(
        mutatedSource,
        sourceName: 'mutated_feature.dart',
      ),
      throwsA(isA<TestFailure>()),
    );
  });
}
