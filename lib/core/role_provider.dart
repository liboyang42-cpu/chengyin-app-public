import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import '../data/models/role_info.dart';

/// 身份与能力的**单一事实源**:`POST /api/role/info`。
///
/// ★★ 后端注释原话:「下发三端能力位全集,前端 roleGuard 一律读这里」。
///   App 此前是自己从 `role` / `userType` 推能力 —— 那是第二份判据,
///   必然和后端漂。实测已经漂了一处:
///   后端 `canCreateClub = !isMerchant && ownedClubCount < 2`,
///   而 App 用 `effectiveRole == 'club'` 一律拦死 ⇒
///   **已是主理人、但还没建满 2 个的人被挡在外面**,还告诉他"已成为主理人"。
///
/// ⚠️ 这个 provider 单独成文件而不是并进 core/providers.dart ——
///   那个文件另一处正在改,避免撞车。
final roleInfoProvider = FutureProvider.autoDispose<RoleInfo>((ref) {
  return ref.watch(registrationApiProvider).roleInfo();
});
