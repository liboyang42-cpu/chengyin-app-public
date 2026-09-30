import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/category.dart';
import '../../data/models/club.dart';
import '../../data/models/publish_draft.dart';
import '../../data/models/xp_budget.dart';
import '../publisher/publisher_identity.dart';
import '../publisher/publisher_identity_fields.dart';
import 'publish_draft_logic.dart';
import 'publish_image_cropper.dart';
import 'publish_pro_utils.dart';
import '../../core/widgets/cy_net_image.dart';

/// 发布编辑器的弹层集合(主题详情 / 节点 / 章节 / 模式 / 类别 / 发布前检查 / 发布成功)。

// ---------------------------------------------------------------- 章节弹窗

class ChapterSheetResult {
  const ChapterSheetResult({
    required this.name,
    required this.description,
    this.audioUrl = '',
    this.atmospherePreset = 'DEFAULT',
    this.recruitEnabled = 0,
    this.termsMode = 'PERK',
    this.categoryId,
    this.categoryName = '',
    this.maxMerchant,
    this.perkMinValue,
    this.deleted = false,
  });
  final String name;
  final String description;

  /// 本章背景旁白(进本章自动播放)。空串 = 没有。
  final String audioUrl;

  /// 章节配色,取值见 [kChapterAtmospheres]。
  final String atmospherePreset;

  /// 商家承接。0/1;只有俱乐部主理人配得了(见 [showChapterSheet] 的 merchantPoolEditable)。
  final int recruitEnabled;

  /// 承接条款:PERK 给权益 / TRAFFIC 只引流。后端发布期只收这两档。
  final String termsMode;

  /// 适合商家品类。★ 开了承接就是必填 —— 后端 assertMerchantCategory 会拒整次保存。
  final int? categoryId;

  /// 品类名。它和 categoryId 是同一列的两半,一起走。
  final String categoryName;

  /// 名额上限,0 = 不限。后端列是有符号 TINYINT,只收 0..127。
  final int? maxMerchant;

  /// 权益门槛(¥)。空 = 不设门槛;★ 只引流档必须为空。
  final String? perkMinValue;
  final bool deleted;
}

/// [merchantPoolEditable] = 本账号是不是俱乐部主理人。商家承接整段只对他露出 ——
/// 和小程序 `chapter-recruit` 的 wx:if、后端 `resolveMerchantPoolFlag` 是同一条闸。
/// 玩家/商家看得到却开不了,只会在发布时被后端拒。
Future<ChapterSheetResult?> showChapterSheet(
  BuildContext context, {
  required String name,
  required String description,
  required bool isEdit,
  required bool isCity,
  String audioUrl = '',
  String atmospherePreset = 'DEFAULT',
  bool merchantPoolEditable = false,
  int recruitEnabled = 0,
  String termsMode = 'PERK',
  int? categoryId,
  String categoryName = '',
  int? maxMerchant,
  String? perkMinValue,
}) {
  return showCupertinoSheet<ChapterSheetResult>(
    context: context,
    showDragHandle: true,
    topGap: 0.38,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        _ChapterSheet(
          name: name,
          description: description,
          isEdit: isEdit,
          isCity: isCity,
          audioUrl: audioUrl,
          atmospherePreset: atmospherePreset,
          merchantPoolEditable: merchantPoolEditable,
          recruitEnabled: recruitEnabled,
          termsMode: termsMode,
          categoryId: categoryId,
          categoryName: categoryName,
          maxMerchant: maxMerchant,
          perkMinValue: perkMinValue,
          scrollController: scrollController,
        ),
  );
}

class _ChapterSheet extends ConsumerStatefulWidget {
  const _ChapterSheet({
    required this.name,
    required this.description,
    required this.isEdit,
    required this.isCity,
    required this.audioUrl,
    required this.atmospherePreset,
    required this.merchantPoolEditable,
    required this.recruitEnabled,
    required this.termsMode,
    required this.categoryId,
    required this.categoryName,
    required this.maxMerchant,
    required this.perkMinValue,
    required this.scrollController,
  });

  final String name;
  final String description;
  final bool isEdit;
  final bool isCity;
  final String audioUrl;
  final String atmospherePreset;
  final bool merchantPoolEditable;
  final int recruitEnabled;
  final String termsMode;
  final int? categoryId;
  final String categoryName;
  final int? maxMerchant;
  final String? perkMinValue;
  final ScrollController scrollController;

