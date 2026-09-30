// 台账行 → 核销详情。
//
// ★ 这一条链路原来是**两头都断的**:
//   `LedgerRow` 声明了 recordType/recordId 却没人填,行也不可点。
//   后端专门给了 /finance/redemption-detail,App 侧一直到不了。
//
// recordKey 的形态是 `"redemption:123"`
// (MerchantFinanceQueryService:348)。拆不出来时**不许兜个默认 id** ——
// 拿错 id 去查,后端回「记录不可见」,看着像权限问题,其实是解析错了。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_ledger.dart';
import '../../support/source_text.dart';

MerchantRedemption row(String key) => MerchantRedemption(recordKey: key);

void main() {
  test('★ 正常形态拆成 type + id', () {
    final r = row('redemption:123');
    expect(r.recordType, 'redemption');
    expect(r.recordId, '123');
  });

  test('★★ 拆不出来时两个都是 null,不兜默认值', () {
    for (final String bad in <String>['', 'redemption', ':123', 'redemption:']) {
      final r = row(bad);
      final bool ok = r.recordType != null && r.recordId != null;
      expect(ok, isFalse, reason: '「$bad」不该被当成可用的 recordKey');
    }
  });

  test('id 里带冒号时只按第一个冒号切', () {
    final r = row('redemption:a:b');
    expect(r.recordType, 'redemption');
    expect(r.recordId, 'a:b');
  });

  test('★ 拆不出 type/id 的行不给点击 —— 点了必失败的按钮比没按钮更坏', () {
    final String code = codeOf('lib/feature/merchant/merchant_ledger_page.dart');
    expect(code.contains('if (type == null || id == null) return card;'), isTrue,
        reason: '缺了这道判断,拆不出 id 的行也会可点,点进去必是「记录不可见」');
    expect(code.contains('/merchant/redemption/'), isTrue);
  });
}
