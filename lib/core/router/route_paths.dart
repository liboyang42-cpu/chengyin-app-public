/// App 的一级首页。它不是 `/`，所有“回首页”行为都应复用该常量。
const String kHomeRoute = '/feed';
const String kRoamRoute = '/roam';
const String kPublishRoute = '/template-square';
const String kClubsRoute = '/clubs';
const String kProfileRoute = '/profile';

/// 与小程序一致的五个玩家一级入口。
const Set<String> kPrimaryTabRoutes = <String>{
  kHomeRoute,
  kRoamRoute,
  kPublishRoute,
  kClubsRoute,
  kProfileRoute,
};

const String kMerchantHomeRoute = '/merchant';

int? publishEditTopicId(Uri uri) =>
    int.tryParse(uri.queryParameters['id'] ?? '');
