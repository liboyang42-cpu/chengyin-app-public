import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_api.dart' show ClubApiException;
import '../../data/models/club_topic_ops.dart';
import '../../data/models/topic.dart' show TopicChapter;
import 'club_story_labels.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

/// 剧情与玩法。对齐小程序 `pages/club/topic-story`(Figma J1-A/J1-B/J1-C)。
///
/// 两个 tab:
/// - **路线**:按章节分组的站点时间轴(第几站 / 时间 / 名字 / 地址 / 步行估算);
/// - **玩法**:章节 chip → 本章剧情 → 本章玩法卡。
///
/// ★ 陈列源是 `/api/topic/info-to-user` 这条**玩家视角公开投影** ——
///   模板已过 TemplateSecrets.strip,答案/提示不在里面,所以敢当陈列源。
///   答案另走 `/api/club/topic-node-answer`(服务端 canGovernClub 校验),
///   **绝不**复用 `/api/play/nodes`:那条揭示要走 member_spoiler_reveal
///   且揭示即 0 分,语义和权限都不是「主理人看答案」。
class ClubTopicStoryPage extends ConsumerStatefulWidget {
  const ClubTopicStoryPage({super.key, required this.topicId, this.clubId});

  final int topicId;

  /// 治理身份线索。缺了也能按公开投影渲染路线与玩法,只是看不了答案。
  final int? clubId;

  @override
  ConsumerState<ClubTopicStoryPage> createState() => _ClubTopicStoryPageState();
}

enum _StoryTab { route, play }

