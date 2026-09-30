import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_tokens.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/publish_draft.dart';
import 'ai_draft_logic.dart';
import 'ai_draft_sheet.dart';
import 'publish_pro_utils.dart';

PublishDraft buildQuickPublishDraft({
  required int mode,
  required String title,
  required String description,
  required List<ConfirmedNode> nodes,
}) {
  if (!canEnterAiEditor(title: title, nodes: nodes)) {
    throw ArgumentError('主题名与每个点位都确认后才能进入编辑器');
  }
  final int productType = mode == kProductFreeExplore
      ? kProductFreeExplore
      : kProductCity;
  final PublishChapter chapter = PublishChapter()
    ..name = '路线'
    ..description = description.trim()
    ..localId = 'quick_chapter'
    ..nodes = <PublishNode>[
      for (int i = 0; i < nodes.length; i++)
        PublishNode()
          ..name = nodes[i].name.trim()
          ..description = nodes[i].description.trim()
          ..address = (nodes[i].address ?? nodes[i].name).trim()
          ..longitude = (nodes[i].longitude ?? '').trim()
          ..latitude = (nodes[i].latitude ?? '').trim()
          ..sortID = i + 1
          ..localId = 'quick_node_${i + 1}',
    ];
  return PublishDraft()
    ..name = title.trim()
    ..description = description.trim()
    ..productType = productType
    ..publishMode = 'ai_simple'
    ..chapters = <PublishChapter>[chapter]
    ..tickets = <PublishTicket>[defaultTicket(productType)];
}

