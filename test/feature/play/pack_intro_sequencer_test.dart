import 'package:chengyin_app/feature/play/pack_opening_intro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackIntroSequencer', () {
    test(
      '三次 tap 依序发 tapOpen → tapOpen2 → cutScene,与 .riv 的 ViewModel 契约一致',
      () {
        final PackIntroSequencer s = PackIntroSequencer();
        expect(s.onTap(), 'tapOpen');
        expect(s.finished, isFalse, reason: '揭晓 trigger 还没发,不能提前收场');
        expect(s.onTap(), 'tapOpen2');
        expect(s.finished, isFalse);
        expect(s.onTap(), 'cutScene');
        expect(s.finished, isTrue, reason: 'cutScene 已发 ⇒ 进入按时长收场');
      },
    );

    test('序列走完后连点不再发任何 trigger(狂点不会把状态机打乱)', () {
      final PackIntroSequencer s = PackIntroSequencer()
        ..onTap()
        ..onTap()
        ..onTap();
      expect(s.onTap(), isNull);
      expect(s.onTap(), isNull);
      expect(s.finished, isTrue);
    });

    test('没点完不算 finished(负控:把 finished 判早了会在撕开前就收场)', () {
      final PackIntroSequencer s = PackIntroSequencer()..onTap();
      expect(s.finished, isFalse);
    });
  });
}
