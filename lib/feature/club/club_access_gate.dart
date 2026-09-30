import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/club_crm_api.dart';
import '../../data/models/club_access.dart';

/// 俱乐部页内守卫的判据串(与后端 `ClubPermission` 同字面量)。
const String kClubMemberListRead = 'club:member:list:read';
const String kClubFinanceRead = 'club:finance:read';

enum ClubAccessDecision { checking, allow, deny, unknown }

class ClubAccessGateResult {
  const ClubAccessGateResult(this.decision, this.reason);

  final ClubAccessDecision decision;
  final String reason;
}

/// 页内权限判定的最小版本(App 暂无俱乐部 access 底座)。
///
/// 逐字移植小程序 `utils/access-gate.js#decideClubGate` 的纪律:
/// **只有明确的拒绝才拦**;回执坏了(网络/格式)判 unknown、放行去让后端拦 ——
/// 把网络问题栽成「没权限」会把人锁在页外,比不拦更坏。
ClubAccessGateResult evaluateClubAccess(
  AsyncValue<ClubAccess> access, {
  required int clubId,
  required String permission,
}) {
  return access.when(
    loading: () => const ClubAccessGateResult(ClubAccessDecision.checking, ''),
    error: (Object error, StackTrace _) {
      if (error is ClubCrmApiException && error.isAuthFailure) {
        return ClubAccessGateResult(ClubAccessDecision.deny, error.message);
      }
      return const ClubAccessGateResult(ClubAccessDecision.unknown, '');
    },
    data: (ClubAccess value) {
      if (!value.active) {
        return const ClubAccessGateResult(
          ClubAccessDecision.deny,
          '当前账号无权进入该俱乐部',
        );
      }
      if (value.clubId != null && value.clubId != clubId) {
        return const ClubAccessGateResult(
          ClubAccessDecision.deny,
          '当前账号不在这个俱乐部',
        );
      }
      if (!value.has(permission)) {
        return const ClubAccessGateResult(
          ClubAccessDecision.deny,
          '当前角色没有这项权限',
        );
      }
      return const ClubAccessGateResult(ClubAccessDecision.allow, '');
    },
  );
}

/// 读接口失败的归一:身份/授权类 → 没权限屏;没连上 → 网络态;其余 → 错误态。
({bool auth, bool network}) classifyClubCrmFailure(Object error) {
  if (error is ClubCrmApiException) {
    if (error.isAuthFailure) return (auth: true, network: false);
    return (auth: false, network: error.networkUnreachable);
  }
  return (auth: false, network: false);
}
