import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/merchant_api.dart';
import 'providers.dart';

/// 经营身份与岗位权限的**单一事实源**:`POST /api/merchant/access/me`。
///
/// ★★ 小程序侧有一条写死的契约(`utils/merchant-access-policy.js`):
///   「access/me 的唯一前端投影。active、主体、固定角色、权限数组必须同时可信;
///    任一层脏数据都关闭,而不是沿用旧全局 role/userType 放行。」
///   App 此前把这条判据散在各页(台账/售后/客户各自现调 `access()`),
///   工作台与营销/模板两 tab 则**根本没判** —— 无权限的员工看到入口、
///   点进去撞 403,拿到的是一句「加载失败 + 重试」,而重试永远不会好。
///
/// ⚠️ fail-closed:读不到 access 的这段时间,受权限位控制的入口**一律不渲染**,
///   不是"先都摆出来,等结果回来再收"。
///
/// ⚠️ 单独成文件而不是并进 core/providers.dart —— 与 role_provider.dart 同理,
///   那个文件多处并行在改,避免撞车。
final merchantAccessProvider = FutureProvider.autoDispose<MerchantAccess>((
  ref,
) {
  return ref.watch(merchantApiProvider).access();
});
