import '../feature/account/pending_inviter.dart';
import 'network/session_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/api/advanced_play_api.dart';
import '../data/api/page_parity_api.dart';
import '../data/api/activity_api.dart';
import '../data/api/official_api.dart';
import '../data/api/participant_api.dart';
import '../data/api/coop_api.dart';
import '../data/api/template_api.dart';
import '../data/api/club_lead_api.dart';
import '../data/api/city_node_api.dart';
import '../data/api/ai_creator_api.dart';
import '../data/api/my_project_api.dart';
import '../data/api/withdrawal_api.dart';
import '../data/api/ai_npc_api.dart';
import '../data/api/asset_api.dart';
import '../data/api/auth_api.dart';
import '../data/api/banner_api.dart';
import '../data/api/category_api.dart';
import '../data/api/club_api.dart';
import '../data/api/club_compensation_api.dart';
import '../data/api/club_crm_api.dart';
import '../data/api/club_ops_api.dart';
import '../data/api/club_topic_ops_api.dart';
import '../data/api/coupon_api.dart';
import '../data/api/feed_section_api.dart';
import '../data/api/growth_api.dart';
import '../data/api/group_code_api.dart';
import '../data/api/im_api.dart';
import '../data/api/mall_api.dart';
import '../data/api/map_api.dart';
import '../data/api/merchant_api.dart';
import '../data/api/merchant_npc_api.dart';
import '../data/api/merchant_crm_console_api.dart';
import '../data/api/badge_wall_api.dart';
import '../data/api/roam_api.dart';
import '../data/api/play_api.dart';
import '../data/api/points_api.dart';
import '../data/api/publish_api.dart';
import '../data/api/publisher_identity_api.dart';
import '../data/api/registration_api.dart';
import '../data/api/square_api.dart';
import '../data/api/team_map_api.dart';
import '../data/api/topic_api.dart';
import '../feature/auth/auth_controller.dart';
import '../feature/account/inviter_cold_start.dart';
import '../feature/roam/roam_session_store.dart';
import 'network/dio_client.dart';
import 'network/token_store.dart';
import 'map/map_privacy_store.dart';

/// 全局 DI 入口(Riverpod)。

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final mapPrivacyStoreProvider = Provider<MapPrivacyStore>((ref) {
  return MapPrivacyStore(ref.watch(secureStorageProvider));
});

/// 冷启动邀请人归因的 `has_inviter` 闸(键名沿用真源 wx storage)。
final inviterFlagStoreProvider = Provider<InviterFlagStore>((ref) {
  return InviterFlagStore(ref.watch(secureStorageProvider));
});

final pendingInviterProvider = Provider<PendingInviter>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return PendingInviter(
    read: (key) => storage.read(key: key),
    write: (key, value) => storage.write(key: key, value: value),
    remove: (key) => storage.delete(key: key),
    currentUserId: () => ref.read(authControllerProvider).user?.id,
    bind: (id) => ref.read(registrationApiProvider).setInviter(id),
    bindForUser: (id, userId) {
      final scope = ref.read(authControllerProvider.notifier).requestScope(userId);
      return ref.read(registrationApiProvider).setInviterForSession(id, scope);
    },
  );
});

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(ref.watch(secureStorageProvider));
});

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(
    ref.watch(tokenStoreProvider),
    onUnauthorized: () {
      // 401 已证明会话失效：只清本地，不再调 `/api/logout`，
      // 避免 logout 也返 401 时重入本回调。
      ref.read(authControllerProvider.notifier).expireSession();
    },
  );
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioClientProvider));
});

final mapApiProvider = Provider<MapApi>((ref) {
  return MapApi(ref.watch(dioClientProvider));
});

final topicApiProvider = Provider<TopicApi>((ref) {
  return TopicApi(ref.watch(dioClientProvider));
});

final playApiProvider = Provider<PlayApi>((ref) {
  return PlayApi(ref.watch(dioClientProvider));
});

final growthApiProvider = Provider<GrowthApi>((ref) {
  return GrowthApi(ref.watch(dioClientProvider));
});

final couponApiProvider = Provider<CouponApi>((ref) {
  return CouponApi(ref.watch(dioClientProvider));
});

final publishApiProvider = Provider<PublishApi>((ref) {
  return PublishApi(ref.watch(dioClientProvider));
});

/// 发布者实名登记:三入口(主理人申请/商家入驻/发布确认)共用。
final publisherIdentityApiProvider = Provider<PublisherIdentityApi>((ref) {
  return PublisherIdentityApi(ref.watch(dioClientProvider));
});

final assetApiProvider = Provider<AssetApi>((ref) {
  return AssetApi(ref.watch(dioClientProvider));
});

final clubApiProvider = Provider<ClubApi>((ref) {
  return ClubApi(ref.watch(dioClientProvider));
});

final clubCompensationApiProvider = Provider<ClubCompensationApi>((ref) {
  return ClubCompensationApi(ref.watch(dioClientProvider));
});

