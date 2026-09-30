import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/infomation.dart';

final infomationsProvider = FutureProvider.autoDispose<List<Infomation>>((ref) {
  return ref.watch(topicApiProvider).infomations();
});

/// 城瘾玩法。对齐小程序 `subpackageA/pages/infomation`。
///
/// ★ 这一页替换掉设置页里那个「玩法说明即将上线」的假按钮。
class PlayGuidePage extends ConsumerWidget {
  const PlayGuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(infomationsProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('城瘾玩法')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.pageX),
            children: <Widget>[
              Text('三种玩法,即开即玩', style: CyType.title2),
              const SizedBox(height: CyTokens.space1),
              Text(
                '不用先学规则。挑一种出发方式,城市自己会讲下去。',
                style: CyType.body.copyWith(color: CyTokens.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              // ★ 每种玩法都给**真实落点**,不是只讲不给去处。
              //   路由由 test/router_targets_exist_test.dart 保证存在。
              ...kPlayModes.map((PlayMode m) => _ModeCard(mode: m)),
              const SizedBox(height: CyTokens.space4),
              const CySectionTitle('了解更多'),
              const SizedBox(height: CyTokens.space2),
              // 三态对齐真源 subpackageA/pages/infomation/infomation.wxml:68-80
              // (加载 = `cy-skeleton type="list" count="2"` / 失败给重试 /
              // 空态说「内容上线后会出现在这里」)——
              // 旧写法是整块不渲染:接口失败时这一块**静默消失**,用户以为
              // 本来就没有玩法说明,连重试的入口都没有。
              async.when(
                loading: () =>
                    const CySkeleton(type: CySkeletonType.list, count: 2),
                error: (Object e, _) => StatusView(
                  message: '玩法文档没能加载出来',
                  sub: e.toString().replaceFirst('Exception: ', ''),
                  large: true,
                  onRetry: () => ref.invalidate(infomationsProvider),
                ),
                data: (List<Infomation> rows) => rows.isEmpty
                    ? const StatusView(
                        message: '暂无玩法说明',
                        sub: '内容上线后会出现在这里',
                        large: true,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 列表侧已过滤掉不可读的条目(usable),
                          // 所以这里每一条都点得进去。
                          ...rows.map(
                            (Infomation x) => CyCell(
                              title: x.title,
                              // 与标题逐字相同的副标不渲染。
                              subtitle: x.summary,
                              onTap: () => context.push('/infomation/${x.id}'),
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode});
  final PlayMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(mode.name, style: CyType.headline)),
              CyTag(label: mode.tag),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            mode.desc,
            style: CyType.footnote.copyWith(color: CyTokens.textSecondary),
          ),
          const SizedBox(height: CyTokens.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: CyNativeButton(
              role: CyNativeButtonRole.secondary,
              label: '去${mode.name}',
              // 源是 switchTab(App 语义 = go 到 tab),不是压栈。
              onPressed: () => context.go(mode.route),
            ),
          ),
        ],
      ),
    );
  }
}
