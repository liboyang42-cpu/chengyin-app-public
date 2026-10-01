import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_recruit.dart';
import 'merchant_error_view.dart';
import 'merchant_recruit_sheets.dart';

/// 改一条商家报名。对齐 `/api/registration/merchant/update`。
///
/// ★★ 这一页存在的理由,就是让被驳回的报名**能改而不是只能取消重报**:
///   服务端原注释写着「被驳回的商家想补一张现场图,只能取消重报,
///   记录丢失、重新排队」。
///
/// ★★ 为什么以前不许接这条接口 —— 以及为什么现在可以接了:
///   当时的理由是「App 侧没有完整的报名编辑表单,接了会拿半截数据覆盖后端」。
///   核到服务端后这条前提**只对了一半**:
///     · 覆盖成空这件事不会发生 —— `MerchantRegistrationEditServiceImpl`
///       只 set 九个白名单字段,mapper 又是逐字段 `<if test="x != null">`
///       的增量更新,没发的字段原样保留;
///     · 但「表单不完整」的实害是**另一件事**:界面上少一项,商家就永远改不了
///       那一项。所以这一页把九个可写字段里 App 采集得到的七项一次全给,
///       并且**每一项都无条件发出去**(空值也发),这样"清空"才真的能清掉。
///   (startDate / endDate 有意不发,理由见 [MerchantRegistrationFormState.toJson]。)
final merchantRegistrationDetailProvider = FutureProvider.autoDispose
    .family<MerchantRegistrationDetail, int>((ref, int id) async {
      final Map<String, dynamic> raw = await ref
          .watch(merchantApiProvider)
          .topicRegistrationDetail(id);
      return MerchantRegistrationDetail.fromJson(raw);
    });

class MerchantRegistrationEditPage extends ConsumerWidget {
  const MerchantRegistrationEditPage({super.key, required this.registrationId});

  final int registrationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MerchantRegistrationDetail> async = ref.watch(
      merchantRegistrationDetailProvider(registrationId),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantCatalogEditTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            // 表单编辑页,真源报名/资料编辑族一律 form-section 档(字段同构不跳位)。
            loading: () => const CySkeleton(
              type: CySkeletonType.formSection,
              count: 3,
            ),
            error: (Object e, StackTrace _) => merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(
                merchantRegistrationDetailProvider(registrationId),
              ),
            ),
            data: (MerchantRegistrationDetail d) => _Editor(detail: d),
          ),
        ),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.detail});

  final MerchantRegistrationDetail detail;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final MerchantRegistrationFormState _form = MerchantRegistrationFormState();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _form.addListener(_onChanged);
    // ★ 用详情把表单**填满**再让人改。空表单 + 增量更新 = 商家以为自己只改了一项,
    //   实际把没碰过的那些也照空值提交了一遍。
    _form.seed(widget.detail);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _form.removeListener(_onChanged);
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    String text;
    bool isError = false;
    try {
      text = await ref.read(merchantApiProvider).updateTopicRegistration(
        <String, dynamic>{
          'id': widget.detail.id,
          // topicId 服务端 @Validated 要求非空;它不在可改白名单里,
          // 原样带回去只是为了过校验,改不了标的。
          'topicId': widget.detail.topicId,
          ..._form.toJson(),
        },
      );
    } on MerchantApiException catch (e) {
      // 「主题已开始,承接内容不能再修改」/「该报名已通过审核」/「无权修改他人报名」
      // —— 每一句都在说清楚为什么改不了,照原文显示。
      text = e.message;
      isError = true;
    } catch (e) {
      text = e.toString().replaceFirst('Exception: ', '');
      isError = true;
    } finally {
      ref.invalidate(merchantRegistrationDetailProvider(widget.detail.id));
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    CyNativeNotice.show(context, text, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final MerchantRegistrationDetail d = widget.detail;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;

    // ★ 改不了的就别摆一张能填的表 —— 已中标、已通过、主题已开始都归服务端管,
    //   前端能判的那一半(状态)先判掉,少一次必然失败的提交。
    if (!d.canEdit) {
      return StatusView(
        key: const Key('reg-edit-locked'),
        icon: CupertinoIcons.lock,
        message: d.isWon ? stringsOf(context).merchantCatalogEditWonLocked : stringsOf(context).merchantCatalogEditLocked,
        sub: d.isWon
            ? stringsOf(context).merchantCatalogEditWonHint
            : stringsOf(context).merchantCatalogEditLockedHint,
        large: true,
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.pageX),
            children: <Widget>[
              Text(
                (d.topicName ?? '').trim().isEmpty
                    ? stringsOf(context).merchantCatalogThisApplication
                    : d.topicName!.trim(),
                style: t.titleMedium,
              ),
              if ((d.nodeName ?? '').trim().isNotEmpty)
                Text(
                  stringsOf(context).merchantCatalogAssignedStop(d.nodeName!.trim()),
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              // 被驳回时把原因摆在表单最上面 —— 商家是照着它改的。
              if (d.status == 2) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                Container(
                  key: const Key('reg-edit-reason'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: BoxDecoration(
                    color: p.bgSubtle,
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  ),
                  child: Text(
                    (d.reason ?? '').trim().isEmpty
                        ? stringsOf(context).merchantCatalogMissingEditReason
                        : stringsOf(context).merchantCatalogReason(d.reason!.trim()),
                    style: t.bodySmall,
                  ),
                ),
                const SizedBox(height: CyTokens.space2),
                Text(
                  stringsOf(context).merchantCatalogResubmitHint,
                  style: t.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
              const SizedBox(height: CyTokens.space4),
              // ★ 表单放在白卡里,与小程序 `ma-card wizard-card` 同形。
              //   不只是好看:商家浅色页的**页底色和描边按钮的填充色是同一档灰**,
              //   直接铺在页底上时「添加照片」这类按钮看不出是个按钮
              //   (2026-08-19 看第一版基准图发现的)。
              Container(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space3,
                  CyTokens.space4,
                  CyTokens.space3,
                  CyTokens.space1,
                ),
                decoration: BoxDecoration(
                  color: p.bgSurface,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  border: Border.all(color: p.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _form.fields(context, ref),
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              // ★ 说清楚哪些改不了,别让人以为是界面漏了。
              Text(
                '承接的路线、站点和玩法模板不能在这里改;分成与结算也不由报名内容决定。',
                style: t.bodySmall?.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ),
        CyFooterBar(
          primary: CyNativeButton(
            key: const Key('reg-edit-save'),
            onPressed: _busy || !_form.isComplete ? null : _save,
            label: stringsOf(context).merchantCatalogSave,
            loading: _busy,
          ),
          secondary: CyNativeButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            label: stringsOf(context).merchantCatalogBack,
            role: CyNativeButtonRole.secondary,
          ),
        ),
      ],
    );
  }
}
