import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/points_record.dart';

/// 积分明细分页流。真实服务端分页(`/api/user/points/list`,data.rows)。
///
/// 设计:controller 只负责拉取「全部」明细的分页流(不带 change_type),
/// 收入/支出 tab 的过滤在页面层对累计列表做客户端筛选——因为后端两个积分端点
/// 都不做 change_type 服务端过滤,若按 tab 分别向服务端要页,hasMore/页码会与
/// 过滤结果脱节。余额取最新一条记录的 afterPoints(与 tab 无关)。
final pointsProvider =
    AsyncNotifierProvider.autoDispose<PointsNotifier, List<PointsRecord>>(
      PointsNotifier.new,
    );

class PointsNotifier extends AsyncNotifier<List<PointsRecord>> {
  static const int _pageSize = 20;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  bool get hasMore => _hasMore;
  bool get loadMoreFailed => _loadMoreFailed;

  /// 当前可用积分余额:最新一条记录的 afterPoints。无记录时返回 null。
  int? get balance {
    final list = state.value;
    if (list == null || list.isEmpty) return null;
    return list.first.afterPoints;
  }

  @override
  Future<List<PointsRecord>> build() async {
    _page = 1;
    _loadingMore = false;
    _loadMoreFailed = false;
    final first = await ref
        .read(pointsApiProvider)
        .list(pageNum: 1, pageSize: _pageSize);
    _hasMore = first.length >= _pageSize;
    return first;
  }

  /// 滚到底加载下一页。失败可重试。
  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _loadingMore = true;
    _loadMoreFailed = false;
    final requestedPage = _page + 1;
    try {
      final next = await ref
          .read(pointsApiProvider)
          .list(pageNum: requestedPage, pageSize: _pageSize);
      if (!ref.mounted || requestedPage != _page + 1) return;
      _page = requestedPage;
      if (next.length < _pageSize) _hasMore = false;
      final current = state.value ?? <PointsRecord>[];
      state = AsyncData<List<PointsRecord>>(<PointsRecord>[...current, ...next]);
    } catch (_) {
      if (ref.mounted) {
        _loadMoreFailed = true;
        state = AsyncData<List<PointsRecord>>(
          state.value ?? <PointsRecord>[],
        );
      }
    } finally {
      if (ref.mounted) _loadingMore = false;
    }
  }
}
