import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 个性化推荐的一条。
///
/// ★★ 与首页那个「推荐主题」**不是一回事**:
///   · 首页横向卡片走 `topic/list?recommend=true` —— **运营配置的固定推荐位**
///   · 这条走 `/api/recommendation/list` —— **按人算的个性化推荐**
///   两者同时存在不冲突,别把其中一个当成另一个的替代。
///
/// ⚠️ 后端返回形状**三种都可能**(小程序原样兼容:裸数组 / `rows` / `list`),
///   而且 id 与名字**各有三个候选键**。少认一个就会渲出一排「推荐路线」。
class RecommendedTopic {
  const RecommendedTopic({required this.id, required this.name});

  final int id;
  final String name;

  /// 认不出 id 的条目**丢掉**,不留一个点不进去的卡片。
  static RecommendedTopic? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? pick(List<String> keys) {
      for (final String k in keys) {
        final Object? v = raw[k];
        if (v is num) return v.toInt();
        if (v is String) {
          final int? n = int.tryParse(v);
          if (n != null) return n;
        }
      }
      return null;
    }

    final int? id = pick(<String>['id', 'topicId', 'candidateId']);
    if (id == null || id <= 0) return null;
    String name = '';
    for (final String k in <String>['name', 'title', 'topicName']) {
      final String v = (raw[k] ?? '').toString().trim();
      if (v.isNotEmpty) {
        name = v;
        break;
      }
    }
    // ★ 名字兜底只在**有 id** 时才用得上 —— 那时它至少点得进去。
    return RecommendedTopic(id: id, name: name.isEmpty ? '推荐路线' : name);
  }

  /// 从整个响应里取列表。三种形状都收。
  static List<RecommendedTopic> parseAll(Object? data) {
    final List<dynamic> rows = switch (data) {
      final List<dynamic> l => l,
      final Map<String, dynamic> m =>
        (m['rows'] as List<dynamic>?) ?? (m['list'] as List<dynamic>?) ??
            const <dynamic>[],
      _ => const <dynamic>[],
    };
    return rows
        .map(RecommendedTopic.tryParse)
        .whereType<RecommendedTopic>()
        .toList();
  }
}

/// 个性化推荐。★ 拉不到就当**没有推荐**(空列表),不抛错 ——
/// 它是首页的锦上添花,拉不到不该让整页变错误页。
final recommendedTopicsProvider =
    FutureProvider.autoDispose<List<RecommendedTopic>>((Ref ref) async {
  try {
    final rows = await ref
        .watch(myProjectApiProvider)
        .recommendations(candidateType: 'topic', limit: 5);
    return RecommendedTopic.parseAll(rows);
  } catch (_) {
    return const <RecommendedTopic>[];
  }
});
