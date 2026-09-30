import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('团队回执只接受合法岗位、状态、版本和时间', () {
    final MerchantTeam team = MerchantTeam.fromJson(<String, dynamic>{
      'operators': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 12,
          'nickname': '小林',
          'avatar': null,
          'roleCode': 'MERCHANT_MARKETING',
          'status': 'ACTIVE',
          'acceptedAt': '2026-08-27 10:30:00',
          'version': 3,
        },
      ],
      'invites': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 19,
          'roleCode': 'MERCHANT_FINANCE',
          'status': 'PENDING',
          'expiresAt': '2026-08-28 10:30:00',
          'version': 0,
        },
      ],
    });

    expect(team.operators.single.nickname, '小林');
    expect(team.operators.single.role.label, '运营');
    expect(team.pendingInvites.single.role.label, '财务');
    expect(team.pendingInvites.single.version, 0);
  });

  test('名单不会把未知岗位或缺失版本降级成可用数据', () {
    expect(
      () => MerchantTeam.fromJson(<String, dynamic>{
        'operators': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 12,
            'roleCode': 'OWNER',
            'status': 'ACTIVE',
            'acceptedAt': '2026-08-27 10:30:00',
          },
        ],
        'invites': const <dynamic>[],
      }),
      throwsFormatException,
    );
  });

  test('岗位更新回执必须绑定目标与预期版本', () {
    final MerchantOperatorReceipt receipt = MerchantOperatorReceipt.fromJson(
      <String, dynamic>{
        'id': 12,
        'nickname': '小林',
        'roleCode': 'MERCHANT_FINANCE',
        'status': 'ACTIVE',
        'acceptedAt': '2026-08-27 10:30:00',
        'version': 4,
        'mutationState': 'EXACT_RESULT',
      },
      expectedId: 12,
      minimumVersion: 4,
      expectedStatus: MerchantOperatorStatus.active,
      expectedRole: MerchantOperatorRole.finance,
    );

    expect(receipt.mutationState, MerchantMutationState.exactResult);
    expect(
      () => MerchantOperatorReceipt.fromJson(
        <String, dynamic>{
          'id': 13,
          'roleCode': 'MERCHANT_FINANCE',
          'status': 'ACTIVE',
          'acceptedAt': '2026-08-27 10:30:00',
          'version': 4,
          'mutationState': 'EXACT_RESULT',
        },
        expectedId: 12,
        minimumVersion: 4,
        expectedStatus: MerchantOperatorStatus.active,
        expectedRole: MerchantOperatorRole.finance,
      ),
      throwsFormatException,
    );
  });
}
