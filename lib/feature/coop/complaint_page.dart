import 'coop_guard.dart';
import '../../l10n/strings.dart';
import 'coop_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 发起投诉。玩家侧,App 此前没有这一页。
///
/// ★★ 选择源**必须**是 `/api/coop/complaint/topics`,不能拿「我参与的」顶替。
///   后端注释记了两个真库实测出来的坑:
///   ① 那条链路末端会砍掉结束超过 7 天的主题(订单列表的视觉收纳规则),
///      而投诉本就是事后行为、受理口没有时间窗
///      ⇒ 玩家选不到、后端却允许;
///   ② 那条链路只对 owner_type=1 挂主题,活动单两个取 id 的来源全空,
///      ③ 自由探索玩家**整条选不到**。
///   选择源与受理口读的是同一份判据,换一个就必然漂。
///
/// ★★ 表单**只有主题 + 说明两项**。后端只信任这两个 ——
///   过错方 / 垫付额 / 过错比例 / 扣划额一律由客服后台设。
///   在这里放一个"选择过错方"或"填写赔付金额",用户填完会以为
///   自己已经索赔了,而那些值根本没被读。
final complainableTopicsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.read(coopApiProvider).complainableTopics();
    });

class ComplaintPage extends ConsumerStatefulWidget {
  const ComplaintPage({super.key});

  @override
  ConsumerState<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends ConsumerState<ComplaintPage> {
  static const List<String> _complaintTypes = <String>[
    '服务与履约',
    '费用与退款',
    '安全与纠纷',
    '虚假宣传',
    '其他',
  ];

  final TextEditingController _reason = TextEditingController();

  /// 联系方式(选填)。
  ///
  /// ★★ 后端 `/api/coop/complaint/report` 只收 `{topicId, reason}`,
  ///   **没有单独的联系方式字段**。小程序的做法是把它**拼进 reason**
  ///   (`reason + '\n联系方式：' + contact`,见 complaint/index.js:131)。
  ///   照搬这个做法 —— 自己另发一个后端不认的字段,等于没填。
  ///
  /// ⚠️ 我第一次读那页时只看了 `data: JSON.stringify({topicId, reason})`
  ///   就判定「小程序收集了但不发送、是死字段」——**错的**,拼接在上面几行。
  ///   看提交语句不看它上面的赋值,会把「换了个地方发」读成「没发」。
  final TextEditingController _contact = TextEditingController();
  int? _topicId;
  int? _typeIndex;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _contact.dispose();
    super.dispose();
  }

  /// 正文 + 联系方式。与小程序同一种拼法(换行 + 「联系方式：」前缀),
  /// 这样客服在后台看到的格式是一致的。
  String _composedReason() {
    String r = _reason.text.trim();
    if (_typeIndex != null) {
      r = '【${_complaintTypes[_typeIndex!]}】$r';
    }
    final String c = _contact.text.trim();
    return c.isEmpty ? r : '$r\n联系方式：$c';
  }

  bool get _canSubmit =>
      _topicId != null && _reason.text.trim().length >= 5 && !_busy;

