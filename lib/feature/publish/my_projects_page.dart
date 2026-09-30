import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/my_project.dart';
import '../../data/models/template.dart';
import '../auth/login_gate.dart';

final myProjectsProvider = FutureProvider.autoDispose<List<MyProject>>((ref) {
  return ref.watch(myProjectApiProvider).list();
});

final myProjectTemplatesProvider =
    FutureProvider.autoDispose<List<PlayTemplate>>((ref) {
      return ref.watch(templateApiProvider).myList();
    });

/// 后端是否以「未登录」拒绝了这次请求。只认 401 ——
/// 断网 / 500 被当成"要登录",会把只是没网的用户反复推去登录页,登完还是失败。
bool _isUnauthorized(Object err) =>
    err is DioException && err.response?.statusCode == 401;

/// 后端给的**中文**话优先,拿不到(或看着像诊断原文:带链接、超长)就退回场景兜底。
/// 真源 `app.getRequestErrorMessage` 是同一口径 —— 绝不把 Dio 的英文异常
/// 连同文档链接糊到屏幕上(B1 报告 pb-07/08/09)。
String? _backendMessage(Object err) {
  if (err is! DioException) return null;
  final Object? body = err.response?.data;
  final Object? raw = body is Map ? body['msg'] : null;
  final String msg = raw is String ? raw.trim() : '';
  if (msg.isEmpty || msg.length > 60 || msg.contains('http')) return null;
  return msg;
}

enum MyProjectTypeTab { topic, activity, template }

/// 卡面标签行的 `CyTag`:Wrap 会给孩子下发**有限 maxWidth**(见
/// `RenderWrap.performLayout`),而 `CyTag` 是 `Container(alignment: center)`
/// —— 铺满语义下被拉成通栏横条。小程序真源 `.cy-tag` 是 `inline-flex`、
/// 宽随字,`IntrinsicWidth` 把宽度收回字宽。
/// 不动共用件本体:全仓 10 个文件的 `Wrap(CyTag)` 同病,波及 7 个 golden
/// 测试域(含并行线 #a5-ios27-publish 的 publish_pro_page),另单开一条收口。
class _CyTagPill extends StatelessWidget {
  const _CyTagPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      IntrinsicWidth(child: CyTag(label: label));
}

const Map<MyProjectTypeTab, String> _typeLabels = <MyProjectTypeTab, String>{
  MyProjectTypeTab.topic: '主题',
  MyProjectTypeTab.activity: '活动',
  MyProjectTypeTab.template: '模板',
};
const Map<String, String> _ownerLabels = <String, String>{
  'all': '全部',
  'member': '个人',
  'club': '俱乐部',
  'merchant': '商家',
};
const List<(String, String)> _states = <(String, String)>[
  ('all', '全部状态'),
  ('draft', '草稿'),
  ('pending', '审核中'),
  ('notStarted', '未开始'),
  ('running', '进行中'),
  ('completed', '已完成'),
  ('offline', '已下架'),
  ('rejected', '未通过'),
];

class MyProjectsPage extends ConsumerStatefulWidget {
  const MyProjectsPage({
    super.key,
    this.liquidGlassSupported,
    this.initialTab = MyProjectTypeTab.topic,
  });

  final bool? liquidGlassSupported;
  final MyProjectTypeTab initialTab;

  @override
  ConsumerState<MyProjectsPage> createState() => _MyProjectsPageState();
}

