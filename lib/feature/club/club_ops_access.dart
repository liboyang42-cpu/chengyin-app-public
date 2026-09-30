import 'package:dio/dio.dart';

import '../../data/api/club_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_access.dart';
import '../../data/models/club_ops.dart';

/// 运营四页的权限字面量(与后端 `ClubPermission` 同字面量)。
const String kClubActivityManage = 'club:activity:manage';
const String kClubEventCheckin = 'club:event:checkin';
const String kClubEventOperate = 'club:event:operate';
const String kClubMemberManage = 'club:member:manage';
const String kClubNotifySend = 'club:notify:send';
const String kClubRoleManage = 'club:role:manage';

/// 四页统一的加载态(照搬小程序:权限拒绝 / 网络失败 / 业务失败是三条)。
enum ClubOpsLoadState { loading, noPermission, networkError, error, ready }

/// 「明确拒绝」的判据:active 明确为真 + 俱乐部范围一致 + 页面自带的权限串。
///
/// ★ 纪律(小程序 2026-08-26 注释):把网络问题/坏回执栽成「没权限」,
///   比不拦更坏 —— 所以本函数只处理**已拿到合法回执**之后的判定;
///   回执坏了由调用方进 error/networkError 态。
///
/// 返回 null 表示放行,否则是拒绝理由文案。
String? clubOpsDenyReason(
  ClubOpsAccess access, {
  required int clubId,
  required bool Function(ClubOpsAccess access) allowed,
  required String deniedMessage,
}) {
  if (!access.active || access.clubId != clubId) return '当前账号不属于该俱乐部';
  if (!allowed(access)) return deniedMessage;
  return null;
}

/// 读接口失败的归一:
/// - [ClubApiException](业务码非 200)→ 业务错误态(带后端原文);
/// - 401/403 → 权限拒绝(后端表态「你不该进来」);
/// - 其余(DioException 连接类)→ 网络态。
({bool denied, bool network}) classifyClubOpsFailure(Object error) {
  if (error is ClubApiException) return (denied: false, network: false);
  if (error is DioException) {
    final int? status = error.response?.statusCode;
    if (status == 401 || status == 403) return (denied: true, network: false);
    return (denied: false, network: true);
  }
  return (denied: false, network: false);
}

/// 失败文案:业务错误带后端原文,其余给页面自己的兜底话术。
String clubOpsErrorMessage(Object error, String fallback) {
  if (error is ClubApiException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return fallback;
}

/// 把一次失败的读请求映射进四态之一(ready 由调用方在成功路径设置)。
ClubOpsLoadState clubOpsFailureState(Object error) {
  final ({bool denied, bool network}) cls = classifyClubOpsFailure(error);
  if (cls.denied) return ClubOpsLoadState.noPermission;
  if (cls.network) return ClubOpsLoadState.networkError;
  return ClubOpsLoadState.error;
}

/// 俱乐部详情页「管理」入口的 7 角色权限落点。
///
/// 逐字对齐小程序 `pages/club/detail`：管理 tab 与内联设置项的每一行各按各的
/// 权限位显隐，绝不用 `isOwner` 一把闸把 CO/OP/LA/EL/EC 全挡在门外。
/// legacy 判据（主理人本人 / 旧式管理员）来自 detail 下发的 `viewerIsAdmin`，
/// 细粒度权限位来自 `/api/club/access/me`；回执没到（access=null）时只认 legacy，
/// 权限回执坏了不栽成「没权限」（对齐 access-gate 纪律：宁可让后端拦）。
class ClubManageFlags {
  ClubManageFlags({required Club club, ClubAccess? access})
    : isOwner = club.isOwner,
      canGovern = club.canGovern,
      _access = access != null && access.active && access.clubId == club.id
          ? access
          : null;

  final bool isOwner;

  /// 主理人本人或旧式管理员（`isOwner || viewerIsAdmin`）。
  final bool canGovern;
  final ClubAccess? _access;

  bool _perm(bool Function(ClubAccess a) test) {
    final ClubAccess? a = _access;
    return a != null && test(a);
  }

  /// 管理 tab 是否出现：任一管理权限即出（小程序 canUseManageTab）。
  bool get showManageTab =>
      canGovern || (_access?.canUseManageTabByPerms ?? false);

  /// 「现在要做」进度卡：主理人 / 管理员。
  bool get manageNow => canGovern;

  /// 数据看板：仅主理人。
  bool get stats => isOwner;

  /// 项目工具面板（AI 策划入口所在）：主理人 / 管理员 / 活动运营 / 场次授权。
  bool get toolsPanel =>
      canGovern ||
      _perm((a) => a.canManageActivities) ||
      _perm((a) => a.canOperateEvents) ||
      (_access?.hasEventScope ?? false);

  /// 发布主题 / 开一场：仅主理人。
  bool get publish => isOwner;

  /// 查看客户 / 报名名册：主理人 / 管理员。
  bool get customers => canGovern;

  /// 活动运营直达：主理人 / 管理员 / 活动管理权。
  bool get eventOps => canGovern || _perm((a) => a.canManageActivities);

  /// 入会申请：主理人 / 管理员 / 审批权。
  bool get joinRequests =>
      canGovern || _perm((a) => a.canApproveMembersByPerms);

  /// 角色与权限：主理人 / 角色管理权。
  bool get roles => isOwner || _perm((a) => a.canManageRoles);

  /// 成员治理：主理人 / 管理员 / 成员管理权。
  bool get governance => canGovern || _perm((a) => a.canManageMembers);

  /// 通知成员：主理人 / 通知权。
  bool get notify => isOwner || _perm((a) => a.canSendNotify);

  /// 编辑资料：主理人 / 管理员。
  bool get editProfile => canGovern;

  /// 分润 / 解散 / 开放设置 / 工时：仅主理人。
  bool get finance => isOwner;
}
