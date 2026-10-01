import '../../l10n/strings.dart';
import '../../l10n/strings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_zh.dart';
import '../../l10n/error_presentation.dart';
import '../auth/auth_controller.dart';
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
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  return ref.watch(topicApiProvider).likeList(pageSize: _kMyLikesPageSize);
});

/// 平台分享边界。页面只提供当前主题；iOS 的系统 Activity View 由实现处理。
abstract interface class TopicShareActions {
  Future<void> share({required Topic topic, required Rect origin});
}

final topicShareActionsProvider = Provider<TopicShareActions>((ref) {
  return SystemTopicShareActions(ref.watch(appStringsProvider));
});

final class SystemTopicShareActions implements TopicShareActions {
  const SystemTopicShareActions([this.strings]);
  final AppLocalizations? strings;

  @override
  Future<void> share({required Topic topic, required Rect origin}) {
    final s = strings ?? AppLocalizationsZh();
    final String title = topic.name.trim().isEmpty ? s.likesUnnamed : topic.name;
    final subject = s.likesRecommendation(title);
    return SharePlus.instance.share(
      ShareParams(
        subject: subject,
        text: '$subject\nhttps://api.example.invalid/topic/${topic.id}',
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
  int _generation = 0;

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
    final generation = ++_generation;
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
      if (!mounted || generation != _generation) return;
      setState(() => _adoptFirstPage(first));
    } catch (_) {
      // FutureProvider 的 error 分支会显示原始服务端回执，别改成泛化成功态。
    }
  }

  Future<void> _loadMore() async {
    final generation = _generation;
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
      if (!mounted || generation != _generation || requestedPage != _page + 1) return;
      setState(() {
        _page = requestedPage;
        _hasMore = next.length >= _kMyLikesPageSize;
        _rows.addAll(next);
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _loadingMore = false);
    }
  }

  Future<void> _unlike(Topic topic) async {
    final generation = _generation;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).likesRemoveNamed(topic.name),
      confirmText: stringsOf(context).likesRemove,
      cancelText: stringsOf(context).likesKeep,
      danger: true,
    );
    if (!ok || !mounted || generation != _generation) return;
    setState(() => _busy.add(topic.id));
    try {
      // `/api/topic/like` 是切换语义；成功回执前绝不先删，也绝不自动重试。
      await ref.read(topicApiProvider).toggleLike(topic.id);
      if (!mounted || generation != _generation) return;
      setState(() => _rows.removeWhere((Topic row) => row.id == topic.id));
    } catch (e) {
      if (!mounted || generation != _generation) return;
      CyNativeNotice.show(
        context,
        presentError(e, stringsOf(context), fallback: stringsOf(context).likesRemoveError, originalApiMessage: legacyApiMessage(e)).noticeText,
        isError: true,
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy.remove(topic.id));
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
    ref.listen<int?>(authControllerProvider.select((state) => state.user?.id), (previous, next) {
      if (previous == next) return;
      setState(() {
        _generation++;
        _rows.clear();
        _busy.clear();
        _openRow = null;
        _seeded = false;
        _loadingMore = false;
        _loadMoreFailed = false;
        _hasMore = true;
        _page = 1;
      });
    });
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
              CyPageTitle(stringsOf(context).likesTitle),
              Expanded(
                child: guest
                    ? AccountLoginGate(
                        key: const Key('my-likes-login-gate'),
                        message: stringsOf(context).likesLogin,
                        sub: stringsOf(context).likesLoginHint,
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
                                message: stringsOf(context).likesLogin,
                                sub: stringsOf(context).likesLoginHint,
                                onSignedIn: _refresh,
                              )
                            : _seeded
                            ? _list()
                            : StatusView(
                                message: stringsOf(context).likesError,
                                sub: presentError(error, stringsOf(context), fallback: stringsOf(context).likesErrorHint, originalApiMessage: legacyApiMessage(error)).noticeText,
                                large: true,
                                onRetry: _refresh,
                              ),
                        data: (List<Topic> rows) {
                          _adoptFirstPage(rows);
                          if (_rows.isEmpty) {
                            return StatusView(
                              message: stringsOf(context).likesEmpty,
                              sub: stringsOf(context).likesEmptyHint,
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
                    label: stringsOf(context).likesShare,
                    semanticLabel: stringsOf(context).likesShareNamed(topic.name),
                    icon: CupertinoIcons.share,
                    onPressed: () => _share(topic, rowContext),
                  ),
                  CyContextualAction(
                    id: 'unlike-${topic.id}',
                    label: stringsOf(context).likesRemove,
                    semanticLabel: stringsOf(context).likesUnsaveNamed(topic.name),
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
        label: stringsOf(context).likesOpenNamed(topic.name),
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
          child: Text(stringsOf(context).likesMoreError),
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
