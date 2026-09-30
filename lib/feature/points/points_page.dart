import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'points_tasks_sheet.dart';

import '../../core/widgets/cy_tabs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/status_view.dart';
import 'points_hero.dart';
import '../../data/models/points_record.dart';
import 'points_controller.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

/// 积分明细页:顶部 hero(我的积分 / 本周获得)+ 全部/收入/支出 tab + 真实分页流水。
///
/// ★ 原来这里另有一张「可用积分」卡,和 hero 左栏是同一个数 ——
///   实拍发现 1380 显示了两遍。hero 就是小程序那张卡(一卡两栏),
///   把余额并进去,那张单独的卡随之删掉。
class PointsPage extends ConsumerStatefulWidget {
  const PointsPage({super.key});

  @override
  ConsumerState<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends ConsumerState<PointsPage> {
  /// 0 全部 / 1 收入 / 2 支出(对应后端 changeType 1/2)。
  int _tab = 0;

  List<PointsRecord> _applyFilter(List<PointsRecord> list) {
    switch (_tab) {
      case 1:
        return list.where((PointsRecord r) => r.isIncome).toList();
      case 2:
        return list.where((PointsRecord r) => r.changeType == 2).toList();
      default:
        return list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsProvider);
    final notifier = ref.read(pointsProvider.notifier);
    final CyPalette p = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: SafeArea(
        bottom: false,
        child: Column(
          // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
          // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const CyPageTitle('积分明细'),
            // 我的积分 / 本周获得 —— 对应小程序积分弹窗顶部那两栏。
            PointsHero(balance: notifier.balance),
            // ★ 空态那句「参与活动或完成任务后…」原来是句**没有出口的话**:
            //   用户看不到有哪些任务、各给多少分。这个入口就是那份真源。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  key: const Key('points-how-to-earn'),
                  onPressed: () => showPointsTasksSheet(context),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  // 小程序 .pc-gs-link:纯文字 12pt / text-tertiary 灰字链接,
                  // 不带图标(源里没有 ⓘ,加了就是源外装饰)。
                  // 也不是蓝色强调(强调色只留给状态与主操作,C1/D5)。
                  child: Text(
                    '如何获取积分',
                    style: CyType.caption1.copyWith(color: p.textTertiary),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: () => ref.refresh(pointsProvider.future),
                child: points.when(
                  loading: () =>
                      const CySkeleton(type: CySkeletonType.list, count: 4),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '积分明细拉取失败',
                    sub: '请检查网络或稍后再试。',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    scrollable: true,
                    onRetry: () => ref.invalidate(pointsProvider),
                  ),
                  data: (List<PointsRecord> all) {
                    final filtered = _applyFilter(all);
                    return NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification n) {
                        if (n.metrics.pixels >=
                                n.metrics.maxScrollExtent - 240 &&
                            notifier.hasMore &&
                            !notifier.loadMoreFailed) {
                          notifier.loadMore();
                        }
                        return false;
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(CyTokens.space4),
                        children: <Widget>[
                          // 原来这里还垫一个 space4,和 ListView 自己的上内边距
                          // 叠成双份留白 —— 删减优先,一份就够。
                          _TabBar(
                            current: _tab,
                            onChanged: (int t) => setState(() => _tab = t),
                          ),
                          const SizedBox(height: CyTokens.space3),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: CyTokens.space7),
                              child: StatusView(
                                message: '暂无积分记录',
                                sub: '参与活动或完成任务后，积分流水会显示在这里。',
                                icon: CupertinoIcons.tray,
                              ),
                            )
                          else
                            ...filtered.map(
                              (PointsRecord r) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: CyTokens.space3,
                                ),
                                child: _RecordTile(record: r),
                              ),
                            ),
                          // 空态下面不再顶一句「没有更多了」—— 空态已经说完了
                          // 「这里什么都没有」,尾注是跟列表尽头说话,不是跟空话。
                          // 只有还有下一页可拉时 spinner 才继续有意义。
                          if (filtered.isNotEmpty || notifier.hasMore)
                            _Footer(
                              hasMore: notifier.hasMore,
                              failed: notifier.loadMoreFailed,
                              onRetry: notifier.loadMore,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onChanged});
  final int current;
  final ValueChanged<int> onChanged;

  static const List<String> _labels = <String>['全部', '收入', '支出'];

  @override
  Widget build(BuildContext context) {
    // 原来是 Row + CyChip 自绘 —— 与台账/活动列表的分段栏各长各的。
    // 收编进 CyTabs 后三处同源(间距、丸高、选中色都从一处来)。
    return CyTabs(
      variant: CyTabsVariant.chip,
      tabs: <CyTab>[
        for (int i = 0; i < _labels.length; i++)
          CyTab(key: '$i', label: _labels[i]),
      ],
      active: '$current',
      onChanged: (String k) => onChanged(int.parse(k)),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});
  final PointsRecord record;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool income = record.isIncome;
    final String sign = income ? '+' : '-';
    // Material Card 自带投影与 Material 主题底色 —— 换成与 hero 同一套实色内容卡
    // (小程序同一行也是卡:bg + radius + padding)。
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CyType.body.copyWith(color: p.textPrimary),
                ),
                if (record.createTime != null &&
                    record.createTime!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    record.createTime!,
                    style: CyType.caption1.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          // 黑白系:金额不上色(收入/支出靠 +/− 号表达),对齐资产页已对齐写法。
          // 档位是**列表档**:真源 components/cy/profile/index.wxss:811
          // `.pts-row__gain` = card-title(16)/700 —— display(28)会把每行的数字
          // 顶到跟 hero 余额一样响,一屏里全是重点。
          Text(
            '$sign${record.displayPoints}',
            style: CyType.callout.copyWith(
              height: 1.15,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.hasMore, this.failed = false, this.onRetry});
  final bool hasMore;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final Widget child;
    if (failed) {
      child = CupertinoButton(
        onPressed: onRetry,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(CupertinoIcons.refresh, size: 18),
            SizedBox(width: CyTokens.space1),
            Text('加载失败,点我重试'),
          ],
        ),
      );
    } else if (hasMore) {
      child = const SizedBox(
        height: 20,
        width: 20,
        child: CupertinoActivityIndicator(radius: 10),
      );
    } else {
      child = Text(
        '没有更多了',
        style: CyType.caption1.copyWith(color: p.textTertiary),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
      child: Center(child: child),
    );
  }
}
