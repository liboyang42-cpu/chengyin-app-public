import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/topic.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_swipe_actions.dart';
import 'account_login_gate.dart';

const int _kMyLikesPageSize = 10;

final myLikesProvider = FutureProvider.autoDispose<List<Topic>>((ref) {
  return ref.watch(topicApiProvider).likeList(pageSize: _kMyLikesPageSize);
});

/// 平台分享边界。页面只提供当前主题；iOS 的系统 Activity View 由实现处理。
abstract interface class TopicShareActions {
  Future<void> share({required Topic topic, required Rect origin});
}

final topicShareActionsProvider = Provider<TopicShareActions>((ref) {
  return const SystemTopicShareActions();
});

final class SystemTopicShareActions implements TopicShareActions {
  const SystemTopicShareActions();

  @override
  Future<void> share({required Topic topic, required Rect origin}) {
    final String title = topic.name.trim().isEmpty ? '城瘾主题' : topic.name;
    return SharePlus.instance.share(
      ShareParams(
        subject: '推荐路线：$title',
        text: '推荐路线：$title\nhttps://api.example.invalid/topic/${topic.id}',
        // iPad 的系统 Activity View 必须锚定触发控件；不能退回屏幕中央。
        sharePositionOrigin: origin,
      ),
    );
  }
}

/// 我的收藏。对齐小程序 `pages/mylike`：16:9 封面卡、卡内分享/取消、分页。
class MyLikesPage extends ConsumerStatefulWidget {
  const MyLikesPage({super.key});

  @override
  ConsumerState<MyLikesPage> createState() => _MyLikesPageState();
}

class _MyLikesPageState extends ConsumerState<MyLikesPage> {
  final Set<int> _busy = <int>{};
  final List<Topic> _rows = <Topic>[];

  /// 同一时刻只允许开一行（iOS 行为），由页面持有。
  Object? _openRow;

  bool _seeded = false;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  int _page = 1;

  void _adoptFirstPage(List<Topic> rows) {
    if (_seeded) return;
    _rows
      ..clear()
      ..addAll(rows);
    _page = 1;
    _hasMore = rows.length >= _kMyLikesPageSize;
    _loadMoreFailed = false;
    _seeded = true;
  }

