// 创作者中心 —— 对应小程序 subpackageP3/pages/creator/index。
//
// App 此前**整页缺失**:只有 creator_controller.dart 和一个路由常量 '/creator',
// 既没有页面也没有 GoRoute。
//
// ★★ 四态各说各的(模型注释已写明,这里是它的界面对应):
//   not_applied → 给申请表单
//   pending     → 说「审核中」,不给表单(重复提交后端也会拒)
//   approved    → 不给表单,给数据概览与收益
//   rejected    → **说清为什么被拒**,但**不给表单**,见下
//
// ⚠️⚠️ 与小程序的一处**有意偏离**,原因是后端:
//   `CreatorCenterServiceImpl.apply` 开头有
//       if (creatorProfileMapper.selectByMemberId(memberId) != null) return 0;
//   —— 只要有过档案就拒收。**被驳回的人永远重申请不了。**
//   小程序照样给 rejected 一张表单(`applyStatus === 'rejected'` 那个分支),
//   按下去后端返回 0,而 code 仍是 200 ⇒ 一次「提交成功但什么都没存」的静默失败。
//   这正是本项目最高频的那类问题:**声称存在、实际不生效的保证**。
//   所以这里不复制那张表单,如实说明要联系客服。
//   后端放开重申请后,把这段和下面的 _canReallyApply 一起改掉即可。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/creator_center.dart';
import 'creator_controller.dart';

/// 真正按得下去的申请:只有**从没建过档案**的人。
/// 与 `CreatorCenter.canApply`(含 rejected)有意不同 —— 那个是「业务上该不该」,
/// 这个是「后端现在收不收」。两者不一致时以后者为准,否则就是给假保证。
bool canReallyApply(CreatorApplyStatus s) => s == CreatorApplyStatus.notApplied;

String applyStatusText(CreatorApplyStatus s) {
  switch (s) {
    case CreatorApplyStatus.approved:
      return '已通过';
    case CreatorApplyStatus.pending:
      return '审核中';
    case CreatorApplyStatus.rejected:
      return '未通过';
    case CreatorApplyStatus.notApplied:
      return '未申请';
  }
}

class CreatorCenterPage extends ConsumerStatefulWidget {
  const CreatorCenterPage({super.key});
  @override
  ConsumerState<CreatorCenterPage> createState() => _CreatorCenterPageState();
}

