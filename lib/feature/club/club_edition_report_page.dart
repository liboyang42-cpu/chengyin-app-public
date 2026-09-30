import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_manage.dart';
import 'club_controller.dart';
import 'edition_report_validation.dart';

/// 探店日:俱乐部自报四类工时 + 提交质量证据。
/// 对齐小程序 `pages/club/edition-report`(E1「俱乐部填四类工时,平台后台逐条确认」)。
///
/// ★ 候选期次的真源是**开售冻结条款里的执行俱乐部**(/api/club-compensation/editions),
///   不是 /api/club/topics —— 那按 cms_topic.club_id 过滤,探店日期次那列为 NULL。
class ClubEditionReportPage extends ConsumerStatefulWidget {
  const ClubEditionReportPage({super.key, this.clubId});
  final int? clubId;

  @override
  ConsumerState<ClubEditionReportPage> createState() =>
      _ClubEditionReportPageState();
}

const List<({String key, String label})> _hourKinds =
    <({String key, String label})>[
      (key: 'PREP', label: '准备'),
      (key: 'CONTENT', label: '内容'),
      (key: 'ONSITE', label: '现场'),
      (key: 'REVIEW', label: '复盘'),
    ];

const List<({String key, String label})> _dimensions =
    <({String key, String label})>[
      (key: 'DELIVERY_SAFETY', label: '交付与安全'),
      (key: 'PLAYER_EXPERIENCE', label: '玩家体验'),
      (key: 'CONTENT_REPORT', label: '内容与回顾报告'),
    ];

class _ClubEditionReportPageState extends ConsumerState<ClubEditionReportPage> {
  int? _topicId;
  final Map<String, TextEditingController> _hourControllers =
      <String, TextEditingController>{};
  String _dimension = _dimensions.first.key;
  final TextEditingController _evidenceController = TextEditingController();
  String _submittingKind = '';

  @override
  void initState() {
    super.initState();
    for (final kind in _hourKinds) {
      _hourControllers[kind.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _hourControllers.values) {
      c.dispose();
    }
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _submitHours(String kind) async {
    final raw = _hourControllers[kind]?.text ?? '';
    final error = hoursInputError(raw);
    if (error != null) {
      _toast(error, isError: true);
      return;
    }
    final topicId = _topicId;
    final clubId = widget.clubId;
    if (topicId == null || clubId == null) {
      _toast(kPickEditionFirst, isError: true);
      return;
    }
    setState(() => _submittingKind = kind);
    try {
      await ref
          .read(clubCompensationApiProvider)
          .reportHours(
            topicId: topicId,
            clubId: clubId,
            hourKind: kind,
            actualHours: double.parse(raw.trim()),
          );
      if (!mounted) return;
      _toast('已自报，等待平台确认');
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _submittingKind = '');
    }
  }

  Future<void> _submitEvidence() async {
    final error = evidenceHashError(_evidenceController.text);
    if (error != null) {
      _toast(error, isError: true);
      return;
    }
    final topicId = _topicId;
    final clubId = widget.clubId;
    if (topicId == null || clubId == null) {
      _toast(kPickEditionFirst, isError: true);
      return;
    }
    setState(() => _submittingKind = 'evidence');
    try {
      await ref
          .read(clubCompensationApiProvider)
          .submitEvidence(
            topicId: topicId,
            clubId: clubId,
            dimension: _dimension,
            evidenceHash: _evidenceController.text.trim().toLowerCase(),
          );
      if (!mounted) return;
      _toast('证据已提交');
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _submittingKind = '');
    }
  }

  void _toast(String message, {bool isError = false}) {
    CyNativeNotice.show(context, message, isError: isError);
  }