class _ClubTopicStoryPageState extends ConsumerState<ClubTopicStoryPage> {
  ClubOpsLoadState _stage = ClubOpsLoadState.loading;
  List<TopicChapter> _sourceChapters = const <TopicChapter>[];
  List<TopicStoryChapter> get _chapters => localizedClubStoryChapters(context, _sourceChapters);
  String _error = '';
  _StoryTab _tab = _StoryTab.route;
  int _activeChapter = 0;
  bool _storyExpanded = false;
  bool _loginRequired = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stage = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
    });
    try {
      final ClubTopicOverview overview = await ref
          .read(clubTopicOpsApiProvider)
          .overview(widget.topicId);
      if (!mounted) return;
      setState(() {
        _sourceChapters = overview.chapters;
        _activeChapter = 0;
        _stage = ClubOpsLoadState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _stage = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, stringsOf(context).clubStoryLoadFailed);
      });
    }
  }

  TopicStoryChapter? get _active =>
      _activeChapter >= 0 && _activeChapter < _chapters.length
      ? _chapters[_activeChapter]
      : null;

  Future<void> _openAnswer(TopicStoryPlay play) async {
    final int? clubId = widget.clubId;
    if (clubId == null || clubId <= 0) {
      CyNativeNotice.show(context, stringsOf(context).clubStoryAnswerAccess, isError: true);
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _AnswerSheet(
        clubId: clubId,
        topicId: widget.topicId,
        nodeId: play.nodeId,
        title: stringsOf(context).clubStoryNamedAnswer(play.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubStoryTitle),
              if (_stage == ClubOpsLoadState.ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space2,
                    CyTokens.pageX,
                    CyTokens.space2,
                  ),
                  // 分段走共用层:iOS 26+ 是原生分段,旧系统回退 Cupertino
                  // 分段控件(与自绘那版同长相,另补齐 44pt 触达区)。
                  child: CyTabs(
                    tabs: <CyTab>[
                      CyTab(key: 'route', label: stringsOf(context).clubStoryRoute),
                      CyTab(key: 'play', label: stringsOf(context).clubStoryPlay),
                    ],
                    active: _tab.name,
                    onChanged: (String key) {
                      final _StoryTab next = _StoryTab.values.byName(key);
                      if (next == _tab) return;
                      setState(() {
                        _tab = next;
                        _storyExpanded = false;
                      });
                    },
                    variant: CyTabsVariant.segmented,
                  ),
                ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 401 排在四态之前:登录过期不是「看不到」,重试/返回都出不去 ——
    // 就地给登录门(#258 同型,topic-detail 已修,本页当时漏了)。
    if (_loginRequired) {
      return ClubLoginGate(message: stringsOf(context).clubStoryLogin, onSignedIn: _load);
    }
    switch (_stage) {
      case ClubOpsLoadState.loading:
        return CySkeleton(
          type: CySkeletonType.card,
          count: 3,
          label: stringsOf(context).clubStoryLoading,
        );
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).clubStoryDenied,
          sub: _error.isEmpty ? stringsOf(context).clubStoryDeniedBody : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).clubStoryNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: stringsOf(context).clubStoryUnavailable,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _load,
        );
      case ClubOpsLoadState.ready:
        if (_chapters.isEmpty) {
          return StatusView(
            message: stringsOf(context).clubStoryNoChapters,
            sub: stringsOf(context).clubStoryNoChaptersBody,
            icon: CupertinoIcons.map,
            large: true,
          );
        }
        return _tab == _StoryTab.route ? _routeBody() : _playBody();
    }
  }

  Widget _routeBody() {
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        for (final TopicStoryChapter chapter in _chapters) ...<Widget>[
          ClubOpsSection(
            key: Key('topic-story-chapter-${chapter.id}'),
            title: chapter.title,
            caption: chapter.meta,
            children: <Widget>[
              if (chapter.stops.isEmpty)
                ClubOpsCard(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space4,
                        vertical: CyTokens.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(stringsOf(context).clubStoryNoStops),
                          const SizedBox(height: CyTokens.space1),
                          _EmptyHint(stringsOf(context).clubStoryNoStopsBody),
                        ],
                      ),
                    ),
                  ],
                )
              else
                ...chapter.stops.map(_stopRow),
            ],
          ),
        ],
      ],
    );
  }

  Widget _stopRow(TopicStoryStop stop) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      key: Key('topic-story-stop-${stop.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (stop.walkText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.space4,
              CyTokens.space2,
              CyTokens.space4,
              0,
            ),
            child: Text(
              stop.walkText,
              style: TextStyle(
                fontSize: CyTokens.typeMicro,
                color: palette.textTertiary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space2),
          child: ClubOpsCard(
            children: <Widget>[
              ClubOpsRow(
                title: stop.name.isEmpty ? stringsOf(context).clubStoryUnnamedStop : stop.name,
                meta: <String>[
                  stop.time,
                  stop.address,
                ].where((String s) => s.isNotEmpty).join(' · '),
                metaLines: 2,
                leading: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CyNetImage(
                        stop.cover,
                        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                        fallback: ColoredBox(color: palette.bgSurfaceSubtle),
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: palette.overlay,
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusSm,
                            ),
                          ),
                          child: Text(
                            '${stop.seq}',
                            style: TextStyle(
                              fontSize: CyTokens.typeMicro,
                              fontWeight: FontWeight.w700,
                              color: palette.textInverse,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playBody() {
    final CyPalette palette = CyPalette.of(context);
    final TopicStoryChapter? chapter = _active;
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space6),
      children: <Widget>[
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            itemCount: _chapters.length,
            separatorBuilder: (_, _) => const SizedBox(width: CyTokens.space2),
            itemBuilder: (BuildContext context, int index) {
              final bool on = index == _activeChapter;
              return GestureDetector(
                key: Key('topic-story-chip-$index'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (index == _activeChapter) return;
                  setState(() {
                    _activeChapter = index;
                    _storyExpanded = false;
                  });
                },
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space1,
                    ),
                    decoration: BoxDecoration(
                      color: on
                          ? palette.actionPrimaryBg
                          : palette.bgSurfaceSubtle,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    ),
                    child: Text(
                      _chapters[index].title,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: on
                            ? palette.actionPrimaryFg
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (chapter == null)
          const SizedBox.shrink()
        else ...<Widget>[
          ClubOpsSection(
            title: stringsOf(context).clubStoryChapterStory,
            caption: chapter.title,
            children: <Widget>[
              ClubOpsCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.space4,
                      CyTokens.space3,
                      CyTokens.space4,
                      CyTokens.space3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          chapter.story.isEmpty ? stringsOf(context).clubStoryNoStory : chapter.story,
                          key: const Key('topic-story-story-text'),
                          maxLines: _storyExpanded ? null : 3,
                          overflow: _storyExpanded
                              ? TextOverflow.clip
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            height: 1.55,
                            color: chapter.story.isEmpty
                                ? palette.textTertiary
                                : palette.textPrimary,
                          ),
                        ),
                        if (chapter.story.isNotEmpty) ...<Widget>[
                          const SizedBox(height: CyTokens.space2),
                          GestureDetector(
                            key: const Key('topic-story-story-toggle'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                              () => _storyExpanded = !_storyExpanded,
                            ),
                            child: Text(
                              _storyExpanded ? stringsOf(context).clubStoryCollapse : stringsOf(context).clubStoryExpand,
                              style: TextStyle(
                                fontSize: CyTokens.typeLabel,
                                color: palette.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          ClubOpsSection(
            title: stringsOf(context).clubStoryChapterPlay,
            caption: stringsOf(context).clubStoryPlayCount(chapter.plays.length),
            children: <Widget>[
              if (chapter.plays.isEmpty)
                ClubOpsCard(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space4,
                        vertical: CyTokens.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(stringsOf(context).clubStoryNoPlay),
                          const SizedBox(height: CyTokens.space1),
                          _EmptyHint(stringsOf(context).clubStoryNoPlayBody),
                        ],
                      ),
                    ),
                  ],
                )
              else
                ...chapter.plays.map(_playCard),
            ],
          ),
        ],
      ],
    );
  }

  Widget _playCard(TopicStoryPlay play) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      key: Key('topic-story-play-${play.nodeId}'),
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        child: Container(
          color: palette.bgElevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CyNetImage(
                      play.cover,
                      fallback: ColoredBox(color: palette.bgSurfaceSubtle),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x00000000), Color(0xAA000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: CyTokens.space3,
                      top: CyTokens.space3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.overlay,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusPill,
                          ),
                        ),
                        child: Text(
                          play.badge,
                          style: TextStyle(
                            fontSize: CyTokens.typeMicro,
                            fontWeight: FontWeight.w600,
                            color: palette.textInverse,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: CyTokens.space3,
                      right: CyTokens.space3,
                      bottom: CyTokens.space3,
                      child: Text(
                        play.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: CyTokens.typeCardTitle,
                          fontWeight: FontWeight.w700,
                          color: palette.textInverse,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space3,
                  CyTokens.space2,
                  CyTokens.space3,
                  CyTokens.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      play.meta,
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Row(
                      children: <Widget>[
                        CyNativeButton(
                          label: stringsOf(context).clubStoryViewTemplate,
                          role: CyNativeButtonRole.secondary,
                          onPressed: () =>
                              context.push('/template/${play.templateId}'),
                        ),
                        if (play.hasAnswer) ...<Widget>[
                          const SizedBox(width: CyTokens.space2),
                          CyNativeButton(
                            key: Key('topic-story-answer-${play.nodeId}'),
                            label: stringsOf(context).clubStoryViewAnswer,
                            onPressed: () => _openAnswer(play),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 答案弹层(J1-C T1)的内容层。
///
/// 自成一块 StatefulWidget,而不是把状态挂在页面上:弹层是 Overlay 里的
/// **另一棵树**,页面的 setState 不会重建它 —— 挂在页面上就会「点开永远转圈」,
/// 而且重试还得靠页面记住「刚才看的是哪一站」。
/// 空态副标:小程序 `cy-empty` 的 sub —— 主标说「没有什么」,副标说「怎么才会有」。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: CyTokens.typeCaption,
        color: CyPalette.of(context).textTertiary,
      ),
    );
  }
}

class _AnswerSheet extends ConsumerStatefulWidget {
  const _AnswerSheet({
    required this.clubId,
    required this.topicId,
    required this.nodeId,
    required this.title,
  });

  final int clubId;
  final int topicId;
  final int nodeId;
  final String title;

  @override
  ConsumerState<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends ConsumerState<_AnswerSheet> {
  bool _loading = true;
  String _error = '';
  TopicNodeAnswer? _answer;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final TopicNodeAnswer answer = await ref
          .read(clubTopicOpsApiProvider)
          .nodeAnswer(
            clubId: widget.clubId,
            topicId: widget.topicId,
            nodeId: widget.nodeId,
          );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ClubApiException && error.message.trim().isNotEmpty
            ? error.message
            : stringsOf(context).clubStoryAnswerUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: widget.title,
      sheetKey: const Key('topic-story-answer-sheet'),
      child: _answerBody(),
    );
  }

  Widget _answerBody() {
    final CyPalette palette = CyPalette.of(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space5),
        child: Column(
          children: <Widget>[
            const CupertinoActivityIndicator(),
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).clubStoryAnswerLoading,
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: CyPalette.of(context).textTertiary,
              ),
            ),
          ],
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.pageX,
          vertical: CyTokens.space5,
        ),
        child: StatusView(
          message: stringsOf(context).clubStoryAnswerFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          retryLabel: stringsOf(context).clubStoryRetry,
          onRetry: _fetch,
        ),
      );
    }
    final TopicNodeAnswer? answer = _answer;
    if (answer == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (answer.question.isNotEmpty) ...<Widget>[
            _answerLabel(stringsOf(context).clubStoryQuestion),
            _answerBlock(
              palette,
              Text(
                answer.question,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: 1.5,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
          _answerLabel(stringsOf(context).clubStoryAnswer),
          _answerBlock(
            palette,
            Text(
              answer.answerReveal.isEmpty ? stringsOf(context).clubStoryNoAnswer : answer.answerReveal,
              key: const Key('topic-story-answer-reveal'),
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (answer.hints.isNotEmpty) ...<Widget>[
            _answerLabel(stringsOf(context).clubStoryHint),
            _answerBlock(
              palette,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < answer.hints.length; i += 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${i + 1} · ${answer.hints[i]}',
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          height: 1.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (answer.feedbackText.isNotEmpty) ...<Widget>[
            _answerLabel(stringsOf(context).clubStoryIncorrectFeedback),
            _answerBlock(
              palette,
              Text(
                answer.feedbackText,
                style: TextStyle(
                  fontSize: CyTokens.typeBody,
                  height: 1.5,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: Text(
              stringsOf(context).clubStoryAnswerScope,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                height: 1.45,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CyTokens.space3,
        bottom: CyTokens.space1,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: CyTokens.typeCaption,
          fontWeight: FontWeight.w600,
          color: CyPalette.of(context).textTertiary,
        ),
      ),
    );
  }

  Widget _answerBlock(CyPalette palette, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: child,
    );
  }
}

/// 半屏 sheet 的公共外壳(与 topic-detail 同形)。
/// ★ 材质交给系统 [CupertinoPopupSurface],不再自绘与页面同色的实色卡片。
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child, this.sheetKey});

  final String title;
  final Widget child;
  final Key? sheetKey;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      child: CupertinoPopupSurface(
        child: Container(
          key: sheetKey,
          // 原生 sheet 停位 = 屏高减一个顶部间隙(SDK 默认 topGap 0.08 → 92%);
          // 0.78 是照小程序压出来的,App 没有胶囊要避让。
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.space3,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('sheet-close'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 24,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
