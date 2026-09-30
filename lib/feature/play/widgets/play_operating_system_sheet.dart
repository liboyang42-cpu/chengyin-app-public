import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';
import '../../../core/widgets/cy_confirm.dart';
import '../../../core/widgets/cy_native_button.dart';
import '../../../core/widgets/cy_native_sheet.dart';
import '../../../core/widgets/status_view.dart';
import '../../../data/api/play_os_api.dart';
import '../../../data/models/play_operating_system.dart';

Future<void> showPlayOperatingSystemSheet({
  required BuildContext context,
  required int topicId,
  PlayOsGateway? api,
}) => showCyNativeSheet<void>(
  // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
  context,
  // 真源近全屏(topGap .12),取大档;长内容由内部滚动兜。
  detents: CyNativeSheetDetents.large,
  builder: (BuildContext sheetContext) =>
      PlayOperatingSystemSheet(topicId: topicId, api: api),
);

class PlayOperatingSystemSheet extends ConsumerStatefulWidget {
  const PlayOperatingSystemSheet({
    super.key,
    required this.topicId,
    this.api,
    this.scrollController,
  });

  final int topicId;
  final PlayOsGateway? api;
  final ScrollController? scrollController;

  @override
  ConsumerState<PlayOperatingSystemSheet> createState() =>
      _PlayOperatingSystemSheetState();
}