final clubCrmApiProvider = Provider<ClubCrmApi>((ref) {
  return ClubCrmApi(ref.watch(dioClientProvider));
});

/// 俱乐部运营四页(event-ops / governance / notify / roles)接口。
final clubOpsApiProvider = Provider<ClubOpsApi>((ref) {
  return ClubOpsApi(ref.watch(dioClientProvider));
});

/// 俱乐部主题运营(4-B:topic-detail / topic-story)接口。
final clubTopicOpsApiProvider = Provider<ClubTopicOpsApi>((ref) {
  return ClubTopicOpsApi(ref.watch(dioClientProvider));
});

final groupCodeApiProvider = Provider<GroupCodeApi>((ref) {
  return GroupCodeApi(ref.watch(dioClientProvider));
});

final squareApiProvider = Provider<SquareApi>((ref) {
  return SquareApi(ref.watch(dioClientProvider));
});

final officialApiProvider = Provider<OfficialApi>((ref) {
  return OfficialApi(ref.watch(dioClientProvider));
});

final participantApiProvider = Provider<ParticipantApi>((ref) {
  return ParticipantApi(ref.watch(dioClientProvider));
});

final coopApiProvider = Provider<CoopApi>((ref) {
  return CoopApi(ref.watch(dioClientProvider));
});

final templateApiProvider = Provider<TemplateApi>((ref) {
  return TemplateApi(ref.watch(dioClientProvider));
});

final withdrawalApiProvider = Provider<WithdrawalApi>((ref) {
  return WithdrawalApi(ref.watch(dioClientProvider));
});

final activityApiProvider = Provider<ActivityApi>((ref) {
  return ActivityApi(ref.watch(dioClientProvider));
});

final mallApiProvider = Provider<MallApi>((ref) {
  return MallApi(ref.watch(dioClientProvider));
});

final imApiProvider = Provider<ImApi>((ref) {
  return ImApi(ref.watch(dioClientProvider));
});

final bannerApiProvider = Provider<BannerApi>((ref) {
  return BannerApi(ref.watch(dioClientProvider));
});

final feedSectionApiProvider = Provider<FeedSectionApi>((ref) {
  return FeedSectionApi(ref.watch(dioClientProvider));
});

final registrationApiProvider = Provider<RegistrationApi>((ref) {
  return RegistrationApi(ref.watch(dioClientProvider));
});

final pointsApiProvider = Provider<PointsApi>((ref) {
  return PointsApi(ref.watch(dioClientProvider));
});

final categoryApiProvider = Provider<CategoryApi>((ref) {
  return CategoryApi(ref.watch(dioClientProvider));
});

final merchantApiProvider = Provider<MerchantApi>((ref) {
  return MerchantApi(ref.watch(dioClientProvider));
});

final roamApiProvider = Provider<RoamApi>((ref) {
  return RoamApi(ref.watch(dioClientProvider));
});

final roamSessionStoreProvider = Provider<RoamSessionStore>((ref) {
  return RoamSessionStore(ref.watch(secureStorageProvider));
});

final badgeWallApiProvider = Provider<BadgeWallApi>((ref) {
  return BadgeWallApi(ref.watch(dioClientProvider));
});

final aiNpcApiProvider = Provider<AiNpcApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return AiNpcApi(ref.watch(dioClientProvider));
});

final merchantNpcApiProvider = Provider<MerchantNpcApi>((ref) {
  return MerchantNpcApi(ref.watch(dioClientProvider));
});

final clubLeadApiProvider = Provider<ClubLeadApi>((ref) {
  return ClubLeadApi(ref.watch(dioClientProvider));
});

final myProjectApiProvider = Provider<MyProjectApi>((ref) {
  return MyProjectApi(ref.watch(dioClientProvider));
});

final cityNodeApiProvider = Provider<CityNodeApi>((ref) {
  return CityNodeApi(ref.watch(dioClientProvider));
});

final aiCreatorApiProvider = Provider<AiCreatorApi>((ref) {
  return AiCreatorApi(ref.watch(dioClientProvider));
});

final pageParityApiProvider = Provider<PageParityApi>((ref) {
  return PageParityApi(ref.watch(dioClientProvider));
});

/// 订单详情「和队友一起出发」建队用的接口入口。
/// ⚠️ 不叫 `teamMapApiProvider`:`feature/team/team_nearby_page.dart` 有自己的
///   同名局部声明,同名会让同时 import 两者的文件(tickets_page)歧义编译失败。
final activityTeamApiProvider = Provider<TeamMapApi>((ref) {
  return TeamMapApi(ref.watch(dioClientProvider));
});

final advancedPlayGatewayProvider = Provider<AdvancedPlayGateway>((ref) {
  return AdvancedPlayApi(ref.watch(dioClientProvider));
});

final merchantCrmConsoleApiProvider = Provider<MerchantCrmConsoleApi>((ref) {
  return MerchantCrmConsoleApi(ref.watch(dioClientProvider));
});
