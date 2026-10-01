import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/network/request_session_scope.dart';
import '../auth/auth_controller.dart';
import '../../data/api/my_project_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_access.dart';
import '../../data/models/club_crm.dart';
import '../../data/models/club_manage.dart';
import '../../data/models/club_settlement.dart';
import '../../data/models/club_stats.dart';
import '../../data/models/my_project.dart';

/// 俱乐部目录(已通过)。搜索/选择场景仍用它;首页分段用 clubHomeProvider。
final clubListProvider = FutureProvider.autoDispose<List<Club>>((ref) {
  return ref.watch(clubApiProvider).list();
});

/// 俱乐部首页四段:我创建的 / 我加入的 / 附近发现 / 俱乐部活动。
///
/// ★ 不能用 clubListProvider 顶替 —— 那是**扁平目录**,
///   我自己的俱乐部会混在陌生俱乐部里,而且没有「俱乐部活动」那一段。
final clubHomeProvider = FutureProvider.autoDispose<ClubHome>((ref) {
  return ref.watch(clubApiProvider).home();
});

/// 俱乐部贡献榜(按俱乐部 + 排序维度)。
final clubLeaderboardProvider = FutureProvider.autoDispose
    .family<List<ClubRankRow>, ({int clubId, ClubRankSort sort})>((ref, arg) {
      return ref.watch(clubApiProvider).leaderboard(arg.clubId, sort: arg.sort);
    });

/// 俱乐部详情(按 id)。join/quit 成功后 invalidate 本 provider 刷新。
final clubDetailProvider = FutureProvider.autoDispose.family<Club, int>((
  ref,
  id,
) {
  return ref.watch(clubApiProvider).detail(id);
});

/// 俱乐部成员(按 clubId)。
final clubMembersProvider = FutureProvider.autoDispose
    .family<List<ClubMember>, int>((ref, clubId) {
      return ref.watch(clubApiProvider).members(clubId);
    });

/// 我拥有的俱乐部:`/api/club/my` data.owned。
/// 权限类入口(报名名册等)用它在进入页面前先判 owner/管理员,不做兜底假数据。
final clubMyProvider = FutureProvider.autoDispose<List<Club>>((ref) {
  return ref.watch(clubApiProvider).my();
});

/// 俱乐部办的经典定向团:`/api/club/topics`。
final clubTopicsProvider = FutureProvider.autoDispose
    .family<List<ClubTopic>, int>((ref, clubId) {
      return ref.watch(clubApiProvider).topics(clubId);
    });

/// 主理人管理视图里的可对接商家。后端已经过滤 coopOpen/status/delFlag。
final clubCoopMerchantsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, clubId) {
      return ref.watch(clubApiProvider).coopMerchants();
    });

/// 主理人「现在要做」阶段机的项目输入:`POST /api/project/my`。
///
/// 与小程序 `loadOwnerProjects()` 同参(`ownerType: 'club'` + 拉 all 回来自己按
/// `bizType` 过滤 —— 后端 `type` 过滤的是 projectType,不是 bizType)。
/// ★ 不能拿 `clubTopicsProvider`(`/api/club/topics`)顶替:阶段机要的是后端
///   算好的 `acceptStatus`(商家有没有承接),那一列只有 `/api/project/my` 有。
///
/// 读失败不自动重试(与 `merchant_game_node_page` 的看板读同一口径):卡上那句
/// 「重试管理进度」就是重试入口 —— 小程序也是手动 `retryOwnerManagement()`,
/// 自动重试会让「点了没反应」和「它自己好了」长得一样。
final clubOwnerProjectsProvider = FutureProvider.autoDispose
    .family<List<MyProject>, int>((ref, clubId) async {
      final MyProjectPage page = await ref
          .watch(myProjectApiProvider)
          .page(ownerType: 'club', pageSize: 200);
      return page
          .where(
            (MyProject row) =>
                row.bizType != 'activity' && row.clubId == clubId,
          )
          .toList();
    }, retry: (int retryCount, Object error) => null);

/// 入会申请列表。
final clubJoinRequestsProvider = FutureProvider.autoDispose
    .family<List<JoinRequest>, int>((ref, clubId) {
      return ref.watch(clubApiProvider).joinRequests(clubId);
    });

