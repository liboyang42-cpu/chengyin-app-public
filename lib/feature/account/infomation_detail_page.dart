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
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          // 缺 id(链接被截断)不拉接口:重试永远不会有结果,只给「返回玩法列表」
          // —— 真源 `infomationdetail` 的 missing 态同样是零假重试。
          child: id <= 0
              ? StatusView(
                  message: '这篇玩法说明打不开',
                  sub: '链接里没有玩法编号，请从玩法列表重新进入',
                  large: true,
                  onRetry: () => context.go('/play-guide'),
                  retryLabel: '返回玩法列表',
                )
              : ref
                    .watch(infomationDetailProvider(id))
                    .when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (Object e, _) => StatusView(
                        message: '打不开这篇',
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
                            message: '这篇玩法说明不在了',
                            sub: '它可能已被下架。去玩法列表看看其它的。',
                            large: true,
                            onRetry: () => context.go('/play-guide'),
                            retryLabel: '返回玩法列表',
                          );
                        }
                        // ★ 后端详情接口**不做可读性过滤**(那是列表侧 usable 的事),
                        //   所以这里可能真的拿到空正文 —— 说清楚,不显示一片空白。
                        if (body.isEmpty) {
                          return StatusView(
                            message: x.title.trim().isEmpty
                                ? '这篇还没有内容'
                                : x.title,
                            sub: '正文还没写好,过一阵再来',
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
