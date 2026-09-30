import 'package:chengyin_app/feature/publisher/publisher_identity.dart';
import 'package:flutter_test/flutter_test.dart';

// Non-issued zero-region fixtures. Expected values follow the arithmetic
// relation, independently of the production lookup table. Never call an API.
String _fixture(int remainder, {String date = '20000101'}) {
  for (var sequence = 0; sequence < 1000; sequence++) {
    final body = '000000$date${sequence.toString().padLeft(3, '0')}';
    var sum = 0;
    for (var index = 0; index < 17; index++) {
      sum += int.parse(body[index]) * ((1 << (17 - index)) % 11);
    }
    if (sum % 11 == remainder) {
      final value = (12 - remainder) % 11;
      return '$body${value == 10 ? 'X' : value.toString()}';
    }
  }
  throw StateError('Synthetic fixture generation failed');
}

void main() {
  for (var remainder = 0; remainder < 11; remainder++) {
    test('identity checksum covers remainder $remainder', () {
      final id = _fixture(remainder);
      expect(isValidIdCard(id), isTrue);
      expect(isValidIdCard(' \n${id.substring(0, 6)} ${id.substring(6).toLowerCase()}\t'), isTrue);
      for (final suffix in '0123456789X'.split('')) {
        if (suffix != id[17]) {
          expect(isValidIdCard('${id.substring(0, 17)}$suffix'), isFalse);
        }
      }
    });
  }
  test('identity date and format boundaries are preserved', () {
    expect(isValidIdCard(_fixture(10, date: '20000229')), isTrue);
    for (final date in <String>[
      '20010229', '20000431', '20001301', '20000001', '18991231',
      '${DateTime.now().year + 1}0101',
    ]) {
      expect(isValidIdCard(_fixture(10, date: date)), isFalse);
    }
    final id = _fixture(10);
    for (final invalid in <String?>[
      null, '', id.substring(0, 17), '${id}0',
      'A${id.substring(1)}', '${id.substring(0, 17)}?',
    ]) {
      expect(isValidIdCard(invalid), isFalse);
    }
  });
}