/// 解散前资金阻断。
final clubDissolutionBlockersProvider = FutureProvider.autoDispose
    .family<DissolutionBlockers, int>((ref, clubId) {
      return ref.watch(clubApiProvider).dissolutionBlockers(clubId);
    });

/// 一个团的报名明细(票种 + 报名者)。
final clubTeamDetailProvider = FutureProvider.autoDispose
    .family<TeamDetail, ({int clubId, int topicId})>((ref, key) {
      final session = ref.read(authControllerProvider.notifier).requestScope(
        ref.read(authControllerProvider).user?.id ?? -1,
      );
      bool active = true;
      ref.onDispose(() => active = false);
      return RequestSessionScope.run(
        RequestSessionScope(() => active && session.isCurrent()),
        () async {
          final result = await ref
          .watch(clubApiProvider)
          .topicRegistrations(clubId: key.clubId, topicId: key.topicId);
          if (!active || !session.isCurrent()) throw StateError('Session changed');
          return result;
        },
      );
    });

/// 探店日候选期次(执行俱乐部真源)。
final clubEditionsProvider = FutureProvider.autoDispose
    .family<List<EditionOption>, int>((ref, clubId) {
      return ref.watch(clubCompensationApiProvider).editions(clubId);
    });

/// 某路线可出示团码的场次。
final groupCodeActivitiesProvider = FutureProvider.autoDispose
    .family<List<GroupCodeActivity>, int>((ref, topicId) {
      return ref.watch(groupCodeApiProvider).activities(topicId);
    });

/// 客户名单(按俱乐部 + 筛选 + 关键词)。
final clubCustomersProvider = FutureProvider.autoDispose
    .family<ClubCustomerList, ({int clubId, String filter, String keyword})>((
      ref,
      key,
    ) {
      return ref
          .watch(clubCrmApiProvider)
          .customers(
            clubId: key.clubId,
            filter: key.filter,
            keyword: key.keyword,
          );
    });

/// 客户人数(管理入口那一行的数)。
final clubCustomerCountProvider = FutureProvider.autoDispose.family<int, int>((
  ref,
  clubId,
) {
  return ref.watch(clubCrmApiProvider).customerCount(clubId: clubId);
});

/// 客户详情(按俱乐部 + 客户 memberId)。
final clubCustomerDetailProvider = FutureProvider.autoDispose
    .family<ClubCustomerDetail, ({int clubId, int memberId})>((ref, key) {
      return ref
          .watch(clubCrmApiProvider)
          .customerDetail(clubId: key.clubId, memberId: key.memberId);
    });

/// 核销详情(按俱乐部 + 报名单)。
final clubCheckinDetailProvider = FutureProvider.autoDispose
    .family<ClubCheckinDetail, ({int clubId, int registrationId})>((ref, key) {
      final session = ref.read(authControllerProvider.notifier).requestScope(
        ref.read(authControllerProvider).user?.id ?? -1,
      );
      bool active = true;
      ref.onDispose(() => active = false);
      return RequestSessionScope.run(
        RequestSessionScope(() => active && session.isCurrent()),
        () async {
          final result = await ref
          .watch(clubCrmApiProvider)
          .checkinDetail(
            clubId: key.clubId,
            registrationId: key.registrationId,
          );
          if (!active || !session.isCurrent()) throw StateError('Session changed');
          return result;
        },
      );
    });

/// 俱乐部分润汇总(仅主理人/管理员)。
final clubSettlementSummaryProvider = FutureProvider.autoDispose
    .family<ClubSettlementSummary, int>((ref, clubId) {
      return ref.watch(clubCrmApiProvider).settlementSummary(clubId: clubId);
    });

/// 俱乐部数据看板(仅主理人)。
final clubStatsProvider = FutureProvider.autoDispose.family<ClubStats, int>((
  ref,
  clubId,
) {
  return ref.watch(clubCrmApiProvider).stats(clubId: clubId);
});

/// 当前账号在该俱乐部的访问上下文(页内权限判定的最小底座)。
final clubAccessProvider = FutureProvider.autoDispose.family<ClubAccess, int>((
  ref,
  clubId,
) {
  return ref.watch(clubCrmApiProvider).access(clubId: clubId);
});