/// 快速配置：一句话灵感 → AI 草稿 → 逐点地图确认 → 专业编辑器。
/// 本页不直接发布；服务端回执仍由专业编辑器统一负责。
class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key, this.mode = 1});

  /// 1 = 城市定向，2 = 自由探索。来自发布 Sheet，本页不重新猜默认值。
  final int mode;

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  List<ConfirmedNode> _nodes = <ConfirmedNode>[];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canEnter => canEnterAiEditor(title: _nameCtrl.text, nodes: _nodes);

  BoxDecoration _inputDecoration(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
  }

  Future<void> _pickPoi(int index) async {
    final result = await context
        .push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (result == null || !mounted) return;
    final ConfirmedNode previous = _nodes[index];
    setState(() {
      _nodes[index] = ConfirmedNode(
        name: previous.name,
        description: previous.description,
        address: result.name,
        longitude: result.longitude.toString(),
        latitude: result.latitude.toString(),
      );
    });
  }

  void _enterEditor() {
    if (!_canEnter) return;
    final PublishDraft draft = buildQuickPublishDraft(
      mode: widget.mode,
      title: _nameCtrl.text,
      description: _descCtrl.text,
      nodes: _nodes,
    );
    context.push('/publish/pro?mode=${draft.productType}', extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final bool freeExplore = widget.mode == 2;
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('快速配置', subtitle: '路线共创'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  0,
                  CyTokens.space4,
                  CyTokens.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      freeExplore ? '自由探索 · 章节承接路线' : '城市定向 · 集合式路线',
                      key: const Key('publish-quick-mode'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(
                      _nodes.isEmpty ? '嗨，想做一条什么样的路线？' : '这条路线，已经有了轮廓。',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      _nodes.isEmpty
                          ? '用一句话告诉我灵感。我先整理主题骨架，地点仍由你亲自确认。'
                          : '检查故事和地点；确认后再进入专业编辑器细化。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              // AI 起草 —— 小程序简易发布页有这一段,App 此前没有。
              // ★ 只填标题与简介,不直接发布:草稿里的点位还没有地点,
              //   由用户在编辑器里定(见 ai_draft_logic.dart 的三条纪律)。
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoButton(
                    key: const Key('publish-ai-draft'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                    ),
                    onPressed: () async {
                      final AiDraftPick? pick = await showAiDraftSheet(context);
                      if (pick == null || !mounted) return;
                      setState(() {
                        _nameCtrl.text = pick.title;
                        if (pick.description.isNotEmpty) {
                          _descCtrl.text = pick.description;
                        }
                        _nodes = <ConfirmedNode>[
                          for (final AiDraftNode node in pick.nodes)
                            ConfirmedNode(
                              name: node.name,
                              description: node.description,
                            ),
                        ];
                      });
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(CupertinoIcons.sparkles, size: 16),
                        SizedBox(width: CyTokens.space2),
                        Text('让 AI 起个草'),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    CyField(
                      label: '主题名',
                      child: CupertinoTextField(
                        key: const Key('publish-quick-name'),
                        controller: _nameCtrl,
                        maxLength: 30,
                        textInputAction: TextInputAction.next,
                        autocorrect: true,
                        enableSuggestions: true,
                        onChanged: (_) => setState(() {}),
                        placeholder: '给你的主题/路线起个名字',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _inputDecoration(context),
                      ),
                    ),
                    CyField(
                      label: '简介',
                      child: CupertinoTextField(
                        key: const Key('publish-quick-description'),
                        controller: _descCtrl,
                        maxLines: 4,
                        maxLength: 200,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: true,
                        enableSuggestions: true,
                        placeholder: '简单介绍一下(可留空)',
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _inputDecoration(context),
                      ),
                    ),
                    if (_nodes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        '确认地点',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: CyTokens.space1),
                      Text(
                        '每个点位都要从地图确认',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (int i = 0; i < _nodes.length; i++)
                        Card(
                          key: Key('publish-quick-node-$i'),
                          child: Padding(
                            padding: const EdgeInsets.all(CyTokens.space3),
                            child: Column(
                              children: <Widget>[
                                CupertinoTextFormFieldRow(
                                  key: Key('publish-quick-node-name-$i'),
                                  initialValue: _nodes[i].name,
                                  maxLength: 30,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: true,
                                  enableSuggestions: true,
                                  placeholder: '点位 ${i + 1}',
                                  padding: const EdgeInsets.all(
                                    CyTokens.space3,
                                  ),
                                  decoration: _inputDecoration(context),
                                  onChanged: (String value) {
                                    final ConfirmedNode old = _nodes[i];
                                    setState(() {
                                      _nodes[i] = ConfirmedNode(
                                        name: value,
                                        description: old.description,
                                        address: old.address,
                                        longitude: old.longitude,
                                        latitude: old.latitude,
                                      );
                                    });
                                  },
                                ),
                                CupertinoTextFormFieldRow(
                                  key: Key('publish-quick-node-story-$i'),
                                  initialValue: _nodes[i].description,
                                  maxLength: 300,
                                  maxLines: 2,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  autocorrect: true,
                                  enableSuggestions: true,
                                  placeholder: '点位故事',
                                  padding: const EdgeInsets.all(
                                    CyTokens.space3,
                                  ),
                                  decoration: _inputDecoration(context),
                                  onChanged: (String value) {
                                    final ConfirmedNode old = _nodes[i];
                                    setState(() {
                                      _nodes[i] = ConfirmedNode(
                                        name: old.name,
                                        description: value,
                                        address: old.address,
                                        longitude: old.longitude,
                                        latitude: old.latitude,
                                      );
                                    });
                                  },
                                ),
                                CupertinoButton(
                                  minimumSize: const Size.fromHeight(44),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _pickPoi(i),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          _nodes[i].confirmed
                                              ? (_nodes[i].address ?? '地点已确认')
                                              : '在地图中确认地点',
                                          style: TextStyle(
                                            color: CyPalette.of(
                                              context,
                                            ).textPrimary,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        CupertinoIcons.chevron_forward,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: CyTokens.space2),
                    CupertinoButton(
                      key: const Key('publish-quick-enter-editor'),
                      minimumSize: const Size.fromHeight(44),
                      color: CyPalette.of(context).actionPrimaryBg,
                      disabledColor: CyPalette.of(context).actionSecondaryBg,
                      onPressed: _canEnter ? _enterEditor : null,
                      child: Text(
                        '确认地点，进入编辑器 →',
                        style: TextStyle(
                          color: _canEnter
                              ? CyPalette.of(context).actionPrimaryFg
                              : CyPalette.of(context).textDisabled,
                        ),
                      ),
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
