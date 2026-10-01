import '../data/api/object_card_api.dart';
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
  ref.watch(sessionDataKeyProvider);
  return MapApi(ref.watch(dioClientProvider));
});

final topicApiProvider = Provider<TopicApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return TopicApi(ref.watch(dioClientProvider));
});

final playApiProvider = Provider<PlayApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return PlayApi(ref.watch(dioClientProvider));
});

final growthApiProvider = Provider<GrowthApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return GrowthApi(ref.watch(dioClientProvider));
});

final couponApiProvider = Provider<CouponApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return CouponApi(ref.watch(dioClientProvider));
});

final publishApiProvider = Provider<PublishApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return PublishApi(ref.watch(dioClientProvider));
});

/// 发布者实名登记:三入口(主理人申请/商家入驻/发布确认)共用。
final publisherIdentityApiProvider = Provider<PublisherIdentityApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return PublisherIdentityApi(ref.watch(dioClientProvider));
});

final assetApiProvider = Provider<AssetApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return AssetApi(ref.watch(dioClientProvider));
});

final clubApiProvider = Provider<ClubApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubApi(ref.watch(dioClientProvider));
});

final clubCompensationApiProvider = Provider<ClubCompensationApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubCompensationApi(ref.watch(dioClientProvider));
});

final clubCrmApiProvider = Provider<ClubCrmApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubCrmApi(ref.watch(dioClientProvider));
});

/// 俱乐部运营四页(event-ops / governance / notify / roles)接口。
final clubOpsApiProvider = Provider<ClubOpsApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubOpsApi(ref.watch(dioClientProvider));
});

/// 俱乐部主题运营(4-B:topic-detail / topic-story)接口。
final clubTopicOpsApiProvider = Provider<ClubTopicOpsApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubTopicOpsApi(ref.watch(dioClientProvider));
});

final groupCodeApiProvider = Provider<GroupCodeApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return GroupCodeApi(ref.watch(dioClientProvider));
});

final squareApiProvider = Provider<SquareApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return SquareApi(ref.watch(dioClientProvider));
});

final officialApiProvider = Provider<OfficialApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return OfficialApi(ref.watch(dioClientProvider));
});

final participantApiProvider = Provider<ParticipantApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ParticipantApi(ref.watch(dioClientProvider));
});

final coopApiProvider = Provider<CoopApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return CoopApi(ref.watch(dioClientProvider));
});

final templateApiProvider = Provider<TemplateApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return TemplateApi(ref.watch(dioClientProvider));
});

final withdrawalApiProvider = Provider<WithdrawalApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return WithdrawalApi(ref.watch(dioClientProvider));
});

final activityApiProvider = Provider<ActivityApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ActivityApi(ref.watch(dioClientProvider));
});

final mallApiProvider = Provider<MallApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return MallApi(ref.watch(dioClientProvider));
});

final imApiProvider = Provider<ImApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ImApi(ref.watch(dioClientProvider));
});

final bannerApiProvider = Provider<BannerApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return BannerApi(ref.watch(dioClientProvider));
});

final feedSectionApiProvider = Provider<FeedSectionApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return FeedSectionApi(ref.watch(dioClientProvider));
});

final registrationApiProvider = Provider<RegistrationApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return RegistrationApi(ref.watch(dioClientProvider));
});

final pointsApiProvider = Provider<PointsApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return PointsApi(ref.watch(dioClientProvider));
});

final categoryApiProvider = Provider<CategoryApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return CategoryApi(ref.watch(dioClientProvider));
});

final merchantApiProvider = Provider<MerchantApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return MerchantApi(ref.watch(dioClientProvider));
});

final roamApiProvider = Provider<RoamApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return RoamApi(ref.watch(dioClientProvider));
});

final roamSessionStoreProvider = Provider<RoamSessionStore>((ref) {
  return RoamSessionStore(ref.watch(secureStorageProvider));
});

final badgeWallApiProvider = Provider<BadgeWallApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return BadgeWallApi(ref.watch(dioClientProvider));
});

final aiNpcApiProvider = Provider<AiNpcApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return AiNpcApi(ref.watch(dioClientProvider));
});

final merchantNpcApiProvider = Provider<MerchantNpcApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return MerchantNpcApi(ref.watch(dioClientProvider));
});

final clubLeadApiProvider = Provider<ClubLeadApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ClubLeadApi(ref.watch(dioClientProvider));
});

final myProjectApiProvider = Provider<MyProjectApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return MyProjectApi(ref.watch(dioClientProvider));
});

final cityNodeApiProvider = Provider<CityNodeApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return CityNodeApi(ref.watch(dioClientProvider));
});

final aiCreatorApiProvider = Provider<AiCreatorApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return AiCreatorApi(ref.watch(dioClientProvider));
});

final pageParityApiProvider = Provider<PageParityApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return PageParityApi(ref.watch(dioClientProvider));
});

/// 订单详情「和队友一起出发」建队用的接口入口。
/// ⚠️ 不叫 `teamMapApiProvider`:`feature/team/team_nearby_page.dart` 有自己的
///   同名局部声明,同名会让同时 import 两者的文件(tickets_page)歧义编译失败。
final activityTeamApiProvider = Provider<TeamMapApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return TeamMapApi(ref.watch(dioClientProvider));
});

final advancedPlayGatewayProvider = Provider<AdvancedPlayGateway>((ref) {
  ref.watch(sessionDataKeyProvider);
  return AdvancedPlayApi(ref.watch(dioClientProvider));
});

final merchantCrmConsoleApiProvider = Provider<MerchantCrmConsoleApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return MerchantCrmConsoleApi(ref.watch(dioClientProvider));
});

final objectCardApiProvider = Provider<ObjectCardApi>((ref) {
  ref.watch(sessionDataKeyProvider);
  return ObjectCardApi(ref.watch(dioClientProvider));
});