  /// 带票分享 = 把票源归因标记拼进主题链接。真源
  /// `pages/club/detail/index.js:2653-2665` + `utils/ticket-source.js:146-157`:
  /// 链接带 `sourceClubId` 与 `clubCode=club-<clubId>-t<topicId>` ——
  /// 两个都是真 ID 合成,绝不凭空造码(ticket-source 的 fail-closed 底线)。
  Future<void> _shareEditionWithTicket(
    int clubId,
    EditionOption edition,
  ) async {
    final Uri url = Uri(
      scheme: 'https',
      host: 'api.example.invalid',
      pathSegments: <String>['topic', '${edition.id}'],
      queryParameters: <String, String>{
        'sourceClubId': '$clubId',
        'clubCode': 'club-$clubId-t${edition.id}',
      },
    );
    await SharePlus.instance.share(
      ShareParams(
        subject: edition.topicName.isNotEmpty ? edition.topicName : '城瘾',
        text: url.toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clubId = widget.clubId;
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('探店日工时与证据'),
              Expanded(
                child: clubId == null
                    ? const StatusView(
                        message: '缺少俱乐部信息',
                        sub: '请从俱乐部管理入口进入本页',
                        icon: CupertinoIcons.exclamationmark_triangle,
                        large: true,
                      )
                    : _buildContent(clubId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(int clubId) {
    final editions = ref.watch(clubEditionsProvider(clubId));
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        Text(
          '四类工时由俱乐部自报、平台后台逐条确认后才计入结算；自报本身不等于已确认。',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
        const SizedBox(height: CyTokens.space4),
        const CySectionTitle('本次自报的期次'),
        const SizedBox(height: CyTokens.space2),
        editions.when(
          // 期次区只是 ListView 里的一块,不能用 CySkeleton(card) —— 它自带
          // ListView,嵌套在纵向 viewport 里会报 unbounded height。
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: CyTokens.space6),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (Object err, StackTrace st) => StatusView(
            message: '期次加载失败',
            sub: '检查网络后重试',
            icon: CupertinoIcons.exclamationmark_triangle,
            onRetry: () => ref.invalidate(clubEditionsProvider(clubId)),
          ),
          data: (List<EditionOption> list) {
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(CyTokens.space3),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  border: Border.all(color: CyTokens.borderSubtle),
                ),
                child: Text(
                  '本俱乐部当前没有已开售的探店日期次。期次要在平台开售冻结之后才会出现在这里。',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _EditionPicker(
                  options: list,
                  selectedId: _topicId,
                  onChanged: (int? id) => setState(() => _topicId = id),
                ),
                // 真源 `pages/club/detail/index.wxml:501-524` 探店日期次面板的
                // 「带票分享」—— 列表页在这,分享按钮此前没做。
                const SizedBox(height: CyTokens.space4),
                const CySectionTitle('带票分享'),
                const SizedBox(height: CyTokens.space2),
                for (final EditionOption option in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CyTokens.space2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                        border: Border.all(color: CyTokens.borderSubtle),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          CyTokens.space3,
                          CyTokens.space2,
                          CyTokens.space2,
                          CyTokens.space2,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    option.topicName.isNotEmpty
                                        ? option.topicName
                                        : '期次 #${option.id}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${option.dateText.isNotEmpty ? option.dateText : '时间待定'} · 执行俱乐部期次',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: CyTokens.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoButton.tinted(
                              key: Key('edition-share-${option.id}'),
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.space3,
                              ),
                              onPressed: () =>
                                  _shareEditionWithTicket(clubId, option),
                              child: const Text('带票分享'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: CyTokens.space6),
        const CySectionTitle('实际工时自报'),
        const SizedBox(height: CyTokens.space2),
        Text(
          '自报只写上报值,平台后台逐条确认后才计入实际工时。',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
        const SizedBox(height: CyTokens.space3),
        for (final kind in _hourKinds)
          _HourRow(
            key: ValueKey<String>(kind.key),
            label: kind.label,
            controller: _hourControllers[kind.key]!,
            busy: _submittingKind == kind.key,
            onSubmit: () => _submitHours(kind.key),
          ),
        const SizedBox(height: CyTokens.space6),
        const CySectionTitle('质量证据提交'),
        const SizedBox(height: CyTokens.space2),
        CyField(
          label: '质量维度',
          child: _CupertinoChoiceField<String>(
            key: const ValueKey<String>('dimension-picker'),
            title: '选择质量维度',
            placeholder: '选择质量维度',
            options: <({String value, String label})>[
              for (final d in _dimensions) (value: d.key, label: d.label),
            ],
            value: _dimension,
            onChanged: (String value) => setState(() => _dimension = value),
          ),
        ),
        CyField(
          label: '证据哈希',
          child: CupertinoTextField(
            key: const ValueKey<String>('edition-evidence-hash'),
            controller: _evidenceController,
            maxLines: 1,
            maxLength: 64,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(64),
            ],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: CyTokens.typeBody,
            ),
            placeholderStyle: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: CyTokens.textTertiary),
            placeholder: '证据文件 SHA-256',
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: _editionFieldDecoration(context),
          ),
        ),
        CupertinoButton.filled(
          minimumSize: const Size.fromHeight(44),
          onPressed: _submittingKind == 'evidence' ? null : _submitEvidence,
          child: _submittingKind == 'evidence'
              ? const CupertinoActivityIndicator()
              : const Text('提交证据'),
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          '超过开售冻结的证据截止(活动结束 + 7 天)后不再收,届时该维按 0 结。',
          style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
        ),
      ],
    );
  }
}

class _EditionPicker extends StatelessWidget {
  const _EditionPicker({
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final List<EditionOption> options;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _CupertinoChoiceField<int>(
      key: const ValueKey<String>('edition-picker'),
      title: '选择要报的期次',
      placeholder: '选择要报的期次',
      options: <({int value, String label})>[
        for (final EditionOption option in options)
          (value: option.id, label: option.label),
      ],
      value: selectedId,
      onChanged: onChanged,
    );
  }
}

class _CupertinoChoiceField<T> extends StatelessWidget {
  const _CupertinoChoiceField({
    super.key,
    required this.title,
    required this.placeholder,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String placeholder;
  final List<({T value, String label})> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = options.indexWhere(
      (({String label, T value}) option) => option.value == value,
    );
    final String label = selectedIndex < 0
        ? placeholder
        : options[selectedIndex].label;
    return Semantics(
      excludeSemantics: true,
      button: true,
      enabled: options.isNotEmpty,
      label: title,
      value: selectedIndex < 0 ? '未选择' : label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          border: Border.all(color: CyTokens.borderSubtle),
        ),
        child: CupertinoButton(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space3,
            vertical: CyTokens.space2,
          ),
          onPressed: options.isEmpty ? null : () => _pick(context),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selectedIndex < 0
                        ? CyTokens.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              const Icon(
                CupertinoIcons.chevron_down,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final T? picked = await showCupertinoModalPopup<T>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: Text(title),
        actions: <Widget>[
          for (final ({String label, T value}) option in options)
            CupertinoActionSheetAction(
              isDefaultAction: option.value == value,
              onPressed: () => Navigator.of(sheetContext).pop(option.value),
              child: Text(option.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    super.key,
    required this.label,
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final String label;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: CupertinoTextField(
              key: ValueKey<String>('edition-hours-${label.toLowerCase()}'),
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              placeholder: '小时',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: _editionFieldDecoration(context),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          CupertinoButton.filled(
            minimumSize: const Size(64, 44),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const CupertinoActivityIndicator(radius: 7)
                : const Text('自报'),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _editionFieldDecoration(BuildContext context) {
  final CyPalette palette = CyPalette.of(context);
  return BoxDecoration(
    color: palette.bgSurface,
    border: Border.all(color: palette.borderSubtle),
    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
  );
}
