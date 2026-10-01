import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('club disclosure translation retains deadlines evidence and cancellation limits', () {
    final strings = AppLocalizationsEn();
    expect(strings.clubOpsTimeEffectPolicy, contains('24 hours before the new meeting time'));
    expect(strings.clubOpsTimeDonePolicy, contains('24 hours before the new meeting time'));
    expect(strings.clubRulesCopy39, contains('2–255'));
    expect(strings.clubSettlementEvidencePolicy, contains('do not mean funds have arrived'));
    expect(strings.clubSettlementEvidencePolicy, contains('no further payment'));
    expect(strings.clubSettlementMissingEvidence(3),
        '3 settled records lack evidence of credit; the total awaits verification');
  });
}
