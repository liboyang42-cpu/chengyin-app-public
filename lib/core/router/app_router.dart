import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../providers.dart';
import '../../data/api/merchant_aftercare_api.dart';
import '../../data/api/merchant_customer_detail_api.dart';
import '../../data/api/merchant_review_api.dart';
import 'route_paths.dart';
import 'route_error_page.dart';
import 'door_entry.dart' show readInviterId;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../feature/activity/activity_detail_page.dart';
import '../../feature/topic/topic_pricing_page.dart';
import '../../feature/topic/topic_pricing_partner_page.dart';
import '../../feature/withdrawal/withdrawal_page.dart';
import '../../feature/withdrawal/withdrawal_records_page.dart';
import '../../feature/official/official_event_detail_page.dart';
import '../../feature/official/official_inbox_page.dart';
import '../../feature/official/official_mine_page.dart';
import '../../feature/official/official_publish_page.dart';
import '../../feature/activity/activity_list_page.dart';
import '../../feature/assets/assets_page.dart';
import '../../feature/account/invite_history_page.dart';
import '../../feature/account/income_detail_page.dart';
import '../../feature/creator/creator_center_page.dart';
import '../../feature/publish/publish_activity_page.dart';
import '../../feature/official/official_events_page.dart';
import '../../feature/merchant/merchant_discover_page.dart';
import '../../feature/auth/auth_controller.dart';
import '../../feature/auth/login_page.dart';
import '../../feature/auth/splash_page.dart';
import '../../feature/account/deregister_page.dart';
import '../../feature/club/club_apply_page.dart';
import '../../feature/club/club_checkin_detail_page.dart';
import '../../feature/club/club_customer_detail_page.dart';
import '../../feature/club/club_customers_page.dart';
import '../../feature/club/club_settlement_page.dart';
import '../../feature/club/club_create_page.dart';
import '../../feature/club/club_detail_page.dart';
import '../../feature/club/club_dissolution_blockers_page.dart';
import '../../feature/club/club_edit_page.dart';
import '../../feature/club/club_edition_report_page.dart';
import '../../feature/club/club_enroll_page.dart';
import '../../feature/club/club_event_ops_page.dart';
import '../../feature/club/club_governance_page.dart';
import '../../feature/club/club_group_code_page.dart';
import '../../feature/club/club_join_requests_page.dart';
import '../../feature/club/club_leaderboard_page.dart';
import '../../feature/club/club_notify_page.dart';
import '../../feature/club/club_roles_page.dart';
import '../../feature/club/club_topic_detail_page.dart';
import '../../feature/club/club_topic_story_page.dart';
import '../../feature/account/address_edit_page.dart';
import '../../feature/account/address_list_page.dart';
import '../../feature/coop/complaint_page.dart';
import '../../feature/merchant/merchant_city_node_create_page.dart';
import '../../feature/merchant/merchant_redemption_detail_page.dart';
import '../../feature/merchant/merchant_registrations_page.dart';
import '../../feature/merchant/node_template_edit_page.dart';
import '../../feature/merchant/merchant_coop_profile_page.dart';
import '../../feature/merchant/project_home_page.dart';
import '../../feature/merchant/project_players_page.dart';
import '../../feature/roam/stamp_album_page.dart';
import '../../feature/roam/stamp_camera_page.dart';
import '../../feature/club/club_list_page.dart';
import '../../feature/club/club_workbench_page.dart';
import '../../feature/coupon/coupon_code_page.dart';
import '../../feature/coupon/my_coupons_page.dart';
import '../../feature/coupon/my_published_coupons_page.dart';
import '../../feature/feed/feed_page.dart';
import '../../feature/im/im_chat_page.dart';
import '../../feature/im/im_list_page.dart';
import '../../feature/p3/growth/growth_center_page.dart';
import '../../feature/p3/growth/leaderboard_page.dart';
import '../../feature/p3/badges/badge_detail_logic.dart';
import '../../feature/p3/badges/badge_detail_page.dart';
import '../../feature/p3/badges/badge_wall_page.dart';
import '../../feature/legal/legal_doc_page.dart';
import '../../feature/mall/cart_page.dart';
import '../../feature/mall/product_detail_page.dart';
import '../../feature/mall/product_list_page.dart';
import '../../feature/map/map_page.dart';
import '../../feature/roam/city_node_voucher_page.dart';
import '../../feature/roam/city_stamp_page.dart';
import '../../feature/roam/roam_hangout_page.dart';
import '../../feature/roam/roam_history_page.dart';
import '../../feature/roam/roam_poi_detail_page.dart';
import '../../feature/roam/roam_session_page.dart';
import '../../feature/merchant/merchant_apply_page.dart';
import '../../feature/account/my_likes_page.dart';
import '../../feature/account/play_guide_page.dart';
import '../../feature/play/my_plays_page.dart';
import '../../feature/account/infomation_detail_page.dart';
import '../../feature/club/club_feed_page.dart';
import '../../feature/merchant/merchant_chapters_page.dart';
import '../../feature/merchant/merchant_recruit_page.dart';
import '../../feature/merchant/merchant_registration_edit_page.dart';
import '../../feature/merchant/topic_chapter_applications_page.dart';
import '../../feature/merchant/merchant_decor_page.dart';
import '../../feature/merchant/merchant_npc_avatar_page.dart';
import '../../feature/merchant/merchant_npc_edit_page.dart';
import '../../feature/merchant/merchant_node_npc_page.dart';
import '../../feature/merchant/merchant_npc_voice_page.dart';
import '../../feature/merchant/merchant_decor_story_page.dart';
import '../../feature/merchant/merchant_decor_gallery_page.dart';
import '../../feature/merchant/merchant_aftercare_detail_page.dart';
import '../../feature/merchant/merchant_aftercare_list_page.dart';
import '../../feature/merchant/merchant_customer_detail_page.dart';
import '../../feature/merchant/merchant_game_node_page.dart';
import '../../feature/merchant/merchant_operator_page.dart';
import '../../feature/merchant/merchant_public_reviews_page.dart';
import '../../feature/merchant/merchant_reviews_page.dart';
import '../../feature/profile/user_profile_page.dart';
import '../../feature/publish/my_projects_page.dart';
import '../../feature/square/square_compose_page.dart';
import '../../feature/square/square_governance_page.dart';
import '../../feature/square/square_drafts_page.dart';
import '../../feature/square/community_post_feature_gate.dart';
import '../../data/models/square_post.dart';
import '../../feature/play/play_ending_page.dart';
import '../../feature/play/team_lead_page.dart';
import '../../feature/play/circle_theme_play_page.dart';
import '../../feature/team/team_pages.dart';
import '../../feature/team/team_nearby_page.dart';
import '../../feature/play/stopwatch_game_page.dart';
import '../../feature/prefab/prefab_life_page.dart';
import '../../feature/account/participants_page.dart';
import '../../feature/profile/profile_edit_page.dart';
import '../../data/models/template_draft.dart';
import '../../feature/template/template_edit_page.dart';
import '../../feature/template/template_list_page.dart';
import '../../feature/template/template_detail_page.dart';
import '../../feature/template/template_intro_page.dart';
import '../../feature/template/template_name_page.dart';
import '../../feature/coop/coop_candidates_page.dart';
import '../../feature/coop/coop_invite_page.dart';
import '../../data/models/coop_invite.dart';
import '../../feature/coop/nearby_merchants_page.dart';
import '../../feature/coop/coop_finance_page.dart';
import '../../feature/coop/coop_pool_page.dart';
import '../../feature/coop/coop_perk_template_page.dart';
import '../../feature/coop/coop_mybiz_page.dart';
import '../../feature/coop/coop_settlement_detail_page.dart';
import '../../feature/coop/coop_list_page.dart';
import '../../feature/coop/coop_invite_detail_page.dart';
import '../../feature/merchant/merchant_city_node_page.dart';
import '../../feature/merchant/merchant_marketing_page.dart';
import '../../feature/merchant/merchant_ai_insight_page.dart';
import '../../feature/merchant/merchant_customer_page.dart';
import '../../feature/merchant/merchant_relation_page.dart';
import '../../feature/merchant/merchant_coop_page.dart';
import '../../feature/merchant/merchant_home_page.dart';
import '../../feature/merchant/batch_detail_page.dart';
import '../../feature/merchant/city_node_redeem_page.dart';
import '../../feature/merchant/merchant_ledger_page.dart';
import '../../feature/merchant/merchant_scan_page.dart';
import '../../feature/merchant/merchant_edit_page.dart';
import '../../feature/merchant/merchant_orders_page.dart';
import '../../feature/merchant/merchant_public_home_page.dart';
import '../../feature/merchant/merchant_subscription_page.dart';
import '../../feature/merchant/merchant_clubs_page.dart';
import '../../feature/merchant/merchant_predict_page.dart';
import '../../feature/orders/orders_page.dart';
import '../../feature/play/play_session_page.dart';
import '../../feature/points/points_page.dart';
import '../../feature/profile/profile_page.dart';
import '../../feature/participation/participation_page.dart';
import '../../feature/publish/publish_page.dart';
import '../../feature/publish/publish_pro_page.dart';
import '../../feature/publish/poi_pick_page.dart';
import '../../feature/search/search_page.dart';
import '../../feature/search/city_node_search_page.dart';
import '../../feature/search/search_result_page.dart';
import '../../feature/settings/about_page.dart';
import '../../feature/settings/settings_page.dart';
import '../../feature/shell/home_shell.dart';
import '../../feature/square/square_detail_page.dart';
import '../../feature/tickets/pass_page.dart';
import '../../feature/tickets/ticket_detail_page.dart';
import '../../feature/tickets/tickets_page.dart';
import '../../feature/account/door_entry_page.dart';
import '../../feature/square/square_list_page.dart';
import '../../feature/topic/topic_detail_page.dart';
import '../../feature/roam/roam_live_page.dart';
import '../../feature/roam/roam_live_controller.dart';
import '../../data/models/publish_draft.dart';

