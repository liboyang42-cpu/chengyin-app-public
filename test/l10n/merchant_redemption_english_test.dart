import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/scan_result.dart';
import 'package:chengyin_app/feature/merchant/city_node_redeem_page.dart';
import 'package:chengyin_app/feature/merchant/scan_choice.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Registration extends Fake implements RegistrationApi {
  int? chosenChapter;
  String? submittedCode;

  @override
  Future<ScanResult> scanChapter({
    required String code,
    required int chapterId,
  }) async {
    submittedCode = code;
    chosenChapter = chapterId;
    return const ScanResult(
      outcome: ScanOutcome.redeemed,
      message: '服务端核销原话',
    );
  }
}

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _choice(
  WidgetTester tester,
  _Registration api,
  ScanResult result,
  ValueChanged<String> onResult,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [registrationApiProvider.overrideWithValue(api)],
      child: _localized(
        Consumer(
          builder: (context, ref, _) => CupertinoButton(
            onPressed: () async {
              try {
                onResult(await resolveScanChoice(
                  context: context,
                  ref: ref,
                  result: result,
                  code: 'UNCHANGED-CODE',
                ));
              } catch (error) {
                onResult(error.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('Choose'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose'));
  await tester.pumpAndSettle();
}

const _result = ScanResult(
  outcome: ScanOutcome.needsChoice,
  message: '后端要求选章',
  choiceKind: 'chapter',
  choices: [ScanChoice(id: 91, name: '商家命名章节')],
);

void main() {
  testWidgets('English result action preserves original server refusal', (
    tester,
  ) async {
    var next = 0;
    await tester.pumpWidget(
      _localized(CityNodeRedeemResult(
        ok: false,
        message: '玩家未到店打卡,或该券已核销',
        onNext: () => next++,
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('玩家未到店打卡,或该券已核销'), findsOneWidget);
    expect(find.text('Continue scanning'), findsOneWidget);
    await tester.tap(find.text('Continue scanning'));
    expect(next, 1);
  });

  testWidgets('English cancellation does not submit a redemption', (tester) async {
    final api = _Registration();
    String? outcome;
    await _choice(tester, api, _result, (value) => outcome = value);
    expect(find.text('后端要求选章'), findsOneWidget);
    expect(find.text('商家命名章节'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome, 'Cancelled. This ticket has not been redeemed.');
    expect(api.chosenChapter, isNull);
  });

  testWidgets('English choice submits original identifiers and retains reply', (
    tester,
  ) async {
    final api = _Registration();
    String? outcome;
    await _choice(tester, api, _result, (value) => outcome = value);
    await tester.tap(find.byKey(const Key('scan-choice-91')));
    await tester.pumpAndSettle();
    expect(api.chosenChapter, 91);
    expect(api.submittedCode, 'UNCHANGED-CODE');
    expect(outcome, '服务端核销原话');
  });

  testWidgets('missing choices localizes only the app-owned explanation', (
    tester,
  ) async {
    final api = _Registration();
    String? outcome;
    await _choice(
      tester,
      api,
      const ScanResult(outcome: ScanOutcome.needsChoice, message: '后端原话'),
      (value) => outcome = value,
    );
    expect(outcome, '后端原话 (No options were received. Contact the platform.)');
    expect(api.chosenChapter, isNull);
  });
}
