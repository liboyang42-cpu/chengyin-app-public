import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/api/creator_api.dart';
import '../../data/models/creator_center.dart';

/// ⚠️ 这个 provider **故意不放进 `core/providers.dart`** ——
/// 那个文件当前有未提交的在途改动(NPC 功能),往里加会污染那份工作。
/// 放在 feature 自己的 controller 里,语义上本来也更合适。
final creatorApiProvider = Provider<CreatorApi>((ref) {
  return CreatorApi(ref.watch(dioClientProvider));
});

/// 创作者中心。四态见 [CreatorApplyStatus] ——
/// `not_applied` / `pending` / `approved` / `rejected` 必须各说各的。
final creatorCenterProvider = FutureProvider.autoDispose<CreatorCenter>((ref) {
  return ref.watch(creatorApiProvider).center();
});