  Future<void> _refresh() async {
    setState(() {
      _seeded = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _page = 1;
      _hasMore = true;
    });
    ref.invalidate(myLikesProvider);
    try {
      final List<Topic> first = await ref.read(myLikesProvider.future);
      if (!mounted) return;
      setState(() => _adoptFirstPage(first));
    } catch (_) {
      // FutureProvider 的 error 分支会显示原始服务端回执，别改成泛化成功态。
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final int requestedPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final List<Topic> next = await ref
          .read(topicApiProvider)
          .likeList(pageNum: requestedPage, pageSize: _kMyLikesPageSize);
      if (!mounted || requestedPage != _page + 1) return;
      setState(() {
        _page = requestedPage;
        _hasMore = next.length >= _kMyLikesPageSize;
        _rows.addAll(next);
      });
    } catch (_) {
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _unlike(Topic topic) async {
    final bool ok = await cyConfirm(
      context,
      title: '取消收藏「${topic.name}」?',
      confirmText: '取消收藏',
      cancelText: '再想想',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(topic.id));
    try {
      // `/api/topic/like` 是切换语义；成功回执前绝不先删，也绝不自动重试。
      await ref.read(topicApiProvider).toggleLike(topic.id);
      if (!mounted) return;
      setState(() => _rows.removeWhere((Topic row) => row.id == topic.id));
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        accountFailureCopy(e, networkFallback: '取消收藏没有成功,请稍后再试'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(topic.id));
    }
  }

  Future<void> _share(Topic topic, BuildContext buttonContext) async {
    final RenderBox? box = buttonContext.findRenderObject() as RenderBox?;
    final Rect origin = box == null
        ? Offset.zero & MediaQuery.sizeOf(context)
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await ref
          .read(topicShareActionsProvider)
          .share(topic: topic, origin: origin);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 游客短路:不发注定 401 的请求,页内给登录门(B1 报告 P1-1)。
    final bool guest = accountGuest(ref);
    final AsyncValue<List<Topic>>? async = guest
        ? null
        : ref.watch(myLikesProvider);
    return CupertinoPageScaffold(
      // 小程序是返回箭头下接左对齐页标题，不能再换成居中的 Material 标题栏。
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('我的收藏'),
              Expanded(
                child: guest
                    ? AccountLoginGate(
                        key: const Key('my-likes-login-gate'),
                        message: '登录后查看我的收藏',
                        sub: '收藏存在账号里,登录完就能看到。',
                        onSignedIn: _refresh,
                      )
                    : async!.when(
                        loading: () => _seeded
                            ? _list()
                            // 真源 pages/mylike/mylike.wxml:14 的加载态是
                            // `cy-skeleton type="card" count="3"`,不是转圈。
                            : const CySkeleton(
                                type: CySkeletonType.card,
                                count: 3,
                              ),
                        error: (Object error, StackTrace stackTrace) =>
                            accountLoginRequired(error)
                            ? AccountLoginGate(
                                message: '登录后查看我的收藏',
                                sub: '收藏存在账号里,登录完就能看到。',
                                onSignedIn: _refresh,
                              )
                            : _seeded
                            ? _list()
                            : StatusView(
                                message: '收藏没能加载出来',
                                sub: accountFailureCopy(
                                  error,
                                  networkFallback: '请检查网络后再进来，收藏不会丢失',
                                ),
                                large: true,
                                onRetry: _refresh,
                              ),
                        data: (List<Topic> rows) {
                          _adoptFirstPage(rows);
                          if (_rows.isEmpty) {
                            return const StatusView(
                              message: '暂无收藏的主题',
                              sub: '遇到想体验的城市主题，可以先收藏，之后从这里找回。',
                              large: true,
                            );
                          }
                          return _list();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    return RefreshIndicator.adaptive(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 180) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          itemCount: _rows.length + (_hasMore || _loadMoreFailed ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space3),
          itemBuilder: (BuildContext context, int index) {
            if (index == _rows.length) {
              return _LoadMoreFooter(
                loading: _loadingMore,
                failed: _loadMoreFailed,
                onRetry: _loadMore,
              );
            }
            final Topic topic = _rows[index];
            final bool busy = _busy.contains(topic.id);
            return Builder(
              // 分享要锚定在本行（iPad 的系统 Activity View 必须有源区）；
              // Builder 给的就是这一行的 RenderObject。
              builder: (BuildContext rowContext) => CySwipeActionsRow(
                key: Key('like-row-${topic.id}'),
                rowKey: topic.id,
                openKey: _openRow,
                onOpenChanged: (Object? opened) =>
                    setState(() => _openRow = opened),
                trailing: <CyContextualAction>[
                  CyContextualAction(
                    id: 'share-${topic.id}',
                    label: '分享',
                    semanticLabel: '分享${topic.name}',
                    icon: CupertinoIcons.share,
                    onPressed: () => _share(topic, rowContext),
                  ),
                  CyContextualAction(
                    id: 'unlike-${topic.id}',
                    label: '取消收藏',
                    semanticLabel: '取消收藏${topic.name}',
                    // 小程序真源是描边 heart；滑动动作位上是破坏性动作，
                    // 用 iOS 的 heart.slash（实心红心读作「收藏」，语义反了）。
                    icon: CupertinoIcons.heart_slash,
                    destructive: true,
                    isEnabled: !busy,
                    onPressed: () => _unlike(topic),
                  ),
                ],
                child: _LikeCard(
                  topic: topic,
                  onOpen: () => context.push('/topic/${topic.id}'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LikeCard extends StatelessWidget {
  const _LikeCard({required this.topic, required this.onOpen});

  final Topic topic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(CyTokens.radiusLg);
    return AspectRatio(
      key: Key('like-card-${topic.id}'),
      aspectRatio: 16 / 9,
      child: Semantics(
        button: true,
        label: '打开${topic.name}',
        onTap: onOpen,
        child: ExcludeSemantics(
          child: CupertinoButton(
            key: Key('like-open-${topic.id}'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: onOpen,
            child: SizedBox.expand(
              child: ClipRRect(
                borderRadius: radius,
                child: ColoredBox(
                  // 网络图首帧尚未回调时也要保留一张可见封面卡，不让操作漂在空白上。
                  color: CyPalette.of(context).bgSurfaceStrong,
                  child: CyNetImage(topic.picUrl, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: CupertinoButton(
          minimumSize: const Size(44, 44),
          onPressed: onRetry,
          child: const Text('加载失败，点我重试'),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: Center(
        child: loading
            ? const CupertinoActivityIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }
}