class _CreatorCenterPageState extends ConsumerState<CreatorCenterPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name = _name.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final bool ok = await ref
          .read(creatorApiProvider)
          .apply(creatorName: name, bio: _bio.text.trim());
      if (!mounted) return;
      // ★ ok==false 是**后端明说没存**(data==0),不是网络错。
      //   不区分的话会报一句「提交成功」,而库里什么都没有。
      _toast(ok ? '申请已提交,等待审核' : '没有提交成功,请确认名称后重试', isError: !ok);
      if (ok) ref.invalidate(creatorCenterProvider);
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String m, {bool isError = false}) =>
      CyNativeNotice.show(context, m, isError: isError);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CreatorCenter> v = ref.watch(creatorCenterProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('创作者中心')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: v.when(
            // 加载态对齐真源(页已废弃,取自 91dd1453e^ 的
            // subpackageP3/pages/creator/index/index.wxml:11)
            // `cy-skeleton type="card" count="{{3}}"` —— 骨架,不是转圈。
            loading: () =>
                const CySkeleton(type: CySkeletonType.card, count: 3),
            error: (Object e, StackTrace _) => StatusView(
              message: '创作者中心没能加载出来',
              // ★ 承载层异常(断网/超时)的 toString 是英文原文,画在屏幕上读不懂;
              //   业务拒绝是后端 msg(中文),照原话透出。
              sub: e is DioException
                  ? '网络不稳定，请检查连接后重试'
                  : e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () => ref.invalidate(creatorCenterProvider),
            ),
            data: (CreatorCenter c) => RefreshIndicator.adaptive(
              onRefresh: () => ref.refresh(creatorCenterProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(CyTokens.space4),
                children: <Widget>[
                  _StatusCard(c),
                  if (canReallyApply(c.status))
                    _ApplyForm(
                      name: _name,
                      bio: _bio,
                      submitting: _submitting,
                      onChanged: () => setState(() {}),
                      onSubmit: _submit,
                    ),
                  _MetricCard(c.metric),
                  _IncomeCard(c.recentIncome),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(this.c);
  final CreatorCenter c;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '状态',
                style: CyType.caption1.copyWith(color: p.textTertiary),
              ),
              const Spacer(),
              Text(
                applyStatusText(c.status),
                key: const Key('creator-status'),
                style: CyType.subhead.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          if ((c.creatorName ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              c.creatorName!,
              style: CyType.headline.copyWith(color: p.textPrimary),
            ),
          ],
          if ((c.bio ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              c.bio!,
              style: CyType.caption1.copyWith(color: p.textTertiary),
            ),
          ],
          if (c.status == CreatorApplyStatus.rejected) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Text(
              // ★ 拿不到原因时说「未说明原因」,不留空 ——
              //   空着用户不知道该改什么。
              '未通过原因:${(c.rejectReason ?? '').isEmpty ? '未说明原因' : c.rejectReason}',
              key: const Key('creator-reject-reason'),
              style: CyType.caption2.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              // ⚠️ 见文件抬头:后端对已有档案一律拒收,重申请按不下去。
              //   与其给一张必然失败的表单,不如如实说。
              '目前还不能在 App 内重新提交申请,如需再次申请请联系客服。',
              key: const Key('creator-reapply-blocked'),
              style: CyType.caption2.copyWith(color: p.textTertiary),
            ),
          ],
          if (c.status == CreatorApplyStatus.pending) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              '审核中,结果出来会通知你。',
              style: CyType.caption2.copyWith(color: p.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApplyForm extends StatelessWidget {
  const _ApplyForm({
    required this.name,
    required this.bio,
    required this.submitting,
    required this.onChanged,
    required this.onSubmit,
  });
  final TextEditingController name;
  final TextEditingController bio;
  final bool submitting;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final BoxDecoration inputDecoration = BoxDecoration(
      color: p.inputBgEmpty,
      border: Border.all(color: p.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
    final TextStyle inputStyle = CyType.body.copyWith(color: p.textPrimary);
    final TextStyle placeholderStyle = CyType.body.copyWith(
      color: p.textPlaceholder,
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CySectionTitle('申请资料'),
          const SizedBox(height: CyTokens.space3),
          Text('创作者名称', style: CyType.subhead.copyWith(color: p.textPrimary)),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            controller: name,
            key: const Key('creator-name-input'),
            enabled: !submitting,
            placeholder: '请输入创作者名称',
            placeholderStyle: placeholderStyle,
            style: inputStyle,
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: inputDecoration,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autocorrect: true,
            enableSuggestions: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: CyTokens.space3),
          Text('简介', style: CyType.subhead.copyWith(color: p.textPrimary)),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            controller: bio,
            key: const Key('creator-bio-input'),
            enabled: !submitting,
            minLines: 3,
            maxLines: 3,
            placeholder: '介绍你的创作方向',
            placeholderStyle: placeholderStyle,
            style: inputStyle,
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: inputDecoration,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: true,
            enableSuggestions: true,
          ),
          const SizedBox(height: CyTokens.space3),
          CupertinoButton(
            key: const Key('creator-submit'),
            minimumSize: const Size.fromHeight(44),
            color: p.actionPrimaryBg,
            disabledColor: p.bgSubtle,
            foregroundColor: submitting || name.text.trim().isEmpty
                ? p.textPlaceholder
                : p.actionPrimaryFg,
            onPressed: submitting || name.text.trim().isEmpty ? null : onSubmit,
            child: submitting
                ? const CupertinoActivityIndicator()
                : const Text('提交申请'),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.m);
  final CreatorMetric? m;

  @override
  Widget build(BuildContext context) {
    // ★ 缺值一律「—」不兜 0:「今天还没统计」和「一次都没被看过」不是一回事。
    String v(int? n) => n?.toString() ?? '—';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CySectionTitle('数据概览'),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              _Metric(label: '内容', value: v(m?.contentCount)),
              _Metric(label: '浏览', value: v(m?.viewCount)),
              _Metric(label: '点赞', value: v(m?.likeCount)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            key: Key('creator-metric-$label'),
            style: CyType.title3.copyWith(
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: CyType.caption2.copyWith(color: p.textTertiary)),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard(this.rows);
  final List<CreatorIncomeRow> rows;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ★ 「查看全部」是真源就有的入口(index.wxml:41 `goIncomeAll` →
          //   income-detail),此前 App 漏了这一条,收益明细从这页走不到。
          CySectionTitle(
            '近期收益',
            trailing: CupertinoButton(
              key: const Key('creator-income-all'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
              onPressed: () => context.push('/income'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '查看全部',
                    style: CyType.subhead.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(width: CyTokens.space1),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 14,
                    color: p.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          if (rows.isEmpty)
            Text(
              '暂无收益明细',
              key: const Key('creator-income-empty'),
              style: CyType.caption2.copyWith(color: p.textTertiary),
            )
          else
            for (final CreatorIncomeRow r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        r.source ?? '收益',
                        style: CyType.body.copyWith(color: p.textPrimary),
                      ),
                    ),
                    Text(
                      // ★ 金额原样透出,不做二次格式化(与商家结算同一条纪律)。
                      //   拿不到给「—」,不给 ¥0.00。
                      r.amount ?? '—',
                      style: CyType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
