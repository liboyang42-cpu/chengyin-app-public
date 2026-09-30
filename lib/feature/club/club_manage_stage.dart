import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/club_manage.dart';
import '../../data/models/coop_invite_row.dart';
import '../../data/models/my_project.dart';

/// 主理人「现在要做」那张卡的阶段机。对齐小程序 `pages/club/detail/index.js`
/// 的 `OWNER_STAGE_COPY` + `updateOwnerStage()`(@90e66d70),文案逐字照搬。
enum ClubManageStage { loading, error, publish, invite, pending, accepted }

/// 一个阶段的标题 + 说明(小程序 `ownerPrimaryLabel` / `ownerStageHint`)。
class ClubManageCopy {
  const ClubManageCopy(this.label, this.hint);

  final String label;
  final String hint;
}

const Map<ClubManageStage, ClubManageCopy> clubManageCopy =
    <ClubManageStage, ClubManageCopy>{
      ClubManageStage.publish: ClubManageCopy('发布主题', '先发布一个俱乐部项目'),
      ClubManageStage.invite: ClubManageCopy('邀请商家', '选择一个项目，开始对接商家'),
      ClubManageStage.pending: ClubManageCopy('查看邀请进度', '邀请已发出，等待商家回应'),
      ClubManageStage.accepted: ClubManageCopy('管理项目', '商家已接受，进入项目主办视图'),
      ClubManageStage.loading: ClubManageCopy('读取管理进度…', '正在核对项目与邀请状态'),
      ClubManageStage.error: ClubManageCopy('重试管理进度', '暂时无法确认当前阶段'),
    };

/// 阶段判定(小程序的 `updateOwnerStage`)。
///
/// ★ 输入的三份读模型缺一不可:`accepted` 只有 `/api/project/my` 的
///   `acceptStatus` 说得清,`pending` 只有 `/api/coop/list` 的发出邀约说得清 ——
///   拿 `/api/club/topics` 猜「有没有商家接受」只能猜出两种态。
/// ★ 读失败 ≠ 阶段未知:任一路失败就落 error,让卡上出现能点的「重试管理进度」,
///   不把「暂时读不到」说成「先发布一个项目」。
ClubManageStage resolveClubManageStage({
  required AsyncValue<List<ClubTopic>> topics,
  required AsyncValue<List<MyProject>> ownerProjects,
  required AsyncValue<CoopInviteList> invites,
}) {
  if (topics.hasError) return ClubManageStage.error;
  final List<ClubTopic>? topicRows = topics.value;
  if (topicRows == null) return ClubManageStage.loading;
  final Set<int> topicIds = topicRows.map((ClubTopic row) => row.id).toSet();
  // 一个项目都没有时,阶段与邀约状态无关 —— 先发项目。
  if (topicIds.isEmpty) return ClubManageStage.publish;

  if (ownerProjects.hasError) return ClubManageStage.error;
  final List<MyProject>? projectRows = ownerProjects.value;
  if (projectRows == null) return ClubManageStage.loading;
  if (projectRows.any(
    (MyProject row) => row.acceptStatus == 'merchantAccepted',
  )) {
    return ClubManageStage.accepted;
  }

  if (invites.hasError) return ClubManageStage.error;
  final CoopInviteList? inviteRows = invites.value;
  if (inviteRows == null) return ClubManageStage.loading;
  // 只算**本俱乐部项目**上的发出邀约;status 0 = 等商家回应。
  final bool pending = inviteRows.sent.any(
    (CoopInviteRow row) => row.status == 0 && topicIds.contains(row.topicId),
  );
  return pending ? ClubManageStage.pending : ClubManageStage.invite;
}