class _PlayOperatingSystemSheetState
    extends ConsumerState<PlayOperatingSystemSheet> {
  PlayOperatingSystem? _data;
  String? _error;
  bool _loading = true;
  int? _revokingTagId;
  int _generation = 0;

  PlayOsGateway get _api => widget.api ?? ref.read(playOsApiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation += 1;
    super.dispose();
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PlayOperatingSystem data = await _api.load(widget.topicId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error is PlayOsApiException ? error.message : '新生活总结暂时没有加载出来';
      });
    }
  }

  Future<void> _revoke(PlayOsTag tag) async {
    if (_revokingTagId != null) return;
    final bool confirmed = await cyConfirm(
      context,
      title: '撤回「${tag.value}」？',
      content: '撤回后它不再用于后续个性化推荐。',
      confirmText: '撤回标签',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _revokingTagId = tag.id);
    try {
      await _api.revokeTag(tag.id);
      final PlayOperatingSystem readback = await _api.load(widget.topicId);
      final bool stillActive = readback.tags.any(
        (PlayOsTag item) => item.id == tag.id && !item.revoked,
      );
      if (stillActive) throw const PlayOsApiException('服务端尚未确认撤回，请稍后重试');
      if (!mounted) return;
      setState(() => _data = readback);
    } catch (error) {
      if (!mounted) return;
      final String message = error is PlayOsApiException
          ? error.message
          : '标签撤回结果未确认，请稍后重试';
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _revokingTagId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPopupSurface(
      // 原生 sheet 承载时不画自带底,透出系统材质(S3);回退路径维持真源底。
      isSurfacePainted: !isCyNativeSheet(context),
      child: SafeArea(
        top: false,
        child: Material(
          key: const Key('play-os-root'),
          color: isCyNativeSheet(context)
              ? CupertinoColors.transparent
              : palette.bgPage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space3,
                  CyTokens.space2,
                  CyTokens.space2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 小程序 .newos__eyebrow / .newos__title 两行,逐字对齐。
                          Text(
                            'PRIVATE BUILD / 仅自己可见',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: palette.textTertiary),
                          ),
                          Text(
                            '我的新生活操作系统',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    CyNativeIconButton(
                      label: '关闭新生活 OS',
                      icon: const CyNativeButtonIcon(
                        sfSymbol: 'xmark.circle.fill',
                        fallback: CupertinoIcons.xmark_circle_fill,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(palette)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(CyPalette palette) {
    if (_loading) {
      // 真源的加载/占位态(`.pref-load`)只有 muted 文字,没有图标。
      // 这里不补一枚 sparkles —— 四角星是装饰性自造图标,
      // 而「正在整理」这件事由文案自己说。
      return const StatusView(message: '正在整理这次探索…');
    }
    if (_error != null && _data == null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _error!,
        onRetry: _load,
      );
    }
    final PlayOperatingSystem data = _data!;
    if (data.isEmpty) {
      return const StatusView(
        icon: CupertinoIcons.square_stack_3d_up,
        message: '这次探索还没有生成总结',
      );
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      children: <Widget>[
        // 真源 `pages/play/index.wxml:1315` 的 `.newos__eyebrow` ——
        // 「PRIVATE BUILD / 仅自己可见」是这张总结的**隐私声明**,
        // 不是装饰眉标:它告诉用户这份画像只有自己能看、且标签可撤回。
        // App 侧此前整条没有,`tool/copy_parity.py` 把它列在
        // `pages/play/index` 的缺字里。
        // 字级/muted 色与下面的分节小标同源(`.newos__eyebrow` 与
        // `.newos__card-k` 都是 micro + ink-muted,只差字距)。
        Text(
          'PRIVATE BUILD / 仅自己可见',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: CyTokens.typeMicro,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        if (_error != null) _notice(_error!, palette),
        if (data.tags
            .where((PlayOsTag tag) => !tag.revoked)
            .isNotEmpty) ...<Widget>[
          // 真源 `.newos__tags` 没有小标题,一行一个标签:左边值、右边「撤回」
          // (`justify-content: space-between` + `.newos__revoke` 下划线文字)。
          // 此前渲成一颗只有值的胶囊 —— 动作看不见,用户不知道能撤。
          for (final PlayOsTag tag in data.tags.where(
            (PlayOsTag tag) => !tag.revoked,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: _OsTagRow(
                tag: tag,
                revoking: _revokingTagId == tag.id,
                busy: _revokingTagId != null,
                onRevoke: () => _revoke(tag),
              ),
            ),
        ],
        if (data.resultCards.isNotEmpty) ...<Widget>[
          _heading('节点结果', palette),
          ...data.resultCards.map(
            (PlayOsResultCard card) =>
                _card(palette, title: card.title, body: card.body),
          ),
        ],
        if (data.actions7Days.isNotEmpty)
          _actionSection('未来 7 天', data.actions7Days, palette),
        if (data.actions30Days.isNotEmpty)
          _actionSection('未来 30 天', data.actions30Days, palette),
        if (data.mapAnchors.isNotEmpty) ...<Widget>[
          // 真源这一组没有「城市锚点」这个自造标题,标题就是 `os-map-label`
          // 那句 `3km 生活圈 · N 个锚点`;每行只有地点名 ——
          // 「已加入这次探索地图」是 App 自加的说明,真源没有这句话。
          _heading('3km 生活圈 · ${data.mapAnchors.length} 个锚点', palette),
          ...data.mapAnchors.map(
            (PlayOsMapAnchor anchor) =>
                _card(palette, title: anchor.name, body: ''),
          ),
        ],
      ],
    );
  }

  /// 真源 `.newos__card-k` / `.newos__plan-k` = `--cy-type-micro` + ink-muted
  /// + `letter-spacing:3rpx` 的分节小标;分节之间是 `.newos__cards` /
  /// `.newos__plan` 的 `margin-top: space-4`。
  /// 此前渲成 `titleMedium` 的白色 w700 大标题,比正文还响 —— 四组
  /// 「节点结果 / 未来 7 天 / 未来 30 天 / 3km 生活圈」本身没有内容,
  /// 不该压过它们下面的正文(critic 二轮判「层级倒挂」)。
  Widget _heading(String text, CyPalette palette) => Padding(
    padding: const EdgeInsets.fromLTRB(0, CyTokens.space4, 0, CyTokens.space2),
    child: Text(
      text,
      style: TextStyle(
        color: palette.textSecondary,
        fontSize: CyTokens.typeMicro,
        letterSpacing: 1.5,
      ),
    ),
  );

  /// 行内失败提示(撤回没成 / 复核没成)。**必须穿错误的衣服**:
  /// 真源这一条走 `cyToast(... '撤回没有成功')`,App 侧改成不打断阅读的行内条,
  /// 但语义仍是 danger —— 此前用 `actionSecondaryBg`(次级动作底)渲染,
  /// 读起来像一块可用的胶囊,不像「这件事没成」;并补警示形状,
  /// 状态不只靠颜色(V5)。
  Widget _notice(String message, CyPalette palette) => Container(
    margin: const EdgeInsets.only(bottom: CyTokens.space3),
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      color: palette.statusDanger.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: 18,
          color: palette.statusDanger,
          semanticLabel: '操作未成功',
        ),
        const SizedBox(width: CyTokens.space2),
        Expanded(
          child: Text(message, style: TextStyle(color: palette.textPrimary)),
        ),
      ],
    ),
  );

  /// 真源 `.newos__card`:标题 `.newos__card-title`(body / 700)、
  /// 正文 `.newos__card-body`(label / muted / 1.55)。
  /// 此前每行配一枚自造图标(结果卡是四角星、锚点是定位针)——
  /// 真源这两个列表都没有图标,图标只是把「AI 生成的卡片」写在脸上,删。
  Widget _card(
    CyPalette palette, {
    required String title,
    required String body,
  }) => Container(
    margin: const EdgeInsets.only(bottom: CyTokens.space2),
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      border: Border.all(color: palette.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: CyTokens.typeBody,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (body.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            body,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeLabel,
              height: CyTokens.leadingNormal,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _actionSection(
    String title,
    List<String> actions,
    CyPalette palette,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _heading(title, palette),
      // 真源 `.newos__action` 是 `{{index + 1}}. {{item}}` 的编号行。
      // 此前每条配一枚 `checkmark.alt.circle` —— 勾是「已完成」的语义,
      // 而这一组是**未来**要做的行动,状态被图标说反了。
      for (int index = 0; index < actions.length; index += 1)
        Padding(
          padding: const EdgeInsets.only(bottom: CyTokens.space2),
          child: Text(
            '${index + 1}. ${actions[index]}',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: CyTokens.typeCaption,
              height: CyTokens.leadingNormal,
            ),
          ),
        ),
    ],
  );
}

/// 真源 `.newos__tag`:一行一个标签 —— 左边值、右边「撤回」文字动作
/// (`justify-content: space-between` + `.newos__revoke` 下划线)。
///
/// 之前渲成 `Wrap` 里的胶囊:值是唯一文字,「撤回」这个动作在画面上
/// 根本不存在 —— 用户读不出这行可以撤。
/// 真源那行左边还有 `tagCode`(`夜行系` 上面的类别码),App 的
/// `PlayOsTag` 模型没有解析这个字段,属数据层缺口,本轮只登记不补。
class _OsTagRow extends StatelessWidget {
  const _OsTagRow({
    required this.tag,
    required this.revoking,
    required this.busy,
    required this.onRevoke,
  });

  final PlayOsTag tag;
  final bool revoking;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      container: true,
      // 不可撤回的标签不许念「可撤回」(A2:读屏器不能骗人)。
      label: tag.canRevoke ? '${tag.value}，可撤回' : tag.value,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
          decoration: BoxDecoration(
            border: Border.all(color: palette.borderStrong),
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          ),
          alignment: Alignment.centerLeft,
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  tag.value,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: CyTokens.typeCaption,
                  ),
                ),
              ),
              if (tag.canRevoke)
                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  // 文字钮自己占 44×44,容器不再叠纵向内距(X12 命中区)。
                  padding: EdgeInsets.zero,
                  onPressed: busy ? null : onRevoke,
                  child: Text(
                    revoking ? '正在撤回…' : '撤回',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: CyTokens.typeCaption,
                      decoration: TextDecoration.underline,
                      decorationColor: palette.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
