import '../../l10n/strings.dart';
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
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).accountGuideTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.pageX),
            children: <Widget>[
              Text(stringsOf(context).accountGuideIntro, style: CyType.title2),
              const SizedBox(height: CyTokens.space1),
              Text(
                stringsOf(context).accountGuideHint,
                style: CyType.body.copyWith(color: CyTokens.textSecondary),
              ),
              const SizedBox(height: CyTokens.space4),
              // ★ 每种玩法都给**真实落点**,不是只讲不给去处。
              //   路由由 test/router_targets_exist_test.dart 保证存在。
              ...kPlayModes.map((PlayMode m) => _ModeCard(mode: m)),
              const SizedBox(height: CyTokens.space4),
              CySectionTitle(stringsOf(context).accountGuideMore),
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
                  message: stringsOf(context).accountGuideError,
                  sub: e.toString().replaceFirst('Exception: ', ''),
                  large: true,
                  onRetry: () => ref.invalidate(infomationsProvider),
                ),
                data: (List<Infomation> rows) => rows.isEmpty
                    ? StatusView(
                        message: stringsOf(context).accountGuideEmpty,
                        sub: stringsOf(context).accountGuideEmptyHint,
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
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space1,
            children: <Widget>[
              Text(_modeCopy(context, mode).name, style: CyType.headline),
              CyTag(label: _modeCopy(context, mode).tag),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            _modeCopy(context, mode).desc,
            style: CyType.footnote.copyWith(color: CyTokens.textSecondary),
          ),
          const SizedBox(height: CyTokens.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: CyNativeButton(
              role: CyNativeButtonRole.secondary,
              label: stringsOf(context).accountGuideGo(_modeCopy(context, mode).name),
              // 源是 switchTab(App 语义 = go 到 tab),不是压栈。
              onPressed: () => context.go(mode.route),
            ),
          ),
        ],
      ),
    );
  }
}

({String name, String tag, String desc}) _modeCopy(BuildContext context, PlayMode mode) {
  final s = stringsOf(context);
  return switch (mode.key) {
    'classic' => (name: s.accountGuideClassicName, tag: s.accountGuideClassicTag, desc: s.accountGuideClassicDesc),
    'free' => (name: s.accountGuideFreeName, tag: s.accountGuideFreeTag, desc: s.accountGuideFreeDesc),
    'roam' => (name: s.accountGuideRoamName, tag: s.accountGuideRoamTag, desc: s.accountGuideRoamDesc),
    _ => (name: mode.name, tag: mode.tag, desc: mode.desc),
  };
}