/// 整页需要登录的路由前缀(游客直接访问这些深链 → 兜底回首页;正常入口由
/// 各动作点的 requireLogin 弹窗处理)。浏览类页面(地图/活动/俱乐部/商城/广场/
/// 搜索等)对游客全开放。
///
/// ★ `/roam/stamp-album`、`/roam/stamp-camera` **不在本表**:这两页游客深链
///   要落地并由页面内的登录门解释(「登录后查看」+ 就地弹登录)。静默弹回首页
///   会让用户以为链接坏了(B1 模拟器报告 P1),且登完还是回不到目标页。
///   同型修复已扩到券域:`/coupons`、`/coupon/*`、`/merchant/coupons`
///   三条深链走页内登录门(b1-sim-coupon P1-1);资产域 `/assets` 同型
///   放行(#276 P1-1,PR #379 真跑:游客被静默弹回 /feed 无登录引导);
///   再扩到成长域:`/growth`(含 `/growth/leaderboard`)、`/badges` 同理
///   不在本表(B1 报告 P3 成长/徽章三条游客深链)。
/// ★ `/roam/stamp-album`、`/roam/stamp-camera`、`/growth`(含 `/growth/leaderboard`)、
///   `/badges` **不在本表**:这些页游客深链要落地并由页面内的登录门解释
///   (「登录后查看」+ 就地弹登录)。静默弹回首页会让用户以为链接坏了
///   (B1 模拟器报告 P1),且登完还是回不到目标页。
/// ★ `/tickets`、`/ticket/:id`、`/ticket/:id/pass` 同理**不在本表**(B1 报告
///   #231 P1):别人发来的票卡链接游客点开也该看到「登录后查看」+ 去哪登录,
///   而不是一张被弹回首页的死链接。
///
/// ★ `/invites`、`/deregister` **同理不在本表**(B1 账号域报告 P1-2,同口径
///   先例 #208/#231):两页本体各有页内登录门(AccountLoginGate),
///   游客落地能看到「需要登录」的解释与「去登录」,而不是无说明弹回首页。
///   再扩到票域:`/tickets`、`/ticket/*`(含出码页)、`/participations`
///   同范式(b1-sim-club-2 N1)。
const List<String> _loginRequiredPrefixes = <String>[
  '/publish', // 发布主题
  '/play', // 游玩打卡
  '/income', // 收益明细
  '/points', // 积分
  '/orders', // 我的订单(含待支付)
  '/merchant', // 商家侧(核销等)
  '/im', // 消息
  '/template/new', // 新建模板
  '/template/edit', // 新建模板编辑器
  '/creator', // 创作者中心
];

bool _needsLogin(String loc) {
  if (loc.startsWith('/merchant/public-home/')) return false;
  if (loc.startsWith('/merchant/reviews/public/')) return false;
  // 券域游客深链要落地,由页内登录门解释(b1-sim-coupon P1-1);
  // '/merchant' 其余商家页仍按整前缀拦。
  if (loc == '/merchant/coupons') return false;
  return _loginRequiredPrefixes.any((p) => loc == p || loc.startsWith('$p/'));
}

/// 带邀请凭证的团队深链在游客态也要落地:页面就地弹登录，
/// 重定向回主页会把 token 丢掉，交接方得再发一次链接。
bool _isMerchantTeamInvite(Uri uri) {
  final String token = uri.queryParameters['invite']?.trim() ?? '';
  return uri.path == '/merchant/team' && token.isNotEmpty;
}

const Map<String, String> _merchantRootRedirects = <String, String>{
  '/feed': kMerchantHomeRoute,
  '/roam': kMerchantHomeRoute,
  '/template-square': '/merchant/templates',
  '/clubs': '/merchant/relations',
  '/profile': '/merchant/profile',
};

/// 会话恢复未完成时,冷启动深链能否**不等恢复**直接落地(单一优先级:
/// 显式深链 > 会话恢复 > 默认 home,B1 play-4 N2)。
///
/// 只有「游客本来就能进、且落点不随恢复结果变」的路由够格:
///  - 需登录前缀(`/points`、`/im`…)不够格 —— 提前落地会在 token 其实
///    有效时把用户闪回首页,或让受保护页露一帧,双双破坏 fail-closed;
///  - 根 tab / `/login` 不够格 —— 落点取决于恢复出的角色(商家视角根
///    页重定向)与登录态,恢复完成前给答案只会闪一下再跳;
///  - 其余(活动列表、官方活动、公开口碑、券/资产/成长等页内登录门页)
///    与小程序 onLaunch 行为 1:1:静默登录不拦页面。
bool _isColdLinkLandable(String loc) {
  if (loc == '/login' || loc == '/splash') return false;
  if (_merchantRootRedirects.containsKey(loc)) return false;
  return !_needsLogin(loc);
}

