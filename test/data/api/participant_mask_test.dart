import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/participant_api.dart';

/// 掩码只是**显示**,提交一律用原值。
///
/// ★ 为什么专门锁:本项目栽过「把掩码后的值塞回可编辑表单」——
///   用户不动那一栏直接保存,库里就被写成 138****1234 这种废数据。
///   掩码属于展示层,数据层必须保持原值可用。
void main() {
  test('11 位手机号显示成掩码', () {
    const p = Participant(id: 1, fullName: '张三', mobilePhone: '13812341234');
    expect(p.maskedPhone, '138****1234');
  });

  test('掩码不改动原值 —— 提交拿到的必须是能用的号码', () {
    const p = Participant(id: 1, fullName: '张三', mobilePhone: '13812341234');
    expect(p.mobilePhone, '13812341234');
    expect(p.maskedPhone == p.mobilePhone, isFalse);
  });

  test('长度不是 11 位的原样显示,不做半截掩码', () {
    const p = Participant(id: 1, fullName: '李四', mobilePhone: '021-6666');
    expect(p.maskedPhone, '021-6666');
  });

  test('空号码不崩', () {
    const p = Participant(id: 1, fullName: '王五', mobilePhone: '');
    expect(p.maskedPhone, '');
  });

  test('isDefault 只认后端的 1,别的都当否', () {
    expect(
      Participant.fromJson(<String, dynamic>{'isDefault': 1}).isDefault,
      isTrue,
    );
    expect(
      Participant.fromJson(<String, dynamic>{'isDefault': 0}).isDefault,
      isFalse,
    );
    expect(Participant.fromJson(<String, dynamic>{}).isDefault, isFalse);
  });
}
