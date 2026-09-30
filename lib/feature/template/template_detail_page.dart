import 'package:flutter/cupertino.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/template_api.dart';
import '../auth/login_gate.dart';
import '../../data/models/template.dart';
import '../../data/models/template_draft.dart';
import '../../core/widgets/cy_native_button.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/cy_net_image.dart';

final templateDetailProvider = FutureProvider.autoDispose
    .family<PlayTemplate, int>((ref, int id) {
      return ref.watch(templateApiProvider).info(id);
    });

/// 玩法详情。对齐小程序 `pages/templatedetail`。
class TemplateDetailPage extends ConsumerWidget {
  const TemplateDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(templateDetailProvider(id));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('玩法详情')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            // 真源 loading 即 <cy-skeleton type="detail">,与其余详情域同件。
            loading: () => const CySkeleton(type: CySkeletonType.detail),
            error: (Object e, _) {
              // ★ 后端有四种拒绝理由,对用户意味着完全不同的事:
              //   审核中会回来(值得重试)、已删除/已下架不会回来(给重试是骗人)。
              if (e is TemplateUnavailableException) {
                return StatusView(
                  message: e.reason.title,
                  sub: e.reason.hint,
                  large: true,
                  onRetry: e.reason.retryable
                      ? () => ref.invalidate(templateDetailProvider(id))
                      : null,
                );
              }
              return StatusView(
                message: '玩法详情没能加载出来',
                sub: e.toString().replaceFirst('Exception: ', ''),
                large: true,
                onRetry: () => ref.invalidate(templateDetailProvider(id)),
              );
            },
            data: (PlayTemplate t) => ListView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              children: <Widget>[
                if ((t.imgUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                    child: CyNetImage(
                      t.imgUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: CyTokens.space3),
                Text(
                  t.title,
                  // 真源 hero 标题 = --cy-font-display(40rpx=20pt, tokens.wxss:800)
                  // + w700 → 梯级 Title3 20;首轮误按 56rpx 放大到 Title1,回退。
                  style: CyType.title3.copyWith(fontWeight: FontWeight.w700),
                ),
                if (t.metaLine.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    t.metaLine,
                    // 真源 xb-head-sub = --cy-font-body(14)→ Subhead 15。
                    style: CyType.subhead.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ],
                // ★ 顺序与小程序 templatedetail 一致:简介 → 规则 → 物料 →
                //   在哪用 → 怎么验证 → 创作者说。
                //   此前 App 只有三块(说明/场地/物料),而后端一直在下发
                //   ruleInstructions / storyText / validationMethod ——
                //   模型没解析,所以详情页比小程序薄一半。
                _section(context, '简介', t.description),
                _section(context, '规则说明', t.ruleInstructions),
                _section(context, '需要准备', t.requiredMaterials),
                _section(context, '在哪用', t.usageLocation),
                _section(context, '怎么验证', t.validationText),
                // 「创作者说」带图。★ storyText 拿不到时退到 publisher,
                //   两个都没有则整块不渲染(见 PlayTemplate.creatorNote)。
                if (t.creatorNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const CySectionTitle('创作者说'),
                        const SizedBox(height: CyTokens.space2),
                        if ((t.storyImg ?? '').trim().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusMd,
                            ),
                            child: CyNetImage(
                              t.storyImg,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        if ((t.storyImg ?? '').trim().isNotEmpty)
                          const SizedBox(height: CyTokens.space2),
                        Text(
                          t.creatorNote!,
                          key: const Key('template-creator-note'),
                          style: CyType.subhead,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: CyTokens.space5),
                // 「套用」—— 把这个库模板的内容作为初值开一个我自己的玩法草稿。
                //
                // ★★ 这是模板市场此前**完全缺失**的一环:能浏览、能看详情,
                //   但没有任何入口把一个模板变成自己的。库里的东西看得见拿不走,
                //   那模板市场就只是一本画册。
                //
                // ★ 走的是既有的「引用模板」链路(originalTemplateId + saveDraft/publish),
                //   不新造后端接口 —— 那条链路连采用数自增都已经接好了。
                CyNativeButton(
                  key: const Key('template-adopt'),
                  onPressed: () => _adopt(context, ref, t),
                  label: '套用这个玩法',
                ),
                const SizedBox(height: CyTokens.space6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 套用:带着来源模板的内容开一个我自己的草稿。
  ///
  /// ★ `originalTemplateId` 是要害 —— 见 TemplateEditPage.seed 的注释。
  ///
  /// ★★ #379 真点 P1:「套用」是**动作**不是浏览,而 `/template/edit` 在整页
  ///   需登录表里。游客直接 push 会撞 router 的兜底 redirect —— 它把 shell 根
  ///   `/feed` 当 imperative push 再压一层,轻则 tab 选中态与内容永久脱钩,
  ///   重则同层 Navigator 出现两个同 key 页面、debug 直接
  ///   `!keyReservation.contains(key)` 断言红屏(必现 2/2)。
  ///   所以和创建/加入等动作入口同口径:先 requireLogin,登完回到本页继续。
  void _adopt(BuildContext context, WidgetRef ref, PlayTemplate t) async {
    if (!await requireLogin(context, ref) || !context.mounted) return;
    context.push(
      '/template/edit',
      extra: TemplateDraft(
        originalTemplateId: t.id,
        title: t.title,
        description: (t.description ?? '').trim(),
        imgUrl: t.imgUrl,
        players: t.players,
        duration: t.duration,
        difficulty: t.difficulty,
        usageLocation: t.usageLocation,
        requiredMaterials: t.requiredMaterials,
        ruleInstructions: t.ruleInstructions,
        categoryId: t.categoryId,
        // ⚠️ **不带答案类字段**:列表与详情接口本来就不下发 questionAnswer /
        //   correctAnswer(公开投影刻意剥掉了)。这里若从别处凑一份出来,
        //   等于把玩法答案发给了所有人。套用者要自己出题。
      ),
    );
  }

  /// 内容为空的小节**整块不渲染** —— 留一个只有标题的空分区
  /// 会让人以为是没加载出来。
  Widget _section(BuildContext context, String title, String? body) {
    if ((body ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CySectionTitle(title),
          const SizedBox(height: CyTokens.space2),
          Text(body!.trim(), style: CyType.subhead),
        ],
      ),
    );
  }
}