  Future<int?> _pickOption({
    required String title,
    required List<String> options,
    int? selected,
  }) {
    return showCupertinoSheet<int>(
      context: context,
      showDragHandle: true,
      topGap: 0.18,
      scrollableBuilder:
          (BuildContext sheetContext, ScrollController scrollController) {
            final CyPalette palette = CyPalette.of(sheetContext);
            return CupertinoPageScaffold(
              backgroundColor: palette.bgPage,
              navigationBar: CupertinoNavigationBar(middle: Text(title)),
              child: SafeArea(
                top: false,
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space2,
                  ),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: CyTokens.pageX),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final bool isSelected = selected == index;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      child: CupertinoButton(
                        minimumSize: const Size.fromHeight(52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.pageX,
                          vertical: CyTokens.space2,
                        ),
                        alignment: Alignment.centerLeft,
                        onPressed: () => Navigator.of(sheetContext).pop(index),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                options[index],
                                style: TextStyle(color: palette.textPrimary),
                              ),
                            ),
                            if (isSelected)
                              const Icon(CupertinoIcons.check_mark, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
    );
  }

  Future<void> _pickTopic(List<Map<String, dynamic>> topics) async {
    final int selected = topics.indexWhere(
      (Map<String, dynamic> topic) =>
          topic['topicId'] is num &&
          (topic['topicId'] as num).toInt() == _topicId,
    );
    final int? index = await _pickOption(
      title: stringsOf(context).coopPickComplaintActivity,
      options: topics
          .map(
            (Map<String, dynamic> topic) =>
                (topic['topicName'] ?? stringsOf(context).coopUnnamedActivity).toString(),
          )
          .toList(),
      selected: selected < 0 ? null : selected,
    );
    if (index == null || !mounted) return;
    final Object? rawId = topics[index]['topicId'];
    if (rawId is! num) return;
    setState(() => _topicId = rawId.toInt());
  }

  Future<void> _pickType() async {
    final int? index = await _pickOption(
      title: stringsOf(context).coopPickComplaintType,
      options: List<String>.generate(_complaintTypes.length,
          (index) => coopComplaintCategory(context, index)),
      selected: _typeIndex,
    );
    if (index != null && mounted) setState(() => _typeIndex = index);
  }

  Widget _selectionField({
    required Key key,
    required String text,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: CupertinoButton(
        key: key,
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: palette.bgSurface,
        foregroundColor: selected ? palette.textPrimary : palette.textSecondary,
        alignment: Alignment.centerLeft,
        onPressed: onPressed,
        child: Row(
          children: <Widget>[
            Expanded(child: Text(text, textAlign: TextAlign.left)),
            const Icon(CupertinoIcons.chevron_forward, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String placeholder,
    required int maxLength,
    required int maxLines,
    required ValueChanged<String> onChanged,
    TextInputAction? textInputAction,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: placeholder,
      maxLength: maxLength,
      minLines: maxLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      autocorrect: true,
      enableSuggestions: true,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: palette.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      onChanged: onChanged,
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(coopApiProvider)
          .reportComplaint(topicId: _topicId!, reason: _composedReason());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      // ★ 说「已受理」而不是「已解决」——后端 status=0 就叫受理,
      //   后面还有垫付/追偿/关闭三档,不能替客服承诺结果。
      CyNativeNotice.show(context, stringsOf(context).coopComplaintSubmitted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // 两种正常拒绝(非参与者 / 已有处理中的投诉)都靠原文说清,
        // 渲成「提交失败,请重试」会让人一直点。
        _error = coopErrorSub(e, context: context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(complainableTopicsProvider);
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).coopComplaintTitle)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.space4,
              CyTokens.space3,
              CyTokens.space4,
              CyTokens.space2,
            ),
            child: Text(
              stringsOf(context).coopComplaintEligibility,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CupertinoActivityIndicator(),
                    SizedBox(height: CyTokens.space2),
                    Text(stringsOf(context).coopComplaintActivitiesLoading),
                  ],
                ),
              ),
              error: (Object e, StackTrace st) => StatusView(
                // 加载失败不止断网(还有 401),泛化失败字形比首轮选的 `cloud`
                // 诚实;口径同 club 域各页错误态。
                icon: CupertinoIcons.exclamationmark_circle,
                message: stringsOf(context).coopComplaintActivitiesFailed,
                sub: coopErrorSub(e, context: context),
                large: true,
                onRetry: () => ref.invalidate(complainableTopicsProvider),
              ),
              data: (List<Map<String, dynamic>> topics) {
                if (topics.isEmpty) {
                  return StatusView(
                    icon: CupertinoIcons.tray,
                    message: stringsOf(context).coopNoComplaintActivities,
                    // 说清判据,否则玩家会以为是 bug。
                    sub: stringsOf(context).coopComplaintEligibilityEmpty,
                    large: true,
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    Text(stringsOf(context).coopComplaintActivity, style: t.labelLarge),
                    const SizedBox(height: CyTokens.space2),
                    _selectionField(
                      key: const Key('complaint-topic-picker'),
                      text: _topicId == null
                          ? stringsOf(context).coopChooseComplaintActivity
                          : (topics.firstWhere(
                                      (Map<String, dynamic> topic) =>
                                          topic['topicId'] is num &&
                                          (topic['topicId'] as num).toInt() ==
                                              _topicId,
                                      orElse: () => <String, dynamic>{},
                                    )['topicName'] ??
                                    stringsOf(context).coopUnnamedActivity)
                                .toString(),
                      selected: _topicId != null,
                      onPressed: () => _pickTopic(topics),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    Text(stringsOf(context).coopComplaintType, style: t.labelLarge),
                    const SizedBox(height: CyTokens.space2),
                    _selectionField(
                      key: const Key('complaint-type-picker'),
                      text: _typeIndex == null
                          ? stringsOf(context).coopChooseComplaintType
                          : coopComplaintCategory(context, _typeIndex!),
                      selected: _typeIndex != null,
                      onPressed: _pickType,
                    ),
                    const SizedBox(height: CyTokens.space4),
                    Text(stringsOf(context).coopComplaintContent, style: t.labelLarge),
                    const SizedBox(height: CyTokens.space2),
                    _textField(
                      key: const Key('complaint-reason'),
                      controller: _reason,
                      placeholder: stringsOf(context).coopComplaintPlaceholder,
                      maxLength: 500,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    Text(stringsOf(context).coopContactDetails, style: t.labelLarge),
                    const SizedBox(height: CyTokens.space2),
                    _textField(
                      controller: _contact,
                      key: const Key('complaint-contact'),
                      placeholder: stringsOf(context).coopComplaintContact,
                      maxLength: 50,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {},
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: CyTokens.space3),
                      Text(_error!, style: TextStyle(color: p.statusDanger)),
                    ],
                    const SizedBox(height: CyTokens.space5),
                    CupertinoButton.filled(
                      key: const Key('complaint-submit'),
                      minimumSize: const Size.fromHeight(44),
                      onPressed: _canSubmit ? _submit : null,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CupertinoActivityIndicator(),
                            )
                          : Text(stringsOf(context).coopSubmitComplaint),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
