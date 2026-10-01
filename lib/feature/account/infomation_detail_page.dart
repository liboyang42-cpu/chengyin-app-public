import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/infomation.dart';

final infomationDetailProvider = FutureProvider.autoDispose
    .family<Infomation, int>((ref, int id) {
      return ref.watch(topicApiProvider).infomationDetail(id);
    });

/// 资讯详情。对齐小程序 `subpackageA/pages/infomationdetail`。
class InfomationDetailPage extends ConsumerWidget {
  const InfomationDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          // 缺 id(链接被截断)不拉接口:重试永远不会有结果,只给「返回玩法列表」
          // —— 真源 `infomationdetail` 的 missing 态同样是零假重试。
          child: id <= 0
              ? StatusView(
                  message: stringsOf(context).accountGuideMissing,
                  sub: stringsOf(context).accountGuideMissingHint,
                  large: true,
                  onRetry: () => context.go('/play-guide'),
                  retryLabel: stringsOf(context).accountGuideReturn,
                )
              : ref
                    .watch(infomationDetailProvider(id))
                    .when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (Object e, _) => StatusView(
                        message: stringsOf(context).accountGuideDetailError,
                        sub: e.toString().replaceFirst('Exception: ', ''),
                        large: true,
                        onRetry: () =>
                            ref.invalidate(infomationDetailProvider(id)),
                      ),
                      data: (Infomation x) {
                        final body = (x.contents ?? '').trim();
                        // ★ 有 id、接口也 200,但实体没有 id = 这条**已被后台删除**
                        //   (真源 notfound 态,2026-08-19 清生产脏数据时暴露的那一态)。
                        //   它既不是加载失败(重试没用)也不是正文没写(那才退到下面那支),
                        //   所以出口是「去玩法列表看看其它的」。
                        if (x.id <= 0) {
                          return StatusView(
                            message: stringsOf(context).accountGuideRemoved,
                            sub: stringsOf(context).accountGuideRemovedHint,
                            large: true,
                            onRetry: () => context.go('/play-guide'),
                            retryLabel: stringsOf(context).accountGuideReturn,
                          );
                        }
                        // ★ 后端详情接口**不做可读性过滤**(那是列表侧 usable 的事),
                        //   所以这里可能真的拿到空正文 —— 说清楚,不显示一片空白。
                        if (body.isEmpty) {
                          return StatusView(
                            message: x.title.trim().isEmpty
                                ? stringsOf(context).accountGuideNoContent
                                : x.title,
                            sub: stringsOf(context).accountGuideNoContentHint,
                            large: true,
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.all(CyTokens.pageX),
                          children: <Widget>[
                            Text(x.title, style: textTheme.headlineSmall),
                            // 与标题逐字相同的副标不渲染(同列表侧规则)。
                            if (x.summary != null) ...<Widget>[
                              const SizedBox(height: CyTokens.space1),
                              Text(
                                x.summary!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: CyTokens.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: CyTokens.space4),
                            Text(
                              body,
                              style: textTheme.bodyMedium?.copyWith(
                                height: 1.8,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
