import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/api/play_run_session_api.dart';
import '../../data/models/play_run_session.dart';
import '../../data/models/topic.dart';

/// 任务流:公开主题(路线)分页列表 + 无限滚动。
final feedProvider =
    AsyncNotifierProvider.autoDispose<FeedNotifier, List<Topic>>(
      FeedNotifier.new,
    );

class FeedNotifier extends AsyncNotifier<List<Topic>> {
  static const int _pageSize = 10;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  bool get hasMore => _hasMore;
  bool get loadMoreFailed => _loadMoreFailed;

  @override
  Future<List<Topic>> build() async {
    // 每次重建(含下拉刷新)复位分页状态,避免与在途 loadMore 串台
    _page = 1;
    _loadingMore = false;
    _loadMoreFailed = false;
    final first = await ref
        .read(topicApiProvider)
        .list(pageNum: 1, pageSize: _pageSize);
    _hasMore = first.length >= _pageSize;
    return first;
  }

  /// 滚到底加载下一页。失败可重试(reset 后再调)。
  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _loadingMore = true;
    _loadMoreFailed = false;
    final requestedPage = _page + 1;
    try {
      final next = await ref
          .read(topicApiProvider)
          .list(pageNum: requestedPage, pageSize: _pageSize);
      // provider 已销毁(autoDispose)或期间发生过刷新(页码已被重置)→ 丢弃本次结果
      if (!ref.mounted || requestedPage != _page + 1) return;
      _page = requestedPage;
      if (next.length < _pageSize) _hasMore = false;
      // 拼接基于 await 后的最新列表,而非进入时的快照
      final current = state.value ?? <Topic>[];
      state = AsyncData<List<Topic>>(<Topic>[...current, ...next]);
    } catch (_) {
      if (ref.mounted) {
        _loadMoreFailed = true;
        // 重新 emit 同一份列表,触发 UI 重建以显示 footer 失败态
        state = AsyncData<List<Topic>>(state.value ?? <Topic>[]);
      }
    } finally {
      if (ref.mounted) _loadingMore = false;
    }
  }
}

/// 首页「继续游戏」卡:GET `/api/play/run-session/list`(小程序 `pages/index/index.js:1142` 同一口径)。
/// 进行中的游戏会话优先占首页那张卡,换手机登录同账号也能接着玩。
/// 服务端已按报名/通行证/活动结束日过滤,这里不再过一遍业务闸 ——
/// 能不能继续仍由游玩页 `/api/play/nodes` 的权威态把门。
final playRunSessionsProvider =
    FutureProvider.autoDispose<List<PlayRunSession>>(
      (ref) => ref.watch(playRunSessionApiProvider).list(),
    );
