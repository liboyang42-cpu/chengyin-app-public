// 商家岗位投影的测试夹具。
//
// ★ 一律走 `MerchantAccess.fromJson`,不在测试里 new 一个 MerchantAccess ——
//   要测的正是「后端载荷 → 18 个权限位」这一层折得对不对(直接构造会绕开它)。
//
// ⚠️ 岗位→权限码的真表在 `MerchantPermissionPolicy`(镜像仓里没有该类源码),
//   所以这里的权限清单是**用例的前提**,不是从真源抄的表。断言只锁
//   「载荷里有/没有这个码 → 界面对应有/没有这个入口」。

import 'package:chengyin_app/data/api/merchant_api.dart';

const Map<String, Object> _activeMerchant = <String, Object>{
  'id': 1,
  'name': '河畔咖啡',
  'logo': 'https://cdn.example/1.png',
};

/// 一个**已激活**的经营身份。
MerchantAccess activeAccess({
  String roleCode = 'MERCHANT_OWNER',
  List<String> permissions = const <String>[],
}) {
  return MerchantAccess.fromJson(<String, dynamic>{
    'active': true,
    'merchant': _activeMerchant,
    'roleCode': roleCode,
    'permissions': permissions,
  });
}

/// 店主:后端把全部权限码都给他(真源 `access/me` 对 OWNER 下发全表)。
///
/// 只列 App 侧真的读到的那些码 —— 其余码界面不消费,列了也是噪音。
MerchantAccess ownerAccess() => activeAccess(
  permissions: const <String>[
    'merchant:basic:read',
    'merchant:profile:write',
    'merchant:project:manage',
    'merchant:verify',
    'merchant:verify:record:read',
    'merchant:order:read',
    'merchant:crm:read',
    'merchant:crm:sensitive:read',
    'merchant:crm:segment',
    'merchant:crm:export',
    'merchant:finance:read',
    'merchant:aftercare:read',
    'merchant:aftercare:respond',
    'merchant:marketing:read',
    'merchant:marketing:write',
    'merchant:coupon:manage',
    'merchant:coop:manage',
    'merchant:operator:manage',
  ],
);

/// 核销员:只有核销与订单读。四个 tab 的权限位一律为假。
MerchantAccess checkinAccess() => activeAccess(
  roleCode: 'MERCHANT_CHECKIN',
  permissions: const <String>[
    'merchant:basic:read',
    'merchant:verify',
    'merchant:verify:record:read',
    'merchant:order:read',
  ],
);

/// 运营岗:有营销读写,没有财务。
MerchantAccess marketingAccess() => activeAccess(
  roleCode: 'MERCHANT_MARKETING',
  permissions: const <String>[
    'merchant:basic:read',
    'merchant:marketing:read',
    'merchant:marketing:write',
    'merchant:coupon:manage',
  ],
);

/// 财务岗:`canReadFinance` 为真,但**不是店主** —— dashboard/todo/events
/// 三个请求在后端是 owner-only,这一条正是「权限位 ≠ 身份」的样本。
MerchantAccess financeAccess() => activeAccess(
  roleCode: 'MERCHANT_FINANCE',
  permissions: const <String>[
    'merchant:basic:read',
    'merchant:finance:read',
    'merchant:order:read',
  ],
);

/// 未激活的店主:申请**已提交**处于某一态,后端会带上摘要。
MerchantAccess inactiveAccess({
  required String applicationState,
  int status = 0,
  int accountStatus = 0,
  String? reson,
  String? disableReason,
}) {
  return MerchantAccess.fromJson(<String, dynamic>{
    'active': false,
    'applicationState': applicationState,
    'roleCode': 'MERCHANT_OWNER',
    'permissions': const <String>[],
    'merchant': <String, dynamic>{
      'id': 1,
      'name': '河畔咖啡',
      'logo': 'https://cdn.example/1.png',
      'status': status,
      'accountStatus': accountStatus,
      'reson': ?reson,
      'disableReason': ?disableReason,
    },
  });
}

/// 后端明说「这个账号名下没有申请行」。
MerchantAccess noApplicationAccess() => MerchantAccess.fromJson(
  <String, dynamic>{
    'active': false,
    'applicationState': 'NONE',
    'permissions': const <String>[],
  },
);
