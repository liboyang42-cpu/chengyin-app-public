import 'package:chengyin_app/data/models/merchant_customer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('客户列表保留服务端 memberId 作为详情页公开路由参数', () {
    expect(
      MerchantCustomer.fromJson(<String, dynamic>{
        'memberId': 42,
      }).customerMemberId,
      42,
    );
    expect(
      MerchantCustomer.fromJson(<String, dynamic>{
        'customerMemberId': '43',
      }).customerMemberId,
      43,
    );
    expect(
      MerchantCustomer.fromJson(<String, dynamic>{
        'memberId': 0,
      }).customerMemberId,
      isNull,
    );
  });
}
