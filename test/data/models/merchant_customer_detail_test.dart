import 'package:chengyin_app/data/models/merchant_customer_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('客户详情严格绑定路由客户 ID，且未下发金额不写成 0', () {
    final MerchantCustomerDetail detail = MerchantCustomerDetail.fromJson(
      <String, dynamic>{
        'summary': <String, dynamic>{
          'customerMemberId': 41,
          'displayName': '林青',
          'avatar': '',
          'arrivedCount': 2,
          'pendingCount': 1,
          'refundedCount': 0,
          'paidAmount': null,
          'lastInteractionTime': '2026-08-23T12:00:00Z',
        },
        'systemTags': <dynamic>[
          <String, dynamic>{'code': 'ARRIVED', 'label': '已到店'},
        ],
        'merchantTags': <dynamic>[
          <String, dynamic>{'id': 3, 'tagName': '高频复购', 'tagColor': '#2e6d5a'},
        ],
        'timeline': <dynamic>[
          <String, dynamic>{
            'key': 'note-8',
            'type': 'NOTE',
            'title': '团队跟进',
            'description': '记得无糖',
            'occurredAt': '2026-08-23T13:00:00Z',
            'noteId': 8,
            'noteVersion': 0,
          },
        ],
      },
      expectedCustomerMemberId: 41,
    );

    expect(detail.summary.customerMemberId, 41);
    expect(detail.summary.paidAmount, isNull);
    expect(detail.summary.paidAmountText, '无查看权限');
    expect(detail.merchantTags.single.tagColor, '#2E6D5A');
    expect(detail.timeline.single.typeText, '跟进');
    expect(detail.timeline.single.canManageNote, isTrue);

    expect(
      () => MerchantCustomerDetail.fromJson(<String, dynamic>{
        'summary': <String, dynamic>{
          'customerMemberId': 99,
          'arrivedCount': 0,
          'pendingCount': 0,
          'refundedCount': 0,
        },
        'systemTags': <dynamic>[],
        'merchantTags': <dynamic>[],
        'timeline': <dynamic>[],
      }, expectedCustomerMemberId: 41),
      throwsFormatException,
    );
  });
}