  @override
  ConsumerState<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends ConsumerState<_ChapterSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.description,
  );
  late String _audioUrl = widget.audioUrl;
  late String _atmosphere = normalizeAtmosphere(widget.atmospherePreset);
  String _audioName = '';
  bool _uploading = false;

  // ── 商家承接 ───────────────────────────────────────────────
  late int _recruit = widget.recruitEnabled;
  late String _terms = widget.termsMode == 'TRAFFIC' ? 'TRAFFIC' : 'PERK';
  late int? _categoryId = widget.categoryId;
  late String _categoryName = widget.categoryName;
  late final TextEditingController _maxMerchant = TextEditingController(
    text: widget.maxMerchant == null ? '' : '${widget.maxMerchant}',
  );
  late final TextEditingController _perkMin = TextEditingController(
    text: widget.perkMinValue ?? '',
  );

  /// 商家品类:和商家档案 `mms_merchant.category_id` 同口径的一级受控分类。
  Future<void> _pickCategory() async {
    List<Category> list;
    try {
      list = await ref.read(categoryApiProvider).list(type: '1');
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          publishMessage(e, '品类加载失败'),
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    final Category? picked = await showCupertinoModalPopup<Category>(
      context: context,
      builder: (BuildContext ctx) => CupertinoActionSheet(
        title: const Text('商家品类'),
        message: const Text('限定可承接本章的商家类型'),
        actions: <Widget>[
          for (final Category c in list)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(c),
              child: Text(c.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.id;
      _categoryName = picked.name;
    });
  }

  /// 完成前自查。★ 这几条和后端 ChapterRecruitmentRules 一一对应 ——
  ///   在这里说清楚,总好过让人在发布时撞一个自己修不了的报错。
  String? get _recruitIssue {
    if (_recruit != 1) return null;
    if (_categoryId == null || _categoryId! <= 0) {
      return '开放商家承接的章节必须选择适合商家品类';
    }
    final String quota = _maxMerchant.text.trim();
    if (quota.isNotEmpty) {
      final int? n = int.tryParse(quota);
      if (n == null || n < 0 || n > 127) {
        return '名额上限只能是 0 到 127 的整数（0 = 不限）';
      }
    }
    final String perk = _perkMin.text.trim();
    if (perk.isNotEmpty && _terms == 'PERK') {
      final double? v = double.tryParse(perk);
      if (v == null || v <= 0) return '权益门槛须为大于 0 的金额；不设置请留空';
    }
    return null;
  }

  ChapterSheetResult _collect() {
    final String quota = _maxMerchant.text.trim();
    final String perk = _perkMin.text.trim();
    return ChapterSheetResult(
      name: _name.text,
      description: _desc.text,
      audioUrl: _audioUrl,
      atmospherePreset: _atmosphere,
      recruitEnabled: _recruit,
      termsMode: _terms,
      // 关掉承接时保留原值:界面收起来了,不代表这一章的配置该被清空。
      categoryId: _recruit == 1 ? _categoryId : widget.categoryId,
      categoryName: _recruit == 1 ? _categoryName : widget.categoryName,
      maxMerchant: quota.isEmpty ? null : int.tryParse(quota),
      // 只引流档必须留空 —— 后端 assertPerkMinValueForTerms 会拒。
      perkMinValue: (_recruit == 1 && _terms == 'PERK' && perk.isNotEmpty)
          ? perk
          : null,
    );
  }

  /// 章节音频:玩家进入本章时自动播放的背景旁白,所以它不落在故事流的某一段上。
  Future<void> _pickAudio() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['mp3', 'm4a', 'aac'],
    );
    final PlatformFile? file = picked?.files.singleOrNull;
    final String? path = file?.path;
    if (file == null || path == null) return;
    setState(() => _uploading = true);
    try {
      final String url = await ref
          .read(publishApiProvider)
          .uploadFile(
            path,
            fileType: file.name.contains('.')
                ? file.name.split('.').last.toLowerCase()
                : null,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() {
        _audioUrl = url;
        _audioName = file.name;
      });
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _maxMerchant.dispose();
    _perkMin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space4 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            CySectionTitle(widget.isEdit ? '编辑章节' : '添加章节'),
            SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              key: const Key('chapter-name'),
              controller: _name,
              maxLength: 30,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              clearButtonMode: OverlayVisibilityMode.editing,
              placeholder: '章节名称',
              style: TextStyle(color: palette.textPrimary),
              placeholderStyle: TextStyle(color: palette.textPlaceholder),
              padding: const EdgeInsets.all(CyTokens.space3),
              decoration: _inputDecoration(palette, _name.text.isNotEmpty),
            ),
            SizedBox(height: CyTokens.space3),
            if (widget.isCity)
              // 城市定向正文只在故事流写;章节弹窗不设第二写处。
              Text(
                '创建后进入全屏故事流，用块间插入点添加文字与节点',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: CyPalette.of(context).textSecondary,
                ),
              )
            else ...<Widget>[
              const _FieldHead(title: '章节剧情', hint: '选填'),
              SizedBox(height: CyTokens.space2),
              CupertinoTextField(
                controller: _desc,
                maxLines: 3,
                maxLength: 500,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                clearButtonMode: OverlayVisibilityMode.editing,
                placeholder: '这一章讲什么？（选填）',
                style: TextStyle(color: palette.textPrimary),
                placeholderStyle: TextStyle(color: palette.textPlaceholder),
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: _inputDecoration(palette, _desc.text.isNotEmpty),
              ),
            ],
            SizedBox(height: CyTokens.space3),
            _AudioRow(
              url: _audioUrl,
              fileName: _audioName,
              uploading: _uploading,
              onPick: _pickAudio,
              onClear: () => setState(() {
                _audioUrl = '';
                _audioName = '';
              }),
            ),
            if (widget.isCity) ...<Widget>[
              SizedBox(height: CyTokens.space3),
              _AtmosphereRow(
                value: _atmosphere,
                onPick: (String v) => setState(() => _atmosphere = v),
              ),
            ],
            if (widget.merchantPoolEditable) ...<Widget>[
              SizedBox(height: CyTokens.space4),
              const _FieldHead(title: '商家承接', hint: '承接的商家给玩家权益,或者只做引流。'),
              SizedBox(height: CyTokens.space2),
              _RecruitRow(
                title: '本章开放商家承接',
                value: _recruit == 1 ? '开后商家可在合作池申请承接本章' : '本章不对商家开放',
                trailing: CupertinoSwitch(
                  key: const Key('chapter-recruit-toggle'),
                  value: _recruit == 1,
                  onChanged: (bool v) => setState(() => _recruit = v ? 1 : 0),
                ),
              ),
              if (_recruit == 1) ...<Widget>[
                _RecruitRow(
                  key: const Key('chapter-recruit-category'),
                  title: '商家品类',
                  value: _categoryName.isEmpty ? '限定可承接的商家类型' : _categoryName,
                  required: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '选择品类',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: palette.textPrimary,
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 18,
                        color: palette.textTertiary,
                      ),
                    ],
                  ),
                  onTap: _pickCategory,
                ),
                SizedBox(height: CyTokens.space2),
                Text(
                  '承接条款',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: palette.textPrimary,
                  ),
                ),
                SizedBox(height: CyTokens.space1),
                _TermsSegment(
                  value: _terms,
                  onPick: (String v) => setState(() {
                    _terms = v;
                    // 只引流档不许带门槛,当场清干净 —— 留着会被后端拒。
                    if (v == 'TRAFFIC') _perkMin.clear();
                  }),
                ),
                if (_terms == 'PERK')
                  _RecruitRow(
                    title: '权益门槛 (¥)',
                    value: '商家给出的权益不低于这个价值',
                    trailing: _NumberBox(
                      key: const Key('chapter-recruit-perk'),
                      controller: _perkMin,
                      placeholder: '不限',
                      decimal: true,
                    ),
                  ),
                _RecruitRow(
                  title: '名额上限 (家)',
                  value: '留空或填 0 都是不限',
                  trailing: _NumberBox(
                    key: const Key('chapter-recruit-quota'),
                    controller: _maxMerchant,
                    placeholder: '不限',
                  ),
                ),
              ],
            ],
            SizedBox(height: CyTokens.space4),
            CupertinoButton(
              key: const Key('chapter-complete'),
              minimumSize: const Size.fromHeight(CyTokens.btnH),
              color: palette.actionPrimaryBg,
              foregroundColor: palette.actionPrimaryFg,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
              onPressed: () {
                final String? issue = _recruitIssue;
                if (issue != null) {
                  CyNativeNotice.show(context, issue, isError: true);
                  return;
                }
                Navigator.of(context).pop(_collect());
              },
              child: const Text('完成'),
            ),
            if (widget.isEdit) ...<Widget>[
              SizedBox(height: CyTokens.space2),
              CupertinoButton(
                key: const Key('chapter-delete'),
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                color: palette.actionSecondaryBg,
                foregroundColor: palette.statusDanger,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                // 垃圾桶 = 会丢掉只存在于这里的东西 ⇒ 必须先二次确认。
                // 图标是后果的预告,预告和实际后果对不上就是在骗人。
                onPressed: () async {
                  final bool ok = await cyConfirm(
                    context,
                    title: '删除这一章?',
                    content: '章节里的剧情与节点会一起删掉，删了找不回来。',
                    confirmText: '删除',
                    danger: true,
                  );
                  if (!ok || !context.mounted) return;
                  Navigator.of(context).pop(
                    const ChapterSheetResult(
                      name: '',
                      description: '',
                      deleted: true,
                    ),
                  );
                },
                child: const _DeleteLabel('删除章节'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 章节音频行:空态给一个「添加音频」入口,有值时显示文件名 + 移除。
/// 不做预听 —— 编辑弹窗里再挂一个播放器不值当,玩家端已经有播放链路。
class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.url,
    required this.fileName,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final String url;
  final String fileName;
  final bool uploading;
  final Future<void> Function() onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _FieldHead(title: '章节音频', hint: '玩家进入本章时自动播放'),
        SizedBox(height: CyTokens.space2),
        if (url.isEmpty)
          Semantics(
            container: true,
            button: true,
            label: '添加章节音频',
            excludeSemantics: true,
            onTap: uploading ? null : onPick,
            child: CupertinoButton(
              key: const Key('chapter-audio-add'),
              minimumSize: const Size.fromHeight(CyTokens.btnH),
              color: palette.actionSecondaryBg,
              foregroundColor: palette.textPrimary,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              onPressed: uploading ? null : onPick,
              child: Text(uploading ? '上传中…' : '＋ 添加音频'),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: palette.actionSecondaryBg,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                const Icon(CupertinoIcons.speaker_2, size: 18),
                SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Text(
                    fileName.isEmpty ? '已上传的音频' : fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ),
                CupertinoButton(
                  key: const Key('chapter-audio-clear'),
                  padding: EdgeInsets.zero,
                  // 命中区 ≥44pt(L9):原来 Size.zero,可点范围只有那两个字。
                  minimumSize: const Size(44, 44),
                  onPressed: onClear,
                  // 小程序同钮 aria-label=「移除章节音频」(可见字只有一个「移除」)。
                  child: Semantics(
                    label: '移除章节音频',
                    child: Text(
                      '移除',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: palette.statusDanger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 章节配色:决定玩家端整章的配色,只有城市定向有。
class _AtmosphereRow extends StatelessWidget {
  const _AtmosphereRow({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _FieldHead(title: '章节配色', hint: '决定玩家端整章的配色'),
        SizedBox(height: CyTokens.space2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final ({String value, String label, String note, int color})
                  item
                  in kChapterAtmospheres)
                Padding(
                  padding: const EdgeInsets.only(right: CyTokens.space2),
                  child: GestureDetector(
                    key: Key('chapter-atmosphere-${item.value}'),
                    onTap: () => onPick(item.value),
                    child: Container(
                      width: 96,
                      padding: const EdgeInsets.all(CyTokens.space3),
                      decoration: BoxDecoration(
                        color: Color(item.color),
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        border: Border.all(
                          color: value == item.value
                              ? CyPalette.of(context).actionPrimaryBg
                              : const Color(0x1F000000),
                          width: value == item.value ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.label,
                            style: TextStyle(
                              color: _swatchFg(item.value),
                              fontSize: CyTokens.typeBody,
                            ),
                          ),
                          Text(
                            item.note,
                            style: TextStyle(
                              color: _swatchFg(
                                item.value,
                              ).withValues(alpha: 0.78),
                              fontSize: CyTokens.typeMicro,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 白档是唯一浅色卡,文字要翻黑,否则白底白字。
  static Color _swatchFg(String value) =>
      value == 'WHITE' ? const Color(0xFF111318) : const Color(0xFFFFFFFF);
}

/// 承接段里的一行:标题 + 说明 + 右侧控件/箭头。
class _RecruitRow extends StatelessWidget {
  const _RecruitRow({
    super.key,
    required this.title,
    required this.value,
    this.trailing,
    this.onTap,
    this.required = false,
  });

  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    text: title,
                    children: <InlineSpan>[
                      if (required)
                        TextSpan(
                          text: ' *',
                          style: TextStyle(color: palette.statusDanger),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: CyTokens.typeBody,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (trailing == null && onTap != null)
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: CyPalette.of(context).textTertiary,
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.fromHeight(44),
      onPressed: onTap,
      child: row,
    );
  }
}

/// 承接条款两档。计酬档是平台在后台标定的,发布期不给选(后端也会拒)。
class _TermsSegment extends StatelessWidget {
  const _TermsSegment({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    // 分段走共用层:iOS 26+ 是原生分段(iOS 27 玻璃),旧系统回退同一控件,
    // 另补齐 44pt 触达区(与 club 域同一口径)。
    return CyTabs(
      key: const Key('chapter-recruit-terms'),
      tabs: const <CyTab>[
        CyTab(key: 'PERK', label: '给权益'),
        CyTab(key: 'TRAFFIC', label: '只引流'),
      ],
      active: value == 'TRAFFIC' ? 'TRAFFIC' : 'PERK',
      onChanged: (String key) => onPick(key == 'TRAFFIC' ? 'TRAFFIC' : 'PERK'),
      variant: CyTabsVariant.segmented,
    );
  }
}

class _NumberBox extends StatelessWidget {
  const _NumberBox({
    super.key,
    required this.controller,
    required this.placeholder,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return SizedBox(
      width: 96,
      child: CupertinoTextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textAlign: TextAlign.right,
        placeholder: placeholder,
        style: TextStyle(color: palette.textPrimary),
        placeholderStyle: TextStyle(color: palette.textPlaceholder),
        padding: const EdgeInsets.symmetric(
          horizontal: CyTokens.space2,
          vertical: CyTokens.space2,
        ),
        decoration: _inputDecoration(palette, controller.text.isNotEmpty),
      ),
    );
  }
}

class _FieldHead extends StatelessWidget {
  const _FieldHead({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            color: palette.textPrimary,
          ),
        ),
        Text(
          hint,
          style: TextStyle(
            fontSize: CyTokens.typeMicro,
            color: CyPalette.of(context).textSecondary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 模式选择

/// 模式选择:先摊开讲、再让人选(切模式会连带改整条票务链路的必填项)。
Future<int?> showModePickerSheet(BuildContext context, {required int current}) {
  return showCupertinoSheet<int>(
    context: context,
    showDragHandle: true,
    topGap: 0.3,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        _ModePickerSheet(current: current, scrollController: scrollController),
  );
}

class _ModePickerSheet extends StatefulWidget {
  const _ModePickerSheet({
    required this.current,
    required this.scrollController,
  });

  final int current;
  final ScrollController scrollController;

  @override
  State<_ModePickerSheet> createState() => _ModePickerSheetState();
}

class _ModePickerSheetState extends State<_ModePickerSheet> {
  late int _selected = widget.current == kProductFreeExplore
      ? kProductFreeExplore
      : kProductCity;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space4,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Semantics(
                  label: '关闭模式选择',
                  button: true,
                  child: CupertinoButton(
                    key: const Key('mode-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: palette.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const ExcludeSemantics(
                      child: Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  key: const Key('mode-confirm'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space3,
                  ),
                  color: palette.actionPrimaryBg,
                  foregroundColor: palette.actionPrimaryFg,
                  borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                  onPressed: () => Navigator.of(context).pop(_selected),
                  // 小程序同钮可见文案「使用此模式」、aria-label「确认创作模式」——
                  // 一个「确定」读不出确认的是哪件事。
                  child: Semantics(
                    label: '确认创作模式',
                    button: true,
                    excludeSemantics: true,
                    child: const Text('使用此模式'),
                  ),
                ),
              ],
            ),
            Text(
              '主题模式',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '这个主题怎么玩？',
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: (int? value) {
                if (value != null) setState(() => _selected = value);
              },
              child: Column(
                children: <Widget>[
                  _modeOption(
                    mode: kProductCity,
                    title: '城市定向',
                    sub: '需设置具体的集合时间与地点，适合强组织的团体活动。',
                  ),
                  const SizedBox(height: CyTokens.space3),
                  _modeOption(
                    mode: kProductFreeExplore,
                    title: '自由探索',
                    sub: '只需设置有效期，用户在规定时间内自由前往体验。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            Text(
              '切换模式会保留当前草稿，另外复制一份新草稿再切 —— 已经写好的章节不会被改掉。',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeOption({
    required int mode,
    required String title,
    required String sub,
  }) {
    final CyPalette palette = CyPalette.of(context);
    final bool selected = _selected == mode;
    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: CupertinoButton(
        key: Key('mode-option-$mode'),
        minimumSize: const Size.fromHeight(64),
        padding: const EdgeInsets.all(CyTokens.space3),
        color: palette.bgSurfaceSubtle,
        foregroundColor: palette.textPrimary,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        onPressed: () => setState(() => _selected = mode),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: CupertinoRadio<int>(
                value: mode,
                activeColor: palette.brand,
                useCheckmarkStyle: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 类别多选

Future<void> showCategorySheet(
  BuildContext context, {
  required WidgetRef ref,
  required PublishDraft draft,
  required VoidCallback onChanged,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.24,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        _CategorySheet(
          ref: ref,
          draft: draft,
          onChanged: onChanged,
          scrollController: scrollController,
        ),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({
    required this.ref,
    required this.draft,
    required this.onChanged,
    required this.scrollController,
  });

  final WidgetRef ref;
  final PublishDraft draft;
  final VoidCallback onChanged;
  final ScrollController scrollController;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  bool _loading = true;
  String? _error;
  List<Category> _categories = <Category>[];
  List<int> _selected = <int>[];
  List<String> _selectedNames = <String>[];

  @override
  void initState() {
    super.initState();
    _selected = List<int>.of(widget.draft.categoryIds);
    _selectedNames = List<String>.of(widget.draft.categoryNames);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.ref.read(categoryApiProvider).list(type: '1');
      if (!mounted) return;
      setState(() {
        _categories = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = publishMessage(e, '类别加载失败');
      });
    }
  }

  void _toggle(Category c) {
    setState(() {
      final idx = _selected.indexOf(c.id);
      if (idx >= 0) {
        _selected.removeAt(idx);
        _selectedNames.remove(c.name);
      } else {
        _selected.add(c.id);
        _selectedNames.add(c.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    void closeSheet() => Navigator.of(context).pop();
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    // 小程序多选弹框标题就叫「选择主题类别」,和 App 里其它
                    // 「主题/路线」措辞统一成同一个词。
                    '选择主题类别',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w700,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: '关闭类别选择',
                    button: true,
                    onTap: closeSheet,
                    child: CupertinoButton(
                      key: const Key('category-close'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      foregroundColor: palette.textSecondary,
                      onPressed: closeSheet,
                      child: const ExcludeSemantics(
                        child: Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: _buildContent()),
            Padding(
              padding: EdgeInsets.all(CyTokens.pageX),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '已选择 ${_selected.length} 个',
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('category-confirm'),
                    minimumSize: const Size(88, CyTokens.btnH),
                    color: palette.actionPrimaryBg,
                    foregroundColor: palette.actionPrimaryFg,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    onPressed: () {
                      widget.draft.categoryIds = List<int>.of(_selected);
                      widget.draft.categoryNames = List<String>.of(
                        _selectedNames,
                      );
                      widget.onChanged();
                      Navigator.of(context).pop();
                    },
                    child: const Text('保存选择'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return StatusView(message: _error!, onRetry: _load);
    }
    if (_categories.isEmpty) {
      return const StatusView(message: '暂时没有可用类别', sub: '类别库是空的，换个时间再来看看');
    }
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: true,
      children: <Widget>[
        for (final c in _categories)
          Semantics(
            selected: _selected.contains(c.id),
            button: true,
            label: c.name,
            child: CupertinoButton(
              key: Key('category-${c.id}'),
              minimumSize: const Size.fromHeight(52),
              padding: EdgeInsets.zero,
              foregroundColor: CyPalette.of(context).textPrimary,
              onPressed: () => _toggle(c),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space2,
                ),
                child: Row(
                  children: <Widget>[
                    ExcludeSemantics(
                      child: CupertinoCheckbox(
                        value: _selected.contains(c.id),
                        activeColor: CyPalette.of(context).brand,
                        onChanged: (_) => _toggle(c),
                      ),
                    ),
                    SizedBox(width: CyTokens.space3),
                    Text(
                      c.name,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 主题详情

Future<void> showTopicDetailSheet(
  BuildContext context, {
  required WidgetRef ref,
  required PublishDraft draft,
  required List<Club> myClubs,
  required VoidCallback onChanged,
  required VoidCallback onCategoryTap,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: false,
    topGap: 0.08,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        _TopicDetailSheet(
          ref: ref,
          draft: draft,
          myClubs: myClubs,
          onChanged: onChanged,
          onCategoryTap: onCategoryTap,
          scrollController: scrollController,
        ),
  );
}

class _TopicDetailSheet extends ConsumerStatefulWidget {
  const _TopicDetailSheet({
    required this.ref,
    required this.draft,
    required this.myClubs,
    required this.onChanged,
    required this.onCategoryTap,
    required this.scrollController,
  });

  final WidgetRef ref;
  final PublishDraft draft;
  final List<Club> myClubs;
  final VoidCallback onChanged;
  final VoidCallback onCategoryTap;
  final ScrollController scrollController;

  @override
  ConsumerState<_TopicDetailSheet> createState() => _TopicDetailSheetState();
}

class _TopicDetailSheetState extends ConsumerState<_TopicDetailSheet> {
  late final TextEditingController _subtitle = TextEditingController(
    text: widget.draft.subtitle,
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.draft.description,
  );
  late final TextEditingController _medal = TextEditingController(
    text: widget.draft.finishMedalName,
  );
  bool _uploading = false;

  /// 完成奖励开关是**纯 UI 态**:奖励本身就是「有没有选券」。
  /// 多存一个 rewardOn 字段会立刻产生「开着但没选」这种存不住也说不清的中间态,
  /// 所以关掉即把 couponId 清 0,开着只是把选择器露出来。
  late bool _rewardOn = widget.draft.completeRewardCouponId != 0;
  String _rewardName = '';

  @override
  void dispose() {
    _subtitle.dispose();
    _desc.dispose();
    _medal.dispose();
    super.dispose();
  }

  /// 选完成奖励。体验卡和优惠券同在券这条链路上(发放/核销/库存全复用),
  /// 只是 couponType 不同 —— 3 = 体验卡,其余都是优惠券,所以一张列表按档标注即可。
  Future<void> _pickReward() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await ref.read(couponApiProvider).myPublishedList();
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    final int? picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (BuildContext ctx) => CupertinoActionSheet(
        title: const Text('选择奖励'),
        message: const Text('主题通关后发放'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: const Text('不发券'),
          ),
          for (final Map<String, dynamic> row in rows)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(ctx).pop((row['id'] as num).toInt()),
              child: Text(
                '${row['name'] ?? '未命名'} · '
                '${(row['couponType'] as num?)?.toInt() == 3 ? '体验卡' : '优惠券'}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      widget.draft.completeRewardCouponId = picked;
      _rewardName = picked == 0
          ? ''
          : (rows.firstWhere(
                      (Map<String, dynamic> r) =>
                          (r['id'] as num).toInt() == picked,
                      orElse: () => <String, dynamic>{},
                    )['name'] ??
                    '')
                .toString();
      widget.onChanged();
    });
  }

  PublishDraft get draft => widget.draft;

  Future<void> _uploadBanner() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final List<String>? urls = await pickCropAndUploadPublishImages(
      context,
      widget.ref,
      maxCount: 1,
      aspect: PublishCropAspect.portrait3x4,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (urls != null && urls.isNotEmpty) {
      draft.imgUrl = urls.first;
      widget.onChanged();
    }
  }

  Future<void> _uploadImgArr() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final int remaining =
        9 - draft.imgArr.split(',').where((s) => s.trim().isNotEmpty).length;
    final List<String>? urls = await pickCropAndUploadPublishImages(
      context,
      widget.ref,
      maxCount: remaining,
      aspect: PublishCropAspect.landscape16x9,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (urls != null && urls.isNotEmpty) {
      final list =
          draft.imgArr.split(',').where((s) => s.trim().isNotEmpty).toList()
            ..addAll(urls);
      draft.imgArr = list.take(9).join(',');
      widget.onChanged();
    }
  }

  Future<void> _uploadMedal() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final List<String>? urls = await pickCropAndUploadPublishImages(
      context,
      widget.ref,
      maxCount: 1,
      aspect: PublishCropAspect.square,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (urls != null && urls.isNotEmpty) {
      draft.finishMedalImg = urls.first;
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final imgArrList = draft.imgArr
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  CupertinoButton(
                    key: const Key('topic-detail-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: palette.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                  Text(
                    '编辑主题',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w700,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('topic-detail-done'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                    ),
                    color: palette.actionPrimaryBg,
                    foregroundColor: palette.actionPrimaryFg,
                    borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                controller: widget.scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                children: <Widget>[
                  Text(
                    draft.name.isEmpty ? '未命名主题' : draft.name,
                    style: TextStyle(
                      fontSize: CyTokens.typeSectionTitle,
                      fontWeight: FontWeight.w600,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      Text(
                        '主题描述',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1_5),
                      CupertinoTextField(
                        controller: _subtitle,
                        onChanged: (v) {
                          draft.subtitle = v;
                          widget.onChanged();
                        },
                        maxLength: 30,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        placeholder: '不超过 30 字',
                        style: TextStyle(color: palette.textPrimary),
                        placeholderStyle: TextStyle(
                          color: palette.textPlaceholder,
                        ),
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _inputDecoration(
                          palette,
                          _subtitle.text.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      _rowCard(
                        icon: CupertinoIcons.line_horizontal_3_decrease_circle,
                        title: '主题类别',
                        value: draft.categoryNames.isEmpty
                            ? '决定主题在广场的分区'
                            : draft.categoryNames.join('，'),
                        required: true,
                        onTap: () async {
                          widget.onCategoryTap();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      _rowCard(
                        title: '竖版封面',
                        value: '3:4 竖图 · 1 张 · 首屏大图展示',
                        required: true,
                        trailing: _uploadPill(
                          draft.imgUrl.isNotEmpty,
                          '＋ 上传 3:4',
                          _uploadBanner,
                        ),
                      ),
                      if (draft.imgUrl.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: CyTokens.space2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CyNetImage(
                              draft.imgUrl,
                              width: 90,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Divider(
                        height: CyTokens.space4,
                        color: CyPalette.of(context).borderSubtle,
                      ),
                      _rowCard(
                        title: '横版封面',
                        value: '16:9 横图 · 最多 9 张',
                        trailing: imgArrList.length < 9
                            ? _uploadPill(
                                imgArrList.isNotEmpty,
                                '＋ 上传 16:9',
                                _uploadImgArr,
                              )
                            : null,
                      ),
                      if (imgArrList.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: CyTokens.space2),
                          child: Wrap(
                            spacing: CyTokens.space2,
                            runSpacing: CyTokens.space2,
                            children: <Widget>[
                              for (var i = 0; i < imgArrList.length; i++)
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CyNetImage(
                                        imgArrList[i],
                                        width: 72,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Semantics(
                                        label: '删除图片',
                                        child: CupertinoButton(
                                          key: Key('topic-landscape-remove-$i'),
                                          onPressed: () {
                                            setState(() {
                                              imgArrList.removeAt(i);
                                              draft.imgArr = imgArrList.join(
                                                ',',
                                              );
                                              widget.onChanged();
                                            });
                                          },
                                          minimumSize: const Size(44, 44),
                                          padding: EdgeInsets.zero,
                                          alignment: Alignment.topRight,
                                          child: Icon(
                                            CupertinoIcons.xmark_circle_fill,
                                            size: 16,
                                            color: CyPalette.of(
                                              context,
                                            ).textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      Text(
                        '剧情详情',
                        style: TextStyle(
                          fontSize: CyTokens.typeLabel,
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      SizedBox(height: CyTokens.space1_5),
                      CupertinoTextField(
                        controller: _desc,
                        onChanged: (v) {
                          draft.description = v;
                          widget.onChanged();
                        },
                        maxLines: 5,
                        maxLength: 1000,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        placeholder: '写下这个主题的故事…',
                        style: TextStyle(color: palette.textPrimary),
                        placeholderStyle: TextStyle(
                          color: palette.textPlaceholder,
                        ),
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _inputDecoration(
                          palette,
                          _desc.text.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      _rowCard(
                        title: '通关勋章',
                        value: '1:1 方图 · 不传图则只显示名称',
                        trailing: draft.finishMedalImg.isNotEmpty
                            ? CupertinoButton(
                                minimumSize: const Size(44, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CyTokens.space2,
                                ),
                                foregroundColor: palette.textPrimary,
                                onPressed: () {
                                  setState(() {
                                    draft.finishMedalImg = '';
                                    widget.onChanged();
                                  });
                                },
                                child: const Text('清除'),
                              )
                            : _uploadPill(false, '上传', _uploadMedal),
                      ),
                      CupertinoTextField(
                        controller: _medal,
                        onChanged: (v) {
                          draft.finishMedalName = v;
                          widget.onChanged();
                        },
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        placeholder:
                            '默认：${draft.name.isEmpty ? '主题名' : draft.name} · 通关',
                        style: TextStyle(color: palette.textPrimary),
                        placeholderStyle: TextStyle(
                          color: palette.textPlaceholder,
                        ),
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: _inputDecoration(
                          palette,
                          _medal.text.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      _rowCard(
                        icon: CupertinoIcons.gift,
                        title: '完成奖励',
                        value: draft.completeRewardCouponId != 0
                            ? (_rewardName.isEmpty ? '已选奖励' : _rewardName)
                            : (_rewardOn ? '可选优惠券或体验卡' : '关着：只发通关勋章'),
                        trailing: CupertinoSwitch(
                          value: _rewardOn,
                          onChanged: (bool v) {
                            setState(() {
                              _rewardOn = v;
                              if (!v) {
                                draft.completeRewardCouponId = 0;
                                _rewardName = '';
                                widget.onChanged();
                              }
                            });
                          },
                        ),
                      ),
                      if (_rewardOn) ...<Widget>[
                        Divider(
                          height: CyTokens.space4,
                          color: CyPalette.of(context).borderSubtle,
                        ),
                        _rowCard(
                          title: '选择奖励',
                          value: draft.completeRewardCouponId != 0
                              ? (_rewardName.isEmpty ? '已选奖励' : _rewardName)
                              : '选一张优惠券或体验卡',
                          onTap: _pickReward,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      _rowCard(
                        icon: CupertinoIcons.globe,
                        title: '发布到创意广场',
                        value: draft.publishToCreative
                            ? '发布后在广场公开展示'
                            : '仅通过主题入口访问',
                        trailing: CupertinoSwitch(
                          value: draft.publishToCreative,
                          onChanged: (v) {
                            setState(() {
                              draft.publishToCreative = v;
                              widget.onChanged();
                            });
                          },
                        ),
                      ),
                      if (widget.myClubs.isNotEmpty) ...<Widget>[
                        Divider(
                          height: CyTokens.space4,
                          color: CyPalette.of(context).borderSubtle,
                        ),
                        _rowCard(
                          icon: CupertinoIcons.group_solid,
                          title: '归属俱乐部',
                          value: draft.clubId == null
                              ? '未选择'
                              : _clubNameById(draft.clubId!),
                          onTap: () async {
                            // 「不挂靠俱乐部」用一个约定:返回 null 之外的哨兵不好造,
                            // 这里用两个布尔区分:pop 一个固定对象即代表不挂靠。
                            final club = await showCupertinoModalPopup<Club>(
                              context: context,
                              builder: (BuildContext ctx) =>
                                  CupertinoActionSheet(
                                    title: const Text('归属俱乐部'),
                                    actions: <Widget>[
                                      for (final c in widget.myClubs)
                                        CupertinoActionSheetAction(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(c),
                                          child: Text(c.name),
                                        ),
                                      CupertinoActionSheetAction(
                                        onPressed: () => Navigator.of(
                                          ctx,
                                        ).pop(Club(id: -1, name: '')),
                                        child: const Text('不挂靠俱乐部'),
                                      ),
                                    ],
                                    cancelButton: CupertinoActionSheetAction(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('取消'),
                                    ),
                                  ),
                            );
                            if (club == null) return;
                            setState(() {
                              // id<0 表示「不挂靠」。
                              draft.clubId = club.id < 0 ? null : club.id;
                              widget.onChanged();
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: CyTokens.space6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clubNameById(int id) {
    for (final c in widget.myClubs) {
      if (c.id == id) return c.name;
    }
    return '未选择';
  }

  Widget _uploadPill(bool uploaded, String label, VoidCallback onTap) {
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
      foregroundColor: CyPalette.of(context).textPrimary,
      onPressed: _uploading ? null : onTap,
      child: Text(uploaded ? '已上传' : label),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _rowCard({
    required String title,
    required String value,
    IconData? icon,
    Widget? trailing,
    VoidCallback? onTap,
    bool required = false,
  }) {
    final Widget row = Padding(
      padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (required)
                        TextSpan(
                          text: '* ',
                          style: TextStyle(
                            color: CyPalette.of(context).statusDanger,
                          ),
                        ),
                      TextSpan(
                        text: title,
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (onTap != null)
            Text(
              '选择 ›',
              style: TextStyle(color: CyPalette.of(context).textTertiary),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      foregroundColor: CyPalette.of(context).textPrimary,
      onPressed: onTap,
      child: row,
    );
  }
}

// ---------------------------------------------------------------- 节点弹窗

class NodeSheetResult {
  const NodeSheetResult({required this.node, this.deleted = false});
  final PublishNode node;
  final bool deleted;
}

Future<NodeSheetResult?> showNodeSheet(
  BuildContext context, {
  required WidgetRef ref,
  required PublishDraft draft,
  required PublishNode? node,
  String scope = '',
}) {
  return showCupertinoSheet<NodeSheetResult>(
    context: context,
    showDragHandle: false,
    topGap: 0.08,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        _NodeSheet(
          ref: ref,
          draft: draft,
          source: node,
          isEdit: node != null,
          scope: scope,
          scrollController: scrollController,
        ),
  );
}

class _NodeSheet extends ConsumerStatefulWidget {
  const _NodeSheet({
    required this.ref,
    required this.draft,
    required this.source,
    required this.isEdit,
    required this.scope,
    required this.scrollController,
  });

  final WidgetRef ref;
  final PublishDraft draft;
  final PublishNode? source;
  final bool isEdit;
  final String scope;
  final ScrollController scrollController;

  @override
  ConsumerState<_NodeSheet> createState() => _NodeSheetState();
}

class _NodeSheetState extends ConsumerState<_NodeSheet> {
  late final PublishNode _node = widget.source?.copy() ?? PublishNode();
  late final TextEditingController _name = TextEditingController(
    text: _node.name,
  );
  late final TextEditingController _desc = TextEditingController(
    text: _node.description,
  );
  bool _showTemplate = false;

  // 模板选择面板三态。
  bool _templatesLoading = false;
  String? _templatesError;
  List<PublishTemplate> _publicTemplates = <PublishTemplate>[];
  List<PublishTemplate> _myTemplates = <PublishTemplate>[];
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _showTemplate = (_node.templateId ?? 0) > 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  PublishDraft get draft => widget.draft;
  bool get isFree => draft.productType == kProductFreeExplore;

  Future<void> _loadTemplates() async {
    setState(() {
      _templatesLoading = true;
      _templatesError = null;
    });
    try {
      final api = widget.ref.read(publishApiProvider);
      final public = await api.templateHomeData();
      final mine = await api.templateMyList(scope: widget.scope);
      if (!mounted) return;
      setState(() {
        _publicTemplates = public;
        _myTemplates = mine;
        _templatesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _templatesLoading = false;
        _templatesError = publishMessage(e, '玩法模板加载失败');
      });
    }
  }

  Future<void> _pickPoi() async {
    final poi = await context
        .push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (poi == null || !mounted) return;
    setState(() {
      _node
        ..address = poi.name
        ..longitude = poi.longitude.toString()
        ..latitude = poi.latitude.toString();
      // 选完点之后标题直接变成地点名(用户 2026-08-11 定)。
      if (_name.text.trim().isEmpty) {
        _name.text = poi.name;
        _node.name = poi.name;
      }
    });
  }

  Future<void> _addPhotos() async {
    final List<String>? urls = await pickCropAndUploadPublishImages(
      context,
      widget.ref,
      maxCount: 9 - _node.imgList.length,
      aspect: PublishCropAspect.node4x3,
    );
    if (urls == null || urls.isEmpty || !mounted) return;
    setState(() {
      final list = _node.imgList..addAll(urls);
      _node.imgUrl = list.take(9).join(',');
    });
  }

  void _confirm() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      CyNativeNotice.show(context, '请填写节点名称', isError: true);
      return;
    }
    _node.name = name;
    _node.description = _desc.text;
    _node.templateId = _showTemplate ? _node.templateId : 0;
    Navigator.of(context).pop(NodeSheetResult(node: _node));
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final photos = _node.imgList.toList();
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space3,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: '关闭节点编辑',
                    button: true,
                    onTap: _close,
                    child: CupertinoButton(
                      key: const Key('node-close'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      foregroundColor: palette.textSecondary,
                      onPressed: _close,
                      child: const ExcludeSemantics(
                        child: Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ),
                  ),
                  Text(
                    widget.isEdit ? '编辑节点' : '新建节点',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                  Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: '完成节点编辑',
                    button: true,
                    onTap: _confirm,
                    child: CupertinoButton(
                      key: const Key('node-complete'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space3,
                      ),
                      color: palette.actionPrimaryBg,
                      foregroundColor: palette.actionPrimaryFg,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                      onPressed: _confirm,
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                controller: widget.scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                children: <Widget>[
                  CupertinoTextField(
                    controller: _name,
                    maxLength: 40,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    clearButtonMode: OverlayVisibilityMode.editing,
                    placeholder: '给这个节点起个名字',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: CyTokens.typeSectionTitle,
                      fontWeight: FontWeight.w600,
                    ),
                    placeholderStyle: TextStyle(color: palette.textPlaceholder),
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: _inputDecoration(
                      palette,
                      _name.text.isNotEmpty,
                    ),
                  ),
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            CupertinoIcons.location,
                            size: 20,
                            color: CyPalette.of(context).textPrimary,
                          ),
                          SizedBox(width: CyTokens.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _node.address.isEmpty
                                      ? '地点'
                                      : (_node.name.isEmpty
                                            ? '未命名地点'
                                            : _node.name),
                                  style: TextStyle(
                                    fontSize: CyTokens.typeBody,
                                    color: CyPalette.of(context).textPrimary,
                                  ),
                                ),
                                if (_node.address.isEmpty)
                                  Text(
                                    '还没有选点',
                                    style: TextStyle(
                                      fontSize: CyTokens.typeLabel,
                                      color: CyPalette.of(
                                        context,
                                      ).textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: CyTokens.space2),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _node.address.isEmpty
                                  ? '搜索并选择一个 POI；自由探索可稍后补'
                                  : _node.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: CyTokens.typeLabel,
                                color: CyPalette.of(context).textSecondary,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space2,
                            ),
                            foregroundColor: palette.textPrimary,
                            onPressed: _pickPoi,
                            child: Semantics(
                              label: '选择或修改节点点位',
                              button: true,
                              child: Text(
                                _node.address.isEmpty ? '选择点位 ›' : '修改点位 ›',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (draft.publishMode != 'ai_simple') ...<Widget>[
                    SizedBox(height: CyTokens.space3),
                    _card(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              CupertinoIcons.play_circle,
                              size: 20,
                              color: CyPalette.of(context).textPrimary,
                            ),
                            SizedBox(width: CyTokens.space3),
                            Expanded(
                              child: Text(
                                '配置模板',
                                style: TextStyle(
                                  fontSize: CyTokens.typeBody,
                                  color: CyPalette.of(context).textPrimary,
                                ),
                              ),
                            ),
                            CupertinoSwitch(
                              value: _showTemplate,
                              onChanged: (v) {
                                setState(() {
                                  _showTemplate = v;
                                  if (v) {
                                    _pickerOpen = true;
                                    _loadTemplates();
                                  } else {
                                    // 开关态不入库,关掉必须连 templateId 一起清,
                                    // 否则重开又会被派生成「开」。
                                    _node.templateId = 0;
                                    _node.templateInfo = <String, dynamic>{};
                                    _node.templateName = '';
                                    _pickerOpen = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        if (_showTemplate) ...<Widget>[
                          SizedBox(height: CyTokens.space2),
                          Text(
                            '互动环节',
                            style: TextStyle(
                              fontSize: CyTokens.typeLabel,
                              color: CyPalette.of(context).textSecondary,
                            ),
                          ),
                          CupertinoButton(
                            minimumSize: const Size.fromHeight(44),
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                            foregroundColor: palette.textPrimary,
                            onPressed: () {
                              setState(() => _pickerOpen = !_pickerOpen);
                              if (_pickerOpen &&
                                  !_templatesLoading &&
                                  _templatesError == null &&
                                  _publicTemplates.isEmpty &&
                                  _myTemplates.isEmpty) {
                                _loadTemplates();
                              }
                            },
                            child: Semantics(
                              label: '选择或修改节点玩法',
                              button: true,
                              child: Text(
                                _node.templateId != null &&
                                        _node.templateId! > 0
                                    ? '玩法已配置，点击修改'
                                    : '选择或创建玩法模板 ›',
                              ),
                            ),
                          ),
                          if (_pickerOpen) _templatePicker(),
                        ],
                      ],
                    ),
                  ],
                  if (isFree) ...<Widget>[
                    SizedBox(height: CyTokens.space3),
                    _card(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              CupertinoIcons.pencil,
                              size: 20,
                              color: CyPalette.of(context).textPrimary,
                            ),
                            SizedBox(width: CyTokens.space3),
                            Text(
                              '文字说明',
                              style: TextStyle(
                                fontSize: CyTokens.typeBody,
                                color: CyPalette.of(context).textPrimary,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: CyTokens.space2),
                        CupertinoTextField(
                          controller: _desc,
                          maxLines: 4,
                          maxLength: 500,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          clearButtonMode: OverlayVisibilityMode.editing,
                          placeholder: '玩家到这里要观察、寻找或完成什么？',
                          style: TextStyle(color: palette.textPrimary),
                          placeholderStyle: TextStyle(
                            color: palette.textPlaceholder,
                          ),
                          padding: const EdgeInsets.all(CyTokens.space3),
                          decoration: _inputDecoration(
                            palette,
                            _desc.text.isNotEmpty,
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: CyTokens.space3),
                  _card(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            CupertinoIcons.photo,
                            size: 20,
                            color: CyPalette.of(context).textPrimary,
                          ),
                          SizedBox(width: CyTokens.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '照片',
                                  style: TextStyle(
                                    fontSize: CyTokens.typeBody,
                                    color: CyPalette.of(context).textPrimary,
                                  ),
                                ),
                                Text(
                                  '上传节点实拍，最多 9 张',
                                  style: TextStyle(
                                    fontSize: CyTokens.typeLabel,
                                    color: CyPalette.of(context).textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${photos.length}/9',
                            style: TextStyle(
                              fontSize: CyTokens.typeLabel,
                              color: CyPalette.of(context).textSecondary,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: CyTokens.space2),
                      Wrap(
                        spacing: CyTokens.space2,
                        runSpacing: CyTokens.space2,
                        children: <Widget>[
                          for (var i = 0; i < photos.length; i++)
                            Stack(
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CyNetImage(
                                    photos[i],
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Semantics(
                                    label: '删除节点照片 ${i + 1}',
                                    child: CupertinoButton(
                                      key: Key('node-photo-remove-$i'),
                                      onPressed: () {
                                        setState(() {
                                          final list = photos..removeAt(i);
                                          _node.imgUrl = list.join(',');
                                        });
                                      },
                                      minimumSize: const Size(44, 44),
                                      padding: EdgeInsets.zero,
                                      alignment: Alignment.topRight,
                                      child: Icon(
                                        CupertinoIcons.xmark_circle_fill,
                                        size: 16,
                                        color: CyPalette.of(
                                          context,
                                        ).textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (photos.length < 9)
                            CupertinoButton(
                              minimumSize: const Size(72, 72),
                              padding: EdgeInsets.zero,
                              foregroundColor: palette.textSecondary,
                              onPressed: _addPhotos,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: CyPalette.of(context).borderStrong,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                // ★ 标签挂在图标上:实测同一 Wrap 里若给它套
                                //   `Semantics(container + excludeSemantics)`,
                                //   邻居(删除角标)的语义节点会一起被查不到。
                                child: Semantics(
                                  label: '添加节点照片',
                                  child: Icon(
                                    CupertinoIcons.add,
                                    size: 24,
                                    color: CyPalette.of(context).textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.isEdit) ...<Widget>[
                    SizedBox(height: CyTokens.space3),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        key: const Key('node-delete'),
                        minimumSize: const Size.fromHeight(CyTokens.btnH),
                        color: palette.actionSecondaryBg,
                        foregroundColor: palette.statusDanger,
                        borderRadius: BorderRadius.circular(
                          CyTokens.radiusPill,
                        ),
                        onPressed: () async {
                          final bool ok = await cyConfirm(
                            context,
                            title: '删除这个节点?',
                            content: '节点的地点、玩法与照片会一起删掉，删了找不回来。',
                            confirmText: '删除',
                            danger: true,
                          );
                          if (!ok || !context.mounted) return;
                          Navigator.of(
                            context,
                          ).pop(NodeSheetResult(node: _node, deleted: true));
                        },
                        child: const _DeleteLabel('删除节点'),
                      ),
                    ),
                  ],
                  SizedBox(height: CyTokens.space6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templatePicker() {
    if (_templatesLoading) {
      return const Padding(
        padding: EdgeInsets.all(CyTokens.space4),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_templatesError != null) {
      return Padding(
        padding: EdgeInsets.all(CyTokens.space4),
        child: Column(
          children: <Widget>[
            Text(
              _templatesError!,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            SizedBox(height: CyTokens.space2),
            CupertinoButton(
              minimumSize: const Size(44, 44),
              onPressed: _loadTemplates,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: CyTokens.space3),
        Text(
          '公共玩法库',
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            fontWeight: FontWeight.w700,
            color: CyPalette.of(context).textPrimary,
          ),
        ),
        if (_publicTemplates.isEmpty)
          Text(
            '暂时拉不到，可以先用下面自己的模板',
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              color: CyPalette.of(context).textTertiary,
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _publicTemplates.length,
              separatorBuilder: (_, _) => SizedBox(width: CyTokens.space2),
              itemBuilder: (_, i) => _templateTile(_publicTemplates[i]),
            ),
          ),
        SizedBox(height: CyTokens.space3),
        Text(
          '我的模板',
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            fontWeight: FontWeight.w700,
            color: CyPalette.of(context).textPrimary,
          ),
        ),
        if (_myTemplates.isEmpty)
          Text(
            '还没建过自己的玩法',
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              color: CyPalette.of(context).textTertiary,
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _myTemplates.length,
              separatorBuilder: (_, _) => SizedBox(width: CyTokens.space2),
              itemBuilder: (_, i) => _templateTile(_myTemplates[i]),
            ),
          ),
        SizedBox(height: CyTokens.space2),
        CupertinoButton(
          key: const Key('node-create-template'),
          minimumSize: const Size.fromHeight(CyTokens.btnH),
          color: CyPalette.of(context).actionPrimaryBg,
          foregroundColor: CyPalette.of(context).actionPrimaryFg,
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          onPressed: () async {
            final bool? created = await context.push<bool>('/template/new');
            if (created == true && mounted) await _loadTemplates();
          },
          child: const Text('自己建一个玩法'),
        ),
      ],
    );
  }

  Widget _templateTile(PublishTemplate t) {
    final selected = _node.templateId == t.id;
    return CupertinoButton(
      minimumSize: const Size(110, 120),
      padding: EdgeInsets.zero,
      foregroundColor: CyPalette.of(context).textPrimary,
      onPressed: () {
        setState(() {
          _node.templateId = t.id;
          _node.templateInfo = t.raw;
          _node.templateName = t.title;
        });
      },
      child: Container(
        width: 110,
        padding: EdgeInsets.all(CyTokens.space2),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurfaceSubtle,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: selected
              ? Border.all(color: CyPalette.of(context).brand)
              : Border.all(color: CyPalette.of(context).borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: t.imgUrl.isEmpty
                    ? Container(color: CyPalette.of(context).bgElevated)
                    : CyNetImage(t.imgUrl, fit: BoxFit.cover),
              ),
            ),
            SizedBox(height: CyTokens.space1_5),
            Text(
              t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
            Text(
              '${t.players} · ${t.duration}分钟',
              style: TextStyle(
                fontSize: 10,
                color: CyPalette.of(context).textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------- 发布前检查

/// 发布前检查弹层。RUN-52 发布者实名挂在**这一层**:
/// · 已登记的人整节不见,只多一行「发布者实名已登记」;
/// · 未登记时三格(姓名/身份证号/单独同意)就在弹层里,点「确认发布」
///   **先落实名、再放行** —— 后端两道闸就是这个顺序(/api/publisher/identity
///   先于 /api/topic/create 的实名校验),并发两发会被拦成「请先登记实名信息」;
/// · 登记失败弹层不关、字段原地,报错用软红整块,不给输入框描红边。
Future<bool?> showPublishCheckSheet(
  BuildContext context, {
  required List<PublishCheckItem> blocking,
  required List<PublishCheckItem> advisory,
  XpBudget? xpBudget,
  PublisherIdentityController? identity,
  Future<IdentityRegisterOutcome> Function(PublisherIdentityController)?
  registerIdentity,
}) {
  final XpBudget? budget = xpBudget;
  return showCupertinoSheet<bool>(
    context: context,
    showDragHandle: true,
    topGap: 0.26,
    scrollableBuilder: (BuildContext ctx, ScrollController scrollController) =>
        ListenableBuilder(
          listenable: identity ?? _NoopListenable(),
          builder: (BuildContext context, _) => CupertinoPageScaffold(
            backgroundColor: CyPalette.of(ctx).bgPage,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.all(CyTokens.pageX),
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const SizedBox(width: 40),
                      Text(
                        // 小程序这一层的标题就是「发布确认」——它不是报告,是最后一页确认页。
                        '发布确认',
                        style: TextStyle(
                          fontSize: CyTokens.typeBody,
                          fontWeight: FontWeight.w700,
                          color: CyPalette.of(context).textPrimary,
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('publish-check-close'),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space2,
                        ),
                        foregroundColor: CyPalette.of(ctx).textPrimary,
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('返回修改'),
                      ),
                    ],
                  ),
                  Text(
                    '确认无误后才会真正发布，发布后进入平台审核。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: CyPalette.of(ctx).textSecondary,
                    ),
                  ),
                  SizedBox(height: CyTokens.space3),
                  if (blocking.isNotEmpty ||
                      (identity != null && !identity.satisfied)) ...<Widget>[
                    Text(
                      '必填项(需补全才能发布)',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).statusDanger,
                      ),
                    ),
                    for (final item in blocking)
                      _checkRow(
                        context,
                        CupertinoIcons.circle_fill,
                        item.label,
                        CyPalette.of(context).statusDanger,
                      ),
                    // 玩家没有向导,这一层就是最后一步,补全的控件就在下面,
                    // 所以这一条不带「去填写」——没有别处可去,指向本层那三格。
                    if (identity != null && !identity.satisfied)
                      _checkRow(
                        context,
                        CupertinoIcons.circle_fill,
                        '发布者实名未填写(在本层填写)',
                        CyPalette.of(context).statusDanger,
                      ),
                  ],
                  if (advisory.isNotEmpty) ...<Widget>[
                    SizedBox(height: CyTokens.space3),
                    Text(
                      '建议完善(不影响发布)',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                    for (final item in advisory)
                      _checkRow(
                        context,
                        CupertinoIcons.circle_fill,
                        item.label,
                        CyPalette.of(context).textTertiary,
                      ),
                  ],
                  if (identity != null && identity.registered) ...<Widget>[
                    SizedBox(height: CyTokens.space3),
                    _checkRow(
                      context,
                      CupertinoIcons.checkmark_circle_fill,
                      '发布者实名已登记',
                      CyPalette.of(context).statusSuccess,
                    ),
                  ],
                  SizedBox(height: CyTokens.space3),
                  // RUN-52 发布者实名:挂在发布确认这一层(用户裁定「放最后一步」)。
                  if (identity != null && !identity.registered) ...<Widget>[
                    PublisherIdentityFields(
                      controller: identity,
                      title: '发布者实名',
                      footHint: '填过一次就不再出现。变更实名信息请联系平台客服。',
                    ),
                    SizedBox(height: CyTokens.space3),
                  ],
                  // 奖励总览(只读:XP 自动分配 / 通关勋章)。
                  if (blocking.isEmpty &&
                      (identity == null || identity.satisfied)) ...<Widget>[
                    Text(
                      '奖励总览',
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        fontWeight: FontWeight.w700,
                        color: CyPalette.of(context).textPrimary,
                      ),
                    ),
                    SizedBox(height: CyTokens.space2),
                    // 发布前的 budget-bar(`/api/topic/xp-budget`)。没有它,
                    // 创作者只能等**提交之后**被后端拒才知道超了 ——
                    // 那时整个表单已经填完。读不回来就整栏不显示,不兜 0。
                    if (budget != null) _XpBudgetOverview(budget: budget),
                  ],
                  SizedBox(height: CyTokens.space4),
                  if (blocking.isEmpty)
                    CupertinoButton(
                      key: const Key('publish-check-continue'),
                      minimumSize: const Size.fromHeight(CyTokens.btnH),
                      color: CyPalette.of(ctx).actionPrimaryBg,
                      foregroundColor: identity != null && identity.busy
                          ? CyPalette.of(ctx).textPlaceholder
                          : CyPalette.of(ctx).actionPrimaryFg,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                      onPressed: identity != null && identity.busy
                          ? null
                          : () async {
                              if (identity != null && !identity.registered) {
                                // 实名不齐时点「确认发布」不静默放行,报第一条
                                // 没满足的原因(真源:置灰键会说话)。
                                final problem = identity.firstProblem;
                                if (problem != null) {
                                  CyNativeNotice.show(
                                    ctx,
                                    problem,
                                    isError: true,
                                  );
                                  return;
                                }
                                identity.setBusy(true);
                                final outcome = await registerIdentity!(
                                  identity,
                                );
                                if (!ctx.mounted) return;
                                identity.setBusy(false);
                                if (!outcome.ok) {
                                  // 弹层不关:字段就在原地,改完再点一次。
                                  identity.setError(outcome.message);
                                  return;
                                }
                                identity.markRegistered();
                              }
                              Navigator.of(ctx).pop(true);
                            },
                      child: const Text('确认发布'),
                    )
                  else
                    Text(
                      '请先处理上方必填项后再发布',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
  );
}

class _NoopListenable extends Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// 发布前检查里的 XP 预算条。
///
/// ★ 是否超预算**以后端的 `over` 为准**,不前端比大小(边界与豁免规则在服务端)。
/// ★ `usedRatio == null`(budget 为 0)时**不画进度条** ——
///   「没有预算」和「预算用了 0%」是两回事。
class _XpBudgetOverview extends StatelessWidget {
  const _XpBudgetOverview({required this.budget});

  final XpBudget budget;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final double? ratio = budget.usedRatio;
    final TextStyle label = TextStyle(
      fontSize: CyTokens.typeLabel,
      color: palette.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('探索值(XP)', style: label),
            Text('${budget.totalXp} / ${budget.budget}', style: label),
          ],
        ),
        if (ratio != null) ...<Widget>[
          SizedBox(height: CyTokens.space1),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: palette.borderSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: budget.over
                      ? palette.statusDanger
                      : palette.actionPrimaryBg,
                  borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: CyTokens.space1),
        Text(
          budget.over
              ? '已超预算 ${budget.overBy} XP —— 提交会被拒收,先把节点奖励调低'
              : '未分配的 ${budget.remain} XP 会成为通关奖励,不必分光',
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: budget.over ? palette.statusDanger : palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

Widget _checkRow(
  BuildContext context,
  IconData icon,
  String label,
  Color color,
) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: CyTokens.space1_5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 8, color: color),
        SizedBox(width: CyTokens.space2),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- 发布成功

/// 发布成功弹层。返回 'preview' = 去预览玩家视角,'projects' = 去我的项目,
/// null = 就地关掉。
///
/// ★ 眉标原来写「城市路线已发布」—— 这时候它其实只是提交完、还在平台审核里,
///   界面却告诉人已经发布了。审核不通过时人只会觉得平台弄丢了他的东西。
///   文案说的是真的那一步:已提交,审核通过后才对外售票。
Future<String?> showPublishSuccessSheet(
  BuildContext context, {
  required String name,
  required int topicId,
  required int chapterCount,
  required int nodeCount,
  required bool isCity,
}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (BuildContext ctx) => CupertinoActionSheet(
      title: const Text('已提交'),
      message: Text(
        '主题已发布，审核通过后即可对外售票。\n'
        '${isCity ? '城市定向' : '自由探索'} · $chapterCount 章 $nodeCount 节点\n'
        '${name.isEmpty ? '新路线' : name}',
      ),
      actions: <Widget>[
        if (topicId > 0)
          CupertinoActionSheetAction(
            key: const Key('publish-success-preview'),
            onPressed: () => Navigator.of(ctx).pop('preview'),
            child: const Text('预览玩家看到的'),
          ),
        CupertinoActionSheetAction(
          key: const Key('publish-success-done'),
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop('projects'),
          child: const Text('去我的项目'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('取消'),
      ),
    ),
  );
}

/// 垃圾桶 + 文案。删除动作的图标口径:
/// 垃圾桶 = 丢掉只存在于这里的东西(必须二次确认);
/// ✕ = 只是摘掉一个引用,原件还在别处(点了就走,不弹确认)。
class _DeleteLabel extends StatelessWidget {
  const _DeleteLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(CupertinoIcons.delete, size: 18),
        SizedBox(width: CyTokens.space2),
        Text(text),
      ],
    );
  }
}

BoxDecoration _inputDecoration(CyPalette palette, bool hasValue) {
  return BoxDecoration(
    color: hasValue ? palette.inputBgFilled : palette.inputBgEmpty,
    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    border: Border.all(color: palette.borderSubtle),
  );
}