class _MyProjectsPageState extends ConsumerState<MyProjectsPage> {
  late MyProjectTypeTab _tab;
  String _owner = 'all';
  String _state = 'all';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant MyProjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab == widget.initialTab) return;
    _tab = widget.initialTab;
    _owner = 'all';
    _state = 'all';
  }

  Future<void> _chooseState() async {
    final String? next = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('选择项目状态'),
        actions: <Widget>[
          for (final (String key, String label) in _states)
            CupertinoActionSheetAction(
              isDefaultAction: key == _state,
              onPressed: () => Navigator.of(context).pop(key),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (next != null && mounted) setState(() => _state = next);
  }

  void _selectState(String next) {
    if (!_states.any((row) => row.$1 == next)) return;
    setState(() => _state = next);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('我的项目'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: CyTabs(
                  // 分段走共用层:iOS 26+ 是原生分段(iOS 27 玻璃),
                  // 旧系统回退同一控件,另补齐 44pt 触达区。
                  tabs: <CyTab>[
                    for (final MapEntry<MyProjectTypeTab, String> entry
                        in _typeLabels.entries)
                      CyTab(key: entry.key.name, label: entry.value),
                  ],
                  active: _tab.name,
                  onChanged: (String key) {
                    final MyProjectTypeTab next = MyProjectTypeTab.values
                        .byName(key);
                    if (next == _tab) return;
                    setState(() {
                      _tab = next;
                      _owner = 'all';
                      _state = 'all';
                    });
                  },
                  variant: CyTabsVariant.segmented,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Expanded(
                child: _tab == MyProjectTypeTab.template
                    ? _templateBody()
                    : _projectBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 游客撞 401 时的登录引导。登录成功**就地**重取,不把人弹去别的页。
  Widget _loginGuide(
    String what,
    VoidCallback reload, {
    bool scrollable = false,
  }) => StatusView(
    message: '登录后查看$what',
    sub: '这一步需要登录,登录完会自动回到这一页。',
    icon: Icons.lock_outline,
    large: true,
    scrollable: scrollable,
    retryLabel: '去登录',
    onRetry: () async {
      if (!await requireLogin(context, ref)) return;
      reload();
    },
  );

  Widget _projectBody() {
    return ref
        .watch(myProjectsProvider)
        .when(
          loading: () => const CySkeleton(),
          error: (Object error, _) => _isUnauthorized(error)
              // ★ 游客点开 /my-projects 必然走到这里:POST /api/project/my 对无 token
              //   的请求返回 401(生产实测 {"code":401,"msg":"登录状态已失效…"})。
              //   通用错误态在这**两头都不对**:屏幕上会糊出 Dio 的英文异常原文,
              //   而「重试」按多少次都还是 401。改成可恢复的登录引导。
              ? _loginGuide('我的项目', () => ref.invalidate(myProjectsProvider))
              : StatusView(
                  message: '项目暂时没能加载',
                  sub: _backendMessage(error) ?? '项目加载失败，请稍后重试',
                  large: true,
                  onRetry: () => ref.invalidate(myProjectsProvider),
                ),
          data: (List<MyProject> all) {
            final List<String> owners = <String>[
              for (final String owner in const <String>[
                'member',
                'club',
                'merchant',
              ])
                if (all.any((MyProject row) => row.ownerType == owner)) owner,
            ];
            final String biz = _tab == MyProjectTypeTab.activity
                ? 'activity'
                : 'topic';
            final List<MyProject> typeRows = all
                .where((MyProject row) => row.bizType == biz)
                .toList();
            final List<MyProject> rows =
                typeRows
                    .where(
                      (MyProject row) =>
                          (_owner == 'all' || row.ownerType == _owner) &&
                          (_state == 'all' || row.state == _state),
                    )
                    .toList()
                  ..sort(
                    (MyProject a, MyProject b) =>
                        a.pendingRank.compareTo(b.pendingRank),
                  );
            final int rejected = typeRows
                .where((MyProject row) => row.state == 'rejected')
                .length;
            final int drafts = typeRows
                .where((MyProject row) => row.state == 'draft')
                .length;
            final int pending = typeRows
                .where((MyProject row) => row.state == 'pending')
                .length;

            return RefreshIndicator.adaptive(
              onRefresh: () async => ref.invalidate(myProjectsProvider),
              child: CustomScrollView(
                slivers: <Widget>[
                  if (owners.length > 1)
                    SliverToBoxAdapter(child: _ownerFilter(owners)),
                  SliverToBoxAdapter(
                    child: _toolbar(rejected, drafts, pending),
                  ),
                  if (rows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: StatusView(
                        message: _tab == MyProjectTypeTab.topic
                            ? '还没有主题'
                            : '还没有活动',
                        sub: _tab == MyProjectTypeTab.topic
                            ? '用发布按钮创建你的第一条城市路线'
                            : '商家与俱乐部主理人可发布单场活动',
                        large: true,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        CyTokens.pageX,
                        CyTokens.space1,
                        CyTokens.pageX,
                        CyTokens.space4,
                      ),
                      sliver: SliverList.separated(
                        itemCount: rows.length,
                        itemBuilder: (_, int i) =>
                            _ProjectCard(project: rows[i]),
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CyTokens.space3),
                      ),
                    ),
                ],
              ),
            );
          },
        );
  }

  Widget _ownerFilter(List<String> owners) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
    child: CyTabs(
      tabs: <String>[
        'all',
        ...owners,
      ].map((owner) => CyTab(key: owner, label: _ownerLabels[owner]!)).toList(),
      active: _owner,
      variant: CyTabsVariant.chip,
      onChanged: (owner) => setState(() => _owner = owner),
    ),
  );

  Widget _toolbar(int rejected, int drafts, int pending) {
    final int total = rejected + drafts + pending;
    final String stateLabel = _states.firstWhere((row) => row.$1 == _state).$2;
    final bool supportsLiquidGlass =
        widget.liquidGlassSupported ??
        NativeLiquidGlassUtils.supportsLiquidGlass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space1,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: total == 0
                ? const Text('没有待处理事项')
                : Wrap(
                    spacing: CyTokens.space1,
                    children: <Widget>[
                      Text('待处理 $total'),
                      if (rejected > 0)
                        _SummaryButton(
                          label: '未通过 $rejected',
                          onTap: () => setState(() => _state = 'rejected'),
                        ),
                      if (drafts > 0)
                        _SummaryButton(
                          label: '草稿 $drafts',
                          onTap: () => setState(() => _state = 'draft'),
                        ),
                      if (pending > 0)
                        _SummaryButton(
                          label: '审核中 $pending',
                          onTap: () => setState(() => _state = 'pending'),
                        ),
                    ],
                  ),
          ),
          if (supportsLiquidGlass)
            KeyedSubtree(
              key: const Key('project-state-filter'),
              child: LiquidGlassMenu(
                // The pinned plugin does not update the native UIButton title.
                // Recreate its platform view when the selected label changes.
                key: ValueKey<String>('project-state-filter-$_state'),
                menuTitle: '选择项目状态',
                label: stateLabel,
                icon: NativeLiquidGlassIcon.sfSymbol('chevron.down'),
                items: <LiquidGlassMenuItem>[
                  for (final (String key, String label) in _states)
                    LiquidGlassMenuItem(
                      id: key,
                      title: label,
                      icon: key == _state
                          ? NativeLiquidGlassIcon.sfSymbol('checkmark')
                          : null,
                    ),
                ],
                onItemSelected: _selectState,
              ),
            )
          else
            CupertinoButton(
              key: const Key('project-state-filter'),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              color: CupertinoColors.systemGrey6,
              onPressed: _chooseState,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(stateLabel),
                  const SizedBox(width: CyTokens.space1),
                  const Icon(CupertinoIcons.chevron_down, size: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _templateBody() => ref
      .watch(myProjectTemplatesProvider)
      .when(
        loading: () => const CySkeleton(),
        error: (Object error, _) => _isUnauthorized(error)
            // 同一个游客陷阱:POST /api/template/my-list 无 token 也是 401。
            ? _loginGuide(
                '节点玩法',
                () => ref.invalidate(myProjectTemplatesProvider),
                scrollable: true,
              )
            : StatusView(
                // 真源 subpackageA/pages/myproject/index.wxml 里这一格本就与
                // 主题/活动面板不同:标题是后端 msg(兜底「节点玩法加载失败」),
                // sub 为空 —— 这里保持同一句兜底,后端 msg 落到 sub。
                message: '节点玩法加载失败',
                sub: _backendMessage(error),
                large: true,
                scrollable: true,
                onRetry: () => ref.invalidate(myProjectTemplatesProvider),
              ),
        data: (List<PlayTemplate> rows) {
          if (rows.isEmpty) {
            return const StatusView(
              message: '还没有节点玩法',
              sub: '发布路线时可以沉淀自己的节点互动，之后在这里复用和管理',
              large: true,
              scrollable: true,
            );
          }
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.invalidate(myProjectTemplatesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              itemCount: rows.length,
              itemBuilder: (_, int i) => _TemplateCard(template: rows[i]),
              separatorBuilder: (_, _) =>
                  const SizedBox(height: CyTokens.space3),
            ),
          );
        },
      );
}

class _SummaryButton extends StatelessWidget {
  const _SummaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: CyTokens.space1),
    onPressed: onTap,
    child: Text(label, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _ProjectCard extends ConsumerStatefulWidget {
  const _ProjectCard({required this.project});
  final MyProject project;

  @override
  ConsumerState<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<_ProjectCard> {
  bool _busy = false;

  void _open() {
    final MyProject p = widget.project;
    if (p.bizType == 'topic' && (p.state == 'draft' || p.state == 'rejected')) {
      context.push('/publish/pro?id=${p.id}');
    } else if (p.bizType == 'activity') {
      context.push('/activity/${p.id}');
    } else {
      context.push('/project/home/${p.id}');
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(myProjectsProvider);
      if (mounted) {
        CyNativeNotice.show(context, message);
      }
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bool ok = await cyConfirm(
      context,
      title: '确认删除',
      content: '确定要删除“${widget.project.title}”吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok && mounted) {
      await _run(
        () => ref.read(myProjectApiProvider).remove(widget.project),
        '删除成功',
      );
    }
  }

  /// 主办方「取消并退款」(对齐小程序 myproject 的 cancelActivity/cancelTopic):
  /// 先问 `/api/{activity,topic}/cancel_preview` 拿已付款人数 N ——
  /// **拿不到就不弹确认、不发取消**,确认框必须写明「将给 N 位已付款玩家全额退款」。
  Future<void> _cancel() async {
    if (_busy) return;
    final MyProject p = widget.project;
    setState(() => _busy = true);
    int paidPlayers;
    try {
      paidPlayers = p.bizType == 'topic'
          ? await ref.read(topicApiProvider).cancelPreview(topicId: p.id)
          : await ref.read(activityApiProvider).cancelPreview(activityId: p.id);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    final bool isTopic = p.bizType == 'topic';
    final bool ok = await cyConfirm(
      context,
      title: isTopic ? '取消「${p.title}」并退款？' : '取消这场活动并退款？',
      content: isTopic
          ? '将给 $paidPlayers 位已付款玩家全额退款，不可撤销。主题同时停售，名下场次一并取消。\n'
                '· 已付款未核销的玩家全额退款，款项原路退回\n'
                '· 主题停售，名下所有场次取消，玩家不能再报名或进入\n'
                '· 已核销的票不退；此操作不可撤销'
          : '将给 $paidPlayers 位已付款玩家全额退款，不可撤销。活动同时下架。\n'
                '· 已报名未核销的玩家全额退款，款项原路退回\n'
                '· 活动下架，玩家不能再报名或进入\n'
                '· 此操作不可撤销，取消后无法恢复这场活动',
      confirmText: '取消并退款',
      danger: true,
    );
    if (!ok || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      // 原因文案与小程序同款(这一路是列表快捷操作,不另设输入框)。
      final String msg = isTopic
          ? await ref
                .read(topicApiProvider)
                .cancel(topicId: p.id, reason: '主办方取消主题')
          : await ref
                .read(activityApiProvider)
                .cancelActivity(activityId: p.id, reason: '主办方取消活动');
      ref.invalidate(myProjectsProvider);
      if (mounted) {
        CyNativeNotice.show(
          context,
          // 活动:小程序结果卡用固定文案(退款明细的长句留在活动详情页那条链路);
          // 主题:dc.done(res.msg) 原样显示后端那句话。
          isTopic ? msg : '活动已取消，已全额退款给所有已报名玩家。',
        );
      }
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MyProject p = widget.project;
    return Card(
      key: Key('project-card-${p.id}'),
      margin: EdgeInsets.zero,
      child: CupertinoButton(
        onPressed: _open,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space3),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  CyNetImage(
                    p.cover,
                    width: 84,
                    height: 84,
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (p.isPending) ...<Widget>[
                              const Icon(
                                CupertinoIcons.circle_fill,
                                size: 8,
                                color: CyTokens.statusDanger,
                              ),
                              const SizedBox(width: CyTokens.space1),
                            ],
                            Expanded(
                              child: Text(
                                p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Wrap(
                          spacing: CyTokens.space1,
                          runSpacing: CyTokens.space1,
                          children: <Widget>[
                            _CyTagPill(p.projectTypeText ?? '项目'),
                            if ((p.stateText ?? '').isNotEmpty)
                              _CyTagPill(p.stateText!),
                            if (p.ownerType == 'club') const _CyTagPill('俱乐部'),
                            if (p.ownerType == 'merchant')
                              const _CyTagPill('商家'),
                            if ((p.acceptStatusText ?? '').isNotEmpty)
                              _CyTagPill(p.acceptStatusText!),
                          ],
                        ),
                        if (p.statsText != null) ...<Widget>[
                          const SizedBox(height: CyTokens.space1),
                          Text(p.statsText!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (p.canToggle ||
                  p.canCancel ||
                  p.canDeleteByState ||
                  p.canViewCandidates) ...<Widget>[
                const Divider(height: CyTokens.space4),
                // 动作最多可同时出现 5 个(查看/候选池/上架/取消/删除),
                // Row 在窄屏会溢出 —— 用 Wrap 换行,排布与 Row 等宽时一致。
                Wrap(
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    _ProjectInlineAction(
                      onPressed: _busy ? null : _open,
                      label: p.actionLabel,
                    ),
                    if (p.canViewCandidates)
                      _ProjectInlineAction(
                        onPressed: _busy
                            ? null
                            : () => context.push('/coop/candidates/${p.id}'),
                        label: '候选池',
                      ),
                    if (p.canToggle)
                      _ProjectInlineAction(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => ref
                                    .read(myProjectApiProvider)
                                    .toggleStatus(p),
                                '操作成功',
                              ),
                        label: p.isOnline ? '下架' : '上架',
                      ),
                    if (p.canCancel)
                      _ProjectInlineAction(
                        key: Key('project-cancel-${p.id}'),
                        onPressed: _busy ? null : _cancel,
                        label: p.bizType == 'topic' ? '取消主题并退款' : '取消活动',
                        destructive: true,
                      ),
                    if (p.canDeleteByState)
                      _ProjectInlineAction(
                        onPressed: _busy ? null : _delete,
                        label: '删除',
                        destructive: true,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends ConsumerStatefulWidget {
  const _TemplateCard({required this.template});
  final PlayTemplate template;

  @override
  ConsumerState<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends ConsumerState<_TemplateCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(myProjectTemplatesProvider);
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bool ok = await cyConfirm(
      context,
      title: '确认删除',
      content: '确定要删除节点玩法“${widget.template.title}”吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok && mounted) {
      await _run(() => ref.read(templateApiProvider).remove(widget.template));
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayTemplate t = widget.template;
    final List<String> stats = <String>[
      if (t.useNum != null) '${t.useNum} 次引用',
      if (t.duration != null) '${t.duration} 分钟',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: CupertinoButton(
        onPressed: () => context.push('/template/${t.id}'),
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space3),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  CyNetImage(
                    t.imgUrl,
                    width: 84,
                    height: 84,
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Wrap(
                          spacing: CyTokens.space1,
                          children: <Widget>[
                            const _CyTagPill('节点玩法'),
                            _CyTagPill(t.managementStatusText),
                            if (t.publishStatus == 1) const _CyTagPill('已在玩法库'),
                          ],
                        ),
                        if (stats.isNotEmpty) ...<Widget>[
                          const SizedBox(height: CyTokens.space1),
                          Text(stats.join(' · ')),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: CyTokens.space4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _ProjectInlineAction(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(templateApiProvider)
                                .setLibraryStatus(t),
                          ),
                    label: t.publishStatus == 1 ? '从玩法库下架' : '发布到玩法库',
                  ),
                  _ProjectInlineAction(
                    onPressed: _busy ? null : _delete,
                    label: '删除',
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectInlineAction extends StatelessWidget {
  const _ProjectInlineAction({
    super.key,
    required this.onPressed,
    required this.label,
    this.destructive = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
    onPressed: onPressed,
    child: Text(
      label,
      style: destructive
          ? const TextStyle(color: CupertinoColors.systemRed)
          : null,
    ),
  );
}