/// 全局路由。游客可自由浏览;只有整页需登录的深链才兜底拦截,
/// 报名/发布/加入俱乐部等动作由页面内 requireLogin 弹窗触发登录。
final appRouterProvider = Provider<GoRouter>((ref) {
  // auth 状态变化时刷新路由(登录成功 / 401 登出)。
  final refresh = ValueNotifier<int>(0);
  String? pendingStartupLocation;
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: kHomeRoute,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final bool merchant = auth.user?.isMerchantView ?? false;
      final String home = merchant ? kMerchantHomeRoute : kHomeRoute;
      // 启动恢复未完成 → 停在 splash,避免误把持 token 的用户踢去登录
      if (!auth.initialized) {
        if (loc == '/splash') return null;
        // ★ 单一优先级:用户显式深链 > 会话恢复 > 默认 home(N2/§3.8)。
        //   小程序真源 onLaunch 的静默登录不拦页面 —— 游客可直达、且
        //   落点与角色无关的深链,首帧直接落地,恢复在后台继续;
        //   其余(需登录深链、根 tab、/login)落点取决于恢复结果,
        //   仍停 splash 等,fail-closed 语义一字不放宽。
        if (_isColdLinkLandable(loc)) return null;
        // 保留冷启动深链的完整 URI(包含 query)。若系统在 splash
        // 期间送来更新的深链，以最后一个用户意图为准。
        pendingStartupLocation = state.uri.toString();
        return '/splash';
      }
      // 恢复完成后先回到原始启动 URI；后续 redirect 仍会对需登录
      // 路由 fail-closed，不会因深链恢复绕过 auth gate。
      if (loc == '/splash') {
        final startupLocation = pendingStartupLocation;
        pendingStartupLocation = null;
        return startupLocation ?? home;
      }
      // 已登录却停在 /login → 收敛到主页
      if (auth.isLoggedIn && loc == '/login') {
        // Intent selects onboarding; server access remains authoritative.
        return state.uri.queryParameters['intent'] == 'merchant'
            ? kMerchantHomeRoute
            : home;
      }
      // 商家视角不渲染玩家五根页，同名根能力转到商家对应落点。
      if (merchant && _merchantRootRedirects.containsKey(loc)) {
        return _merchantRootRedirects[loc];
      }
      // 游客直接访问整页需登录的深链 → 兜底回主页(正常路径会先弹登录)
      if (!auth.isLoggedIn &&
          _needsLogin(loc) &&
          !_isMerchantTeamInvite(state.uri)) {
        return kHomeRoute;
      }
      return null;
    },
    // 未匹配深链 / 路由异常 → 人话错误页(默认是整屏英文 GoException)。
    errorBuilder: (context, state) => RouteErrorPage(error: state.error),
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      // 门口码冷启动落点:小程序由 wxacode scene 打进 pages/index onLoad,
      // App 侧深链带 `?scene=<32hex>`(及可选 `?inviter`/`?id`)到这里。
      // 游客也要能落地(解析失败由页面自己 toast 回首页),不进需登录表。
      GoRoute(
        path: '/door',
        builder: (context, state) => DoorEntryPage(
          scene: state.uri.queryParameters['scene'],
          inviterId: readInviterId(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          intent: state.uri.queryParameters['intent'],
        ),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/search/map',
        builder: (context, state) => CityNodeSearchPage(
          initialKeyword: state.uri.queryParameters['keyword'] ?? '',
          categoryId: int.tryParse(
            state.uri.queryParameters['categoryId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/search/result',
        builder: (context, state) => SearchResultPage(
          keyword: state.uri.queryParameters['keyword'] ?? '',
          categoryId: int.tryParse(
            state.uri.queryParameters['categoryId'] ?? '',
          ),
          startDate: state.uri.queryParameters['startDate'],
          endDate: state.uri.queryParameters['endDate'],
          minPrice: double.tryParse(
            state.uri.queryParameters['minPrice'] ?? '',
          ),
          maxPrice: double.tryParse(
            state.uri.queryParameters['maxPrice'] ?? '',
          ),
        ),
      ),
      // 设置页(对齐小程序 pages/shezhi)。
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _nativePage(
          context,
          state,
          _merchantLightIfMerchant(const SettingsPage()),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'about',
            // 商家视角要浅色:真源 pages/shezhi/about/index.wxml 根节点是
            // `{{isMerchantView ? 'theme-merchant' : 'theme-dark'}}`,与父页
            // `/settings` 同源。父页包了、子路由漏包时,商家点进「关于」看到的
            // 是一屏没人会看到的纯黑页(2026-09-18 复核)。
            pageBuilder: (context, state) => _nativePage(
              context,
              state,
              _merchantLightIfMerchant(const AboutPage()),
            ),
          ),
        ],
      ),
      // 法律文档:游客、未登录、登录流程内都要能打开(App Store 审核硬要求),
      // 所以**不进** _loginRequiredPrefixes。
      GoRoute(
        path: '/legal/:type',
        builder: (context, state) =>
            LegalDocPage(type: state.pathParameters['type'] ?? ''),
      ),
      GoRoute(
        path: '/publish',
        builder: (context, state) => _topicEditorLight(
          PublishPage(
            mode: int.tryParse(state.uri.queryParameters['mode'] ?? '') == 2
                ? 2
                : 1,
          ),
        ),
      ),
      // 专业发布编辑器(对齐小程序 pages/publish/fabu)。
      // ?id= 编辑既有主题;不带 id = 新建草稿。?scope=MERCHANT 与真源同款:
      // 决定 edit-detail/发布载荷/模板列表按商家口径走(否则记个人名下)。
      GoRoute(
        path: '/publish/pro',
        builder: (context, state) => _topicEditorLight(
          PublishProPage(
            topicId: publishEditTopicId(state.uri),
            mode: int.tryParse(state.uri.queryParameters['mode'] ?? '') == 2
                ? 2
                : 1,
            initialDraft: state.extra is PublishDraft
                ? state.extra as PublishDraft
                : null,
            initialClubId: int.tryParse(
              state.uri.queryParameters['clubId'] ?? '',
            ),
            merchantScope: state.uri.queryParameters['scope'] == 'MERCHANT',
            resumeDraftUuid: state.uri.queryParameters['draftUuid'],
          ),
        ),
      ),
      // 地图选点(替代小程序 wx.choosePoi / wx.chooseLocation)。
      // 返回 (name, latitude, longitude)。
      GoRoute(
        path: '/publish/poi',
        builder: (context, state) => const PoiPickPage(),
      ),
      GoRoute(path: '/assets', builder: (context, state) => const AssetsPage()),
      GoRoute(
        path: '/invites',
        builder: (context, state) => const InviteHistoryPage(),
      ),
      GoRoute(
        path: '/income',
        builder: (context, state) => const IncomeDetailPage(),
      ),
      // ★ '/creator' 之前只在路由名清单里,既没有 GoRoute 也没有页面 ——
      //   点进去是 404。现在补上。
      GoRoute(
        path: '/creator',
        builder: (context, state) => const CreatorCenterPage(),
      ),
      GoRoute(
        path: '/merchant/discover',
        // 商家域走浅色(门禁 merchant_routes_are_light 拦着)。
        builder: (context, state) =>
            _merchantLight(const MerchantDiscoverPage()),
      ),
      GoRoute(
        path: '/official-events',
        builder: (context, state) => const OfficialEventsPage(),
      ),
      GoRoute(
        path: '/publish/activity',
        builder: (context, state) =>
            _topicEditorLight(const PublishActivityPage()),
      ),
      GoRoute(path: '/im', builder: (context, state) => const ImListPage()),
      GoRoute(
        path: '/im/chat/:conversationId',
        builder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['conversationId'] ?? '') ?? 0;
          final extra = state.extra is Map<String, String>
              ? state.extra as Map<String, String>
              : const <String, String>{};
          return ImChatPage(
            conversationId: id,
            peerName: extra['name'] ?? '',
            peerAvatar: extra['avatar'] ?? '',
            peerMemberId: int.tryParse(extra['memberId'] ?? '') ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/coupons',
        builder: (context, state) => const MyCouponsPage(),
      ),
      GoRoute(
        path: '/coupon/:id/code',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return CouponCodePage(couponHistoryId: id);
        },
      ),
      GoRoute(path: '/points', builder: (context, state) => const PointsPage()),
      // 成长中心(对齐小程序 subpackageP3/pages/growthcenter)。
      GoRoute(
        path: '/growth',
        builder: (context, state) => const GrowthCenterPage(),
      ),
      GoRoute(
        path: '/growth/leaderboard',
        builder: (context, state) => const LeaderboardPage(),
      ),
      // 勋章墙(对齐小程序 subpackageP3/pages/badge-wall / badge-3d)。
      GoRoute(
        path: '/badges',
        builder: (context, state) => const BadgeWallPage(),
      ),
      GoRoute(
        path: '/badge',
        builder: (context, state) => BadgeDetailPage(
          params: state.extra is BadgeDetailParams
              ? state.extra as BadgeDetailParams
              : badgeDetailParams(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/activities',
        builder: (context, state) => const ActivityListPage(),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _merchantLightIfMerchant(ActivityDetailPage(activityId: id));
        },
      ),
      GoRoute(
        path: '/withdrawal',
        builder: (context, state) => const WithdrawalPage(),
      ),
      GoRoute(
        path: '/withdrawal-records',
        builder: (context, state) => const WithdrawalRecordsPage(),
      ),
      // 确认终价 = **恒浅**:小程序 `pages/topic/pricing/index.wxml` 根节点是
      // `theme-merchant`(index.wxss 第 1 行 `@import merchant-light.wxss`),
      // 且 pairs 台账 E24 把这一屏记在 role=merchant 名下。
      // App 侧此前没包浅色 → 整屏是玩家黑皮,与小程序对不上。
      GoRoute(
        path: '/topic/pricing/partner',
        builder: (context, state) {
          final query = state.uri.queryParameters;
          // 条款不从 query 带入:和小程序一样,页面自己用 topicId 走 preview 换服务器端条款。
          return TopicPricingPartnerPage(
            toType: query['toType'] ?? '',
            toId: int.tryParse(query['toId'] ?? ''),
            topicId: int.tryParse(query['topicId'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: '/topic/:id/pricing',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _merchantLight(TopicPricingPage(topicId: id));
        },
      ),
      // 官方活动域。小程序有三页,App 此前一页都没有(后端 16 个端点全没接)。
      GoRoute(
        path: '/official/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return OfficialEventDetailPage(id: id);
        },
      ),
      GoRoute(
        path: '/official-inbox',
        builder: (context, state) =>
            _merchantLightIfMerchant(const OfficialInboxPage()),
      ),
      GoRoute(
        path: '/official-publish',
        builder: (context, state) => const OfficialPublishPage(),
      ),
      GoRoute(
        path: '/official-mine',
        builder: (context, state) =>
            _merchantLightIfMerchant(const OfficialMinePage()),
      ),
      GoRoute(
        path: '/deregister',
        builder: (context, state) => const DeregisterPage(),
      ),
      GoRoute(
        path: '/merchant/decor',
        builder: (context, state) => _merchantLight(const MerchantDecorPage()),
      ),
      GoRoute(
        path: '/merchant/npc',
        builder: (context, state) =>
            _merchantLight(const MerchantNpcEditPage()),
      ),
      GoRoute(
        path: '/merchant/npc/avatar',
        builder: (context, state) =>
            _merchantLight(const MerchantNpcAvatarPage()),
      ),
      GoRoute(
        path: '/merchant/npc/voice',
        builder: (context, state) =>
            _merchantLight(const MerchantNpcVoicePage()),
      ),
      GoRoute(
        path: '/merchant/decor/story',
        builder: (context, state) =>
            _merchantLight(const MerchantDecorStoryPage()),
      ),
      GoRoute(
        path: '/merchant/decor/gallery',
        builder: (context, state) =>
            _merchantLight(const MerchantDecorGalleryPage()),
      ),
      GoRoute(
        path: '/merchant/chapters',
        builder: (context, state) =>
            _merchantLight(const MerchantChaptersPage()),
      ),
      // 商家承接一条路线(自由探索按章节申请 / 经典定向按站点报名)。
      GoRoute(
        path: '/merchant/recruit/:topicId',
        builder: (context, state) => _merchantLight(
          MerchantRecruitPage(
            topicId: int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0,
          ),
        ),
      ),
      // 点位上的 AI 角色(章节节点 NPC,与店铺形象 `/merchant/npc` 是两套)。
      GoRoute(
        path: '/merchant/node-npc/:nodeId',
        builder: (context, state) => _merchantLight(
          MerchantNodeNpcPage(
            nodeId: int.tryParse(state.pathParameters['nodeId'] ?? '') ?? 0,
            nodeName: state.extra is String ? state.extra! as String : null,
          ),
        ),
      ),
      // 改一条已提交的报名(仅审核中/已驳回,且主题未开始)。
      GoRoute(
        path: '/merchant/registration/:id/edit',
        builder: (context, state) => _merchantLight(
          MerchantRegistrationEditPage(
            registrationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ),
      // 主办方:审商家的章节承接申请 + 邀商家来接。
      GoRoute(
        path: '/merchant/topic/:topicId/applications',
        builder: (context, state) => _merchantLight(
          TopicChapterApplicationsPage(
            topicId: int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0,
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/customers/:customerMemberId',
        builder: (context, state) {
          final api = ref.watch(merchantCustomerDetailApiProvider);
          return _merchantLight(
            MerchantCustomerDetailPage(
              api: api,
              customerMemberId:
                  int.tryParse(
                    state.pathParameters['customerMemberId'] ?? '',
                  ) ??
                  0,
            ),
          );
        },
      ),
      GoRoute(
        path: '/merchant/aftercare',
        builder: (context, state) {
          final api = ref.watch(merchantAftercareApiProvider);
          return _merchantLight(MerchantAftercareListPage(api: api));
        },
      ),
      GoRoute(
        path: '/merchant/aftercare/:refundId',
        builder: (context, state) {
          final api = ref.watch(merchantAftercareApiProvider);
          return _merchantLight(
            MerchantAftercareDetailPage(
              api: api,
              refundId:
                  int.tryParse(state.pathParameters['refundId'] ?? '') ?? 0,
            ),
          );
        },
      ),
      GoRoute(
        path: '/merchant/reviews',
        builder: (context, state) {
          final api = ref.watch(merchantReviewApiProvider);
          return _merchantLight(MerchantReviewsPage(api: api));
        },
      ),
      // 口碑公开页:商家把链接发给顾客,未登录也能看和提交。
      // ★ 这一条恒浅色,不按角色切:小程序只有 pages/merchant/reviews/index
      //   一个页,公开与商家共用、靠 query 分辨,无条件 @import merchant-light.wxss
      //   —— 商家把链接发给顾客,顾客看到的也该是浅色。
      //   (注释别写进 builder 里:门禁按 `),` 截断扫描窗口,注释里带这个
      //   序列会让它提前收工,把 wrap 挡在窗口外,判成「没包」——2026-09-17 实撞。)
      // ★ 解析不出数字**不兜 0**(同下面 public-home 口径):0 会撞页面参数
      //   校验变红屏(b1-sim-merchant-4 P2),「链接缺主体」是页内
      //   「链接参数无效」态。
      GoRoute(
        path: '/merchant/reviews/public/:merchantRowId/:ownerMemberId',
        builder: (context, state) {
          final api = ref.watch(merchantReviewApiProvider);
          final uploadImage = ref.watch(publishApiProvider).uploadImage;
          return _merchantLight(
            MerchantPublicReviewsPage(
              api: api,
              merchantRowId: int.tryParse(
                state.pathParameters['merchantRowId'] ?? '',
              ),
              merchantOwnerMemberId: int.tryParse(
                state.pathParameters['ownerMemberId'] ?? '',
              ),
              uploadImage: uploadImage,
            ),
          );
        },
      ),
      GoRoute(
        path: '/merchant/game-node/:activityId',
        builder: (context, state) => _merchantLight(
          MerchantGameNodePage(
            ownerMemberId: ref.watch(authControllerProvider).user?.id ?? 0,
            activityId:
                int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0,
            initialNodeId: int.tryParse(
              state.uri.queryParameters['nodeId'] ?? '',
            ),
          ),
        ),
      ),
      // 经营团队:邀请深链在未登录时也要能落地(登录后就地叠加)。
      GoRoute(
        path: '/merchant/team',
        builder: (context, state) => _merchantLight(
          MerchantTeamRoutePage(
            incomingInviteToken: state.uri.queryParameters['invite'],
          ),
        ),
      ),
      GoRoute(
        path: '/user/:memberId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['memberId'] ?? '') ?? 0;
          return UserProfilePage(memberId: id);
        },
      ),
      GoRoute(
        path: '/club-feed',
        builder: (context, state) => const ClubFeedPage(),
      ),
      GoRoute(
        path: '/infomation/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return InfomationDetailPage(id: id);
        },
      ),
      GoRoute(
        path: '/my-projects',
        builder: (context, state) {
          final String? type = state.uri.queryParameters['type'];
          final MyProjectTypeTab initialTab = switch (type) {
            'template' => MyProjectTypeTab.template,
            'club_activity' => MyProjectTypeTab.activity,
            _ => MyProjectTypeTab.topic,
          };
          return MyProjectsPage(initialTab: initialTab);
        },
      ),
      GoRoute(
        path: '/square/compose',
        builder: (context, state) => SquareComposePage(
          initialPost: state.extra is SquarePost
              ? state.extra! as SquarePost
              : null,
          initialIntent: squareComposeIntentFromValue(
            state.uri.queryParameters['intent'],
          ),
        ),
      ),
      GoRoute(
        path: '/square/drafts',
        builder: (context, state) => const SquareDraftsPage(),
      ),
      GoRoute(
        path: '/square/governance',
        builder: (context, state) => const SquareGovernancePage(),
      ),
      GoRoute(
        path: '/my-plays',
        builder: (context, state) => const MyPlaysPage(),
      ),
      GoRoute(
        path: '/participations',
        builder: (context, state) => const ParticipationPage(),
      ),
      GoRoute(
        path: '/play/:activityId/ending',
        builder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0;
          // 自玩(主题直玩)会话没有 activityId,同 `/play/:activityId` 一样从 query 收 topicId。
          return PlayEndingPage(
            activityId: id,
            topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: '/team-lead/:activityId',
        builder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0;
          return TeamLeadPage(activityId: id);
        },
      ),
      GoRoute(
        path: '/play/circle/:topicId',
        builder: (context, state) => CircleThemePlayPage(
          topicId: int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0,
          themeCode: state.uri.queryParameters['themeCode'],
          inviteCode: state.uri.queryParameters['inviteCode'],
        ),
      ),
      GoRoute(
        path: '/team/join',
        builder: (context, state) =>
            TeamJoinPage(code: state.uri.queryParameters['code'] ?? ''),
      ),
      // ★ 必须排在 `/team/:teamId` **前面**:go_router 按声明顺序匹配,
      //   反过来的话 `/team/nearby` 会被动态段吃掉(`teamId='nearby'` → 0)。
      GoRoute(
        path: '/team/nearby',
        builder: (context, state) => const TeamNearbyPage(),
      ),
      GoRoute(
        path: '/team/:teamId',
        builder: (context, state) => TeamDetailPage(
          teamId: int.tryParse(state.pathParameters['teamId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/play/stopwatch',
        pageBuilder: (context, state) => _nativePage(
          context,
          state,
          StopwatchGamePage(
            targetSeconds:
                double.tryParse(state.uri.queryParameters['target'] ?? '') ??
                10,
            revealMode: switch (state.uri.queryParameters['reveal']) {
              'never' => StopwatchRevealMode.never,
              'always' => StopwatchRevealMode.always,
              _ => StopwatchRevealMode.delay,
            },
            tolerance:
                double.tryParse(state.uri.queryParameters['tolerance'] ?? '') ??
                0.05,
          ),
        ),
      ),
      GoRoute(
        path: '/play-guide',
        builder: (context, state) => const PlayGuidePage(),
      ),
      // ★ 必须排在 `/play/:activityId` 前面:go_router 按声明顺序匹配,
      //   反过来的话 `/play/prefab` 会被动态段吃掉(`activityId='prefab'`)。
      GoRoute(
        path: '/play/prefab',
        builder: (context, state) => PrefabLifePage(
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
          mock: state.uri.queryParameters['mock'] == '1',
        ),
      ),
      GoRoute(
        path: '/my-likes',
        builder: (context, state) => const MyLikesPage(),
      ),
      GoRoute(
        path: '/participants',
        builder: (context, state) => const ParticipantsPage(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const ProfileEditPage(),
      ),
      GoRoute(
        path: '/template/new',
        pageBuilder: (context, state) => _nativePage(
          context,
          state,
          _topicEditorLight(const TemplateNamePage()),
        ),
      ),
      GoRoute(
        path: '/template/edit',
        pageBuilder: (context, state) => _nativePage(
          context,
          state,
          _topicEditorLight(
            TemplateEditPage(
              initialTitle: state.uri.queryParameters['templateName'] ?? '',
              // 从模板库「套用」过来时带初值;直接进编辑器时是 null。
              // ★ 用 is 判类型而不是强转:extra 是 Object?,别的调用方将来传别的东西
              //   进来时该安静忽略,不是崩在这里。
              seed: state.extra is TemplateDraft
                  ? state.extra! as TemplateDraft
                  : null,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/template/intro',
        pageBuilder: (context, state) => _nativePage(
          context,
          state,
          _topicEditorLight(const TemplateIntroPage()),
        ),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) =>
            _merchantLightIfMerchant(const TemplateListPage()),
      ),
      GoRoute(
        path: '/template/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _merchantLightIfMerchant(TemplateDetailPage(id: id));
        },
      ),
      GoRoute(
        path: '/coop/invite',
        builder: (context, state) {
          final int? rawType = int.tryParse(
            state.uri.queryParameters['type'] ?? '',
          );
          final bool invalidLegacyType = rawType == 2;
          return _merchantLightIfMerchant(
            CoopInvitePage(
              type: rawType == 0
                  ? CoopInviteType.merchant
                  : CoopInviteType.club,
              toId: invalidLegacyType
                  ? null
                  : int.tryParse(state.uri.queryParameters['toId'] ?? ''),
              toName: invalidLegacyType
                  ? null
                  : state.uri.queryParameters['toName'],
              originApplyId: invalidLegacyType || rawType == 0
                  ? null
                  : int.tryParse(
                      state.uri.queryParameters['originApplyId'] ?? '',
                    ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/coop/invite/:topicId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0;
          final int? rawType = int.tryParse(
            state.uri.queryParameters['type'] ?? '',
          );
          final bool invalidLegacyType = rawType == 2;
          return _merchantLightIfMerchant(
            CoopInvitePage(
              topicId: id > 0 ? id : null,
              topicName:
                  state.uri.queryParameters['topicName'] ??
                  state.uri.queryParameters['name'],
              type: rawType == 0
                  ? CoopInviteType.merchant
                  : CoopInviteType.club,
              toId: invalidLegacyType
                  ? null
                  : int.tryParse(state.uri.queryParameters['toId'] ?? ''),
              toName: invalidLegacyType
                  ? null
                  : state.uri.queryParameters['toName'],
              originApplyId: invalidLegacyType || rawType == 0
                  ? null
                  : int.tryParse(
                      state.uri.queryParameters['originApplyId'] ?? '',
                    ),
              // 商家员工代 owner 主题回邀约时带的归属标记,原样透传到提交体。
              scope: state.uri.queryParameters['scope'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/coop/nearby',
        // 真源入口都带 topicId(发件箱「再邀别人」/merchantinfo/邀约页),
        // 参数原样交给页面自己按 positiveTopicId 判 —— 不在这里兜 0,
        // 也不在这里把坏参数静默丢掉(丢了页面会假装是一次普通搜索)。
        builder: (context, state) => _merchantLight(
          NearbyMerchantsPage(
            topicIdRaw: state.uri.queryParameters['topicId'],
            topicName: state.uri.queryParameters['topicName'],
          ),
        ),
      ),
      GoRoute(
        path: '/coop/candidates/:topicId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0;
          return _merchantLight(CoopCandidatesPage(topicId: id));
        },
      ),
      GoRoute(
        path: '/coop-finance',
        builder: (context, state) => _merchantLight(const CoopFinancePage()),
      ),
      GoRoute(
        path: '/coop-pool',
        builder: (context, state) => _merchantLight(const CoopPoolPage()),
      ),
      GoRoute(
        path: '/coop/list',
        builder: (context, state) => _merchantLightIfMerchant(
          CoopListPage(
            initialTab: state.uri.queryParameters['tab'] ?? 'received',
          ),
        ),
      ),
      GoRoute(
        path: '/coop/invite-detail',
        // 浅色口径跟它父页 `/coop/list` 一致(两条路由同属商家工作域,
        // 一深一浅会在流程中间插一次明暗跳变)。
        builder: (context, state) => _merchantLightIfMerchant(
          CoopInviteDetailPage(
            inviteId: state.uri.queryParameters['inviteId'],
            box: state.uri.queryParameters['box'] ?? 'received',
          ),
        ),
      ),
      GoRoute(
        path: '/coop/perk-templates',
        builder: (context, state) =>
            _merchantLight(const CoopPerkTemplatePage()),
      ),
      GoRoute(
        path: '/coop/mybiz',
        builder: (context, state) => _merchantLight(const CoopMyBizPage()),
      ),
      GoRoute(
        path: '/coop/settlement-detail',
        builder: (context, state) => _merchantLight(
          CoopSettlementDetailPage(
            source: state.uri.queryParameters['source'] ?? '',
            recordId: state.uri.queryParameters['recordId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/marketing/ai-insight',
        builder: (context, state) =>
            _merchantLight(const MerchantAiInsightPage()),
      ),
      GoRoute(
        path: '/merchant/city-nodes',
        builder: (context, state) =>
            _merchantLight(const MerchantCityNodePage()),
      ),
      GoRoute(
        path: '/merchant/coop-profile',
        builder: (context, state) =>
            _merchantLight(const MerchantCoopProfilePage()),
      ),
      GoRoute(
        path: '/project/home',
        builder: (context, state) => _merchantLight(
          ProjectHomePage(scope: state.uri.queryParameters['scope']),
        ),
      ),
      GoRoute(
        path: '/project/home/:topicId',
        builder: (context, state) => _merchantLight(
          ProjectHomePage(
            topicId: int.tryParse(state.pathParameters['topicId'] ?? ''),
            scope: state.uri.queryParameters['scope'],
          ),
        ),
      ),
      GoRoute(
        path: '/project/players',
        builder: (context, state) => _merchantLight(const ProjectPlayersPage()),
      ),
      GoRoute(
        path: '/project/players/:topicId',
        builder: (context, state) => _merchantLight(
          ProjectPlayersPage(
            topicId: int.tryParse(state.pathParameters['topicId'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/registrations',
        builder: (context, state) =>
            _merchantLight(const MerchantRegistrationsPage()),
      ),
      GoRoute(
        path: '/merchant/node-template',
        builder: (context, state) =>
            _merchantLight(const NodeTemplateEditPage()),
      ),
      GoRoute(
        path: '/merchant/node-template/:id',
        builder: (context, state) => _merchantLight(
          NodeTemplateEditPage(
            templateId: int.tryParse(state.pathParameters['id'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/city-nodes/redeem',
        builder: (context, state) => _merchantLight(const CityNodeRedeemPage()),
      ),
      GoRoute(
        path: '/merchant/city-nodes/create',
        builder: (context, state) =>
            _merchantLight(const MerchantCityNodeCreatePage()),
      ),
      GoRoute(
        path: '/merchant/customers',
        builder: (context, state) =>
            _merchantLight(const MerchantCustomerPage()),
      ),
      GoRoute(
        path: '/merchant/apply',
        builder: (context, state) => _merchantLight(const MerchantApplyPage()),
      ),
      GoRoute(
        path: '/merchant/coop',
        builder: (context, state) => _merchantLight(const MerchantCoopPage()),
      ),
      GoRoute(
        path: '/merchant/ledger',
        builder: (context, state) => _merchantLight(
          MerchantLedgerPage(
            initialView: state.uri.queryParameters['view'] ?? 'redemption',
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/ledger/batch/:batchId',
        builder: (context, state) => _merchantLight(
          BatchDetailPage(
            // 解析不出数字就**不要兜 0**:0 会去打一个不存在的批次,
            // 而「这个链接缺标识」是页面上一个真实状态(对齐小程序 missing-param)。
            batchId: int.tryParse(state.pathParameters['batchId'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/scan',
        builder: (context, state) => _merchantLight(const MerchantScanPage()),
      ),
      GoRoute(
        path: '/merchant/edit',
        builder: (context, state) => _merchantLight(const MerchantEditPage()),
      ),
      GoRoute(
        path: '/merchant/orders',
        builder: (context, state) => _merchantLight(const MerchantOrdersPage()),
      ),
      GoRoute(
        path: '/merchant/public-home/member/:memberId',
        // 解析不出数字就**不要兜 0**:0 会去打一个不存在的商家 id,
        // 而「这个链接缺主体」是页面上一个真实状态(对齐小程序 invalid 态)。
        builder: (context, state) => _merchantLight(
          MerchantPublicHomePage(
            memberId: int.tryParse(state.pathParameters['memberId'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        // Legacy App 深链的 `:id` 是商家档案 id；不能静默重解释为 memberId。
        path: '/merchant/public-home/:id',
        builder: (context, state) => _merchantLight(
          MerchantPublicHomePage(
            merchantId: int.tryParse(state.pathParameters['id'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/merchant/subscription',
        builder: (context, state) =>
            _merchantLight(const MerchantSubscriptionPage()),
      ),
      GoRoute(
        path: '/merchant/clubs',
        builder: (context, state) => _merchantLight(const MerchantClubsPage()),
      ),
      GoRoute(
        path: '/merchant/coupons',
        builder: (context, state) =>
            _merchantLight(const MyPublishedCouponsPage()),
      ),
      GoRoute(
        path: '/merchant/predict',
        builder: (context, state) =>
            _merchantLight(const MerchantPredictPage()),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => OrdersPage(
          initialDetailId: int.tryParse(
            state.uri.queryParameters['detailId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/address',
        builder: (context, state) => const AddressListPage(),
      ),
      GoRoute(
        path: '/address/edit',
        builder: (context, state) => const AddressEditPage(),
      ),
      GoRoute(
        path: '/address/edit/:id',
        builder: (context, state) => AddressEditPage(
          addressId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/complaint',
        builder: (context, state) => const ComplaintPage(),
      ),
      GoRoute(
        path: '/tickets',
        // 真源票夹已无「路线/场次」tab:调用方仍带的 stype 参数与真源一样被忽略,
        // 只有 focusId 有效(定位到那张票)。
        builder: (context, state) => TicketsPage(
          focusId: int.tryParse(state.uri.queryParameters['focusId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/ticket/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return TicketDetailPage(registrationId: id);
        },
      ),
      GoRoute(
        path: '/ticket/:id/pass',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return PassPage(registrationId: id);
        },
      ),
      GoRoute(
        path: '/club/apply',
        builder: (context, state) => const ClubApplyPage(),
      ),
      GoRoute(
        path: '/club/create',
        builder: (context, state) => const ClubCreatePage(),
      ),
      GoRoute(
        path: '/club/group-code',
        builder: (context, state) => ClubGroupCodePage(
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
          activityName: state.uri.queryParameters['activityName'],
          topicName: state.uri.queryParameters['topicName'],
        ),
      ),
      GoRoute(
        path: '/club/workbench',
        builder: (context, state) => ClubWorkbenchPage(
          clubId: int.tryParse(state.uri.queryParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/club/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return ClubDetailPage(clubId: id);
        },
      ),
      GoRoute(
        path: '/club/:id/edit',
        builder: (context, state) => ClubEditPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/enroll',
        builder: (context, state) => ClubEnrollPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          // E-07:主题页「核销台账」带 topicId 来,到达即展开那一团。
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/club/:id/join-requests',
        builder: (context, state) => ClubJoinRequestsPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/customers',
        builder: (context, state) => ClubCustomersPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/customers/:memberId',
        builder: (context, state) => ClubCustomerDetailPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          memberId: int.tryParse(state.pathParameters['memberId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/checkin/:registrationId',
        builder: (context, state) => ClubCheckinDetailPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          registrationId:
              int.tryParse(state.pathParameters['registrationId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/settlement',
        builder: (context, state) => ClubSettlementPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/merchant/redemption/:type/:id',
        builder: (context, state) => _merchantLight(
          MerchantRedemptionDetailPage(
            recordType: state.pathParameters['type'] ?? '',
            recordId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/roam/stamp-album',
        builder: (context, state) => const StampAlbumPage(),
      ),
      GoRoute(
        path: '/roam/stamp-camera',
        builder: (context, state) => const StampCameraPage(),
      ),
      GoRoute(
        path: '/club/:id/leaderboard',
        builder: (context, state) => ClubLeaderboardPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/edition-report',
        builder: (context, state) => ClubEditionReportPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/dissolution-blockers',
        builder: (context, state) => ClubDissolutionBlockersPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/club/:id/event-ops',
        builder: (context, state) => ClubEventOpsPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
          recurrence: state.uri.queryParameters['recurrence'],
          // E-07:主题页「管理场次」带着 topicId 来,页面要预选到它。
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/club/:id/governance',
        builder: (context, state) => ClubGovernancePage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          mode: state.uri.queryParameters['mode'] ?? 'manage',
          targetType: state.uri.queryParameters['targetType'],
          targetId: int.tryParse(state.uri.queryParameters['targetId'] ?? ''),
          memberId: int.tryParse(
            state.uri.queryParameters['memberId'] ??
                state.uri.queryParameters['targetMemberId'] ??
                '',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/notify',
        builder: (context, state) => ClubNotifyPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/roles',
        builder: (context, state) => ClubRolesPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
          memberId: int.tryParse(state.uri.queryParameters['memberId'] ?? ''),
        ),
      ),
      // 俱乐部 · 活动详情 / 剧情与玩法(4-B,只追加)。
      GoRoute(
        path: '/club/:id/topic/:topicId',
        builder: (context, state) => ClubTopicDetailPage(
          clubId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          topicId: int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0,
          activityId: int.tryParse(
            state.uri.queryParameters['activityId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/club/:id/topic/:topicId/story',
        // 商家视角要浅色:小程序真源 pages/club/topic-story 按 isMerchantViewer
        // 切 theme-merchant(原来写死 theme-dark,商家进来就是一屏纯黑)。
        builder: (context, state) => _merchantLightIfMerchant(
          ClubTopicStoryPage(
            topicId: int.tryParse(state.pathParameters['topicId'] ?? '') ?? 0,
            clubId: int.tryParse(state.pathParameters['id'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/mall',
        builder: (context, state) => const ProductListPage(),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartPage()),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailPage(
          productId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/square',
        builder: (context, state) => const CommunityPostFeatureGateView(
          access: CommunityPostAccess.read,
          child: SquareListPage(),
        ),
      ),
      GoRoute(
        path: '/square/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return CommunityPostFeatureGateView(
            access: CommunityPostAccess.read,
            child: SquareDetailPage(postId: id),
          );
        },
      ),
      GoRoute(
        path: '/topic/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return TopicDetailPage(topicId: id);
        },
      ),
      GoRoute(
        path: '/play/:activityId',
        builder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0;
          return PlaySessionPage(
            activityId: id,
            topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
            registrationId: int.tryParse(
              state.uri.queryParameters['registrationId'] ?? '',
            ),
          );
        },
      ),
      // 漫游域(对齐小程序 subpackageRoam)。
      GoRoute(
        path: '/roam/poi/:poiId',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['poiId'] ?? '') ?? 0;
          return RoamPoiDetailPage(poiId: id);
        },
      ),
      GoRoute(
        path: '/roam/citynode-code',
        builder: (context, state) => CityNodeVoucherPage(
          poiId: int.tryParse(state.uri.queryParameters['poiId'] ?? ''),
          name: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/roam/history',
        builder: (context, state) => const RoamHistoryPage(),
      ),
      GoRoute(
        path: '/roam/nearby',
        builder: (context, state) => RoamHangoutPage(
          hangoutId: int.tryParse(state.uri.queryParameters['hangoutId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/roam/citystamp',
        builder: (context, state) => CityStampPage(
          kind: state.uri.queryParameters['kind'] ?? 'sign',
          place: state.uri.queryParameters['place'],
          shot: state.uri.queryParameters['shot'],
        ),
      ),
      GoRoute(
        path: '/roam/session',
        builder: (context, state) => RoamSessionPage(
          ts: int.tryParse(state.uri.queryParameters['ts'] ?? '') ?? 0,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => _merchantLight(
          MerchantHomeShell(
            navigationShell: navigationShell,
            child: navigationShell,
          ),
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: kMerchantHomeRoute,
                builder: (context, state) =>
                    _merchantLight(const MerchantHomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/merchant/marketing',
                builder: (context, state) =>
                    _merchantLight(const MerchantMarketingPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/merchant/templates',
                builder: (context, state) =>
                    _merchantLight(const TemplateListPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/merchant/relations',
                builder: (context, state) =>
                    _merchantLight(const MerchantRelationPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/merchant/profile',
                builder: (context, state) =>
                    _merchantLight(const ProfilePage()),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) {
            final RoamLivePhase roamPhase = state.matchedLocation == kRoamRoute
                ? ref.watch(roamLiveControllerProvider).phase
                : RoamLivePhase.idle;
            final bool showBottomNavigation =
                state.matchedLocation != kRoamRoute ||
                roamPhaseShowsPlayerTabBar(roamPhase);
            return HomeShell(
              bottomNavigationBarVisible: showBottomNavigation,
              navigationShell: navigationShell,
              child: navigationShell,
            );
          },
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/feed',
                builder: (context, state) => const FeedPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/roam',
                builder: (context, state) => const RoamLivePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/template-square',
                builder: (context, state) => const TemplateListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/clubs',
                builder: (context, state) => const ClubListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/map', builder: (context, state) => const MapPage()),
      GoRoute(
        path: '/roam/official',
        builder: (context, state) => RoamLivePage(
          eventId: int.tryParse(state.uri.queryParameters['eventId'] ?? ''),
          missionCode: state.uri.queryParameters['missionCode'],
        ),
      ),
    ],
  );
});

Page<void> _nativePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final TargetPlatform platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoPage<void>(
      key: state.pageKey,
      name: state.name,
      arguments: state.extra,
      restorationId: state.pageKey.value,
      child: child,
    );
  }
  return MaterialPage<void>(
    key: state.pageKey,
    name: state.name,
    arguments: state.extra,
    restorationId: state.pageKey.value,
    child: child,
  );
}

/// 浅色域包装 —— Material **和** Cupertino 两套主题一起换。
///
/// ⚠️ 只包 Material `Theme` 是**不够的**:`ThemeData.cupertinoOverrideTheme`
///   在 `CupertinoApp` 下根本不生效 —— Material `Theme.build` 只要发现祖先已有
///   CupertinoTheme(`main.dart` 的根 `CupertinoApp.router` 就是),就把**祖先那份
///   数据**原样转发布出去(framework `material/theme.dart`
///   `_inheritedCupertinoThemeData`),自己那份 override 被丢掉。于是
///   `CupertinoNavigationBar` 标题、`CupertinoPageScaffold` 底色仍读根暗色:
///   浅色商家页上表现为「白字压浅底」(2026-09-17 模拟器实拍 254 vs 243,≈1.1:1)
///   与未登录门**整页纯黑** —— 所以浅色域必须**再包一层 `CupertinoTheme`**。
///   (源码 grep 门禁 `merchant_routes_are_light_test.dart` 对这条恒绿,
///   渲出来到底什么颜色由 `test/core/router/merchant_team_invite_route_test.dart` 锁。)
///
/// Cupertino 那半从 [ThemeData] 现推,不另写一份常量 —— 少一个会漂移的真源。
Widget _lightScope(ThemeData data, Widget child) => Theme(
  data: data,
  child: CupertinoTheme(
    data: CupertinoThemeData(
      brightness: data.brightness,
      primaryColor: data.colorScheme.primary,
      scaffoldBackgroundColor: data.scaffoldBackgroundColor,
      barBackgroundColor: data.scaffoldBackgroundColor,
    ),
    child: child,
  ),
);

/// 商家工作台 = **浅色**。小程序侧 `pages/merchant/**` 每页都 `@import merchant-light.wxss`
/// 并在 onShow 调 `merchantPageShow()` 切浅色导航栏(utils/merchant-theme.js),
/// 离开就恢复暗色 —— 所以这是**逐路由包装**,不是全局主题切换。
///
/// ⚠️ 新增 `/merchant/**` 路由必须包这一层,否则那一页会是黑底、和相邻页对不上。
///   `test/merchant_routes_are_light_test.dart` 门禁锁着这条。
Widget _merchantLight(Widget child) =>
    _lightScope(AppTheme.merchantLight(), child);

/// 主题编辑器 / 创建域 = **浅色**(决策 D10⑥,角色外观见 D6③「主题编辑器=浅色」)。
/// 小程序侧对应页根节点套 `.theme-topic-editor`(2026-09-17 快照 grep 实测):
/// pages/publish/fabu · publish/temp · publish/templateadd · publish/template-intro ·
/// publish/activity · publish/simple —— App 侧就是 `/publish*` 与 `/template/{new,edit,intro}`。
/// merchant/citynode/create 同样挂这个 class,但它已在 `_merchantLight` 那条恒浅链上。
///
/// ⚠️ 用 [AppTheme.topicEditorLight] 而**不是** `merchantLight()`:两域同底色/白卡/正文,
///   但**卡片起层手段相反**。逐块比对 tokens.wxss(两边各 122 个变量,去掉 var() 间接后
///   真差异 **21 处**;早先这里写的「49 处」把 `var(--cy-ref-gray-900)` 与字面
///   `#33363C` 这类同值写法也算了进去,是错的):
///   · **卡片**:`.cy-card` 的描边读 `--cy-border-card`(= `--cy-color-border-subtle`,
///     本域 `#E8E8E8`)、投影读 `--cy-shadow-card`(本域 `none`)—— 商家域正好反过来
///     (投影 `rgba(15,23,43,.48)`、描边透明)。这是**看得见**的一处,已由
///     `topicEditorLight()` 收敛,门禁锁在 topic_editor_routes_are_light_test.dart。
///   · 其余 20 处(status-* 软底/`bgGlass` `.96` vs `.88`/skeleton/text-placeholder/
///     `--cy-color-ai-*` 13 条只有本域有)在 `lib/feature/publish`、`lib/feature/template`
///     里**没有消费端**,当前取的是商家值 = 已知偏差,待 P0 统一收敛。
///   `lib/core/theme/**` 归共用层 P0 线;这里只补了有消费端的那一处,没有另起主题族。
///
/// ⚠️ 新增这两组路由必须包这一层,否则那一页会是黑底(与相邻创建页对不上)。
///   `test/topic_editor_routes_are_light_test.dart` 门禁锁着这条。
Widget _topicEditorLight(Widget child) =>
    _lightScope(AppTheme.topicEditorLight(), child);

/// 条件浅色:8 个页面在小程序里按**商家视角**切主题,不是整条路由恒浅 ——
/// 同一条路由,玩家看到暗色、商家看到浅色(pages/shezhi、pages/activity/detail、
/// pages/template… 都在 onShow 里 `if (isMerchantView) merchantPageShow()`)。
///
/// 判据走 [User.effectiveRole],它逐字镜像后端 `RoleServiceImpl.resolveRole`
/// —— **不要在这里另写一套 `role == 'merchant'`**,role 未回填时要靠 userType 兜底,
/// 少这一条会让一批商家在 App 里看到玩家皮。
Widget _merchantLightIfMerchant(Widget child) => Consumer(
  builder: (BuildContext context, WidgetRef ref, Widget? _) {
    final bool merchant =
        ref.watch(authControllerProvider).user?.isMerchantView ?? false;
    return merchant ? _lightScope(AppTheme.merchantLight(), child) : child;
  },
);
