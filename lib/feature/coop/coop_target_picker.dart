// 邀约对象选择器 —— 对应小程序 pages/coop/invite 里那段 targets 加载。
//
// App 的邀约页此前**没有「选谁」这一步**:必须从「附近商家」或「伙伴」
// 带着对象跳进来,页面上只写了一句提示。于是 /api/club/merchants 与
// /api/merchant/clubs 两条目录接口都零调用方。
//
// ★★ 两个类型走**两个不同的接口**,而且 id 是两套空间:
//   商家 → /api/club/merchants(后端强制 coopOpen=1 + status=1)
//   俱乐部 → /api/merchant/clubs(后端强制 status=1)
//   ⇒ 换类型必须清空已选(页面里已经这么做了),这里也各查各的,不共用缓存。
//
// ⚠️ 两条都是 @RequestBody 端点,必须发 JSON —— 缺 header 会被当 urlencoded,
//   后端 415,表现是「列表一直加载不出来」。这一点两个 api 方法里都处理好了。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_invite.dart';

/// 候选目录。★ 按类型分 family —— 商家和俱乐部各自缓存,别互相覆盖。
final coopTargetsProvider = FutureProvider.autoDispose
    .family<List<CoopInviteTarget>, CoopInviteType>((
      Ref ref,
      CoopInviteType t,
    ) async {
      final List<Map<String, dynamic>> rows = t == CoopInviteType.merchant
          ? await ref.watch(clubApiProvider).coopMerchants()
          : await ref.watch(merchantApiProvider).clubsForInvite();
      return rows
          .map(coopTargetFromRow)
          .where((CoopInviteTarget? x) => x != null)
          .cast<CoopInviteTarget>()
          .toList();
    });

/// 把后端行折成候选。
///
/// ★ id 拿不到就**整条丢掉**,不兜 0 —— 一个 toId=0 的候选提交必被后端拒,
///   而界面上它看着和别的一样,用户不知道为什么只有这条失败。
CoopInviteTarget? coopTargetFromRow(Map<String, dynamic> r) {
  final Object? raw = r['id'] ?? r['merchantId'] ?? r['clubId'];
  final int id = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}') ?? 0;

  if (id <= 0) return null;
  final String name =
      ((r['name'] ?? r['merchantName'] ?? r['clubName'] ?? '') as Object)
          .toString()
          .trim();
  return CoopInviteTarget(
    toId: id,
    // 名字拿不到时用 id 兜 —— 显示一个空条目比显示「#123」更难认。
    name: name.isEmpty ? '#$id' : name,
  );
}

/// 打开选择器,返回**新增**的候选(已选的由调用方合并)。
Future<List<CoopInviteTarget>?> pickCoopTargets(
  BuildContext context, {
  required CoopInviteType type,
  required List<CoopInviteTarget> already,
}) => showCupertinoSheet<List<CoopInviteTarget>>(
  context: context,
  showDragHandle: true,
  topGap: 0.18,
  scrollableBuilder:
      (BuildContext context, ScrollController scrollController) => _Picker(
        type: type,
        already: already,
        scrollController: scrollController,
      ),
);

class _Picker extends ConsumerStatefulWidget {
  const _Picker({
    required this.type,
    required this.already,
    required this.scrollController,
  });
  final CoopInviteType type;
  final List<CoopInviteTarget> already;
  final ScrollController scrollController;
  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  final Set<int> _picked = <int>{};

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final AsyncValue<List<CoopInviteTarget>> v = ref.watch(
      coopTargetsProvider(widget.type),
    );
    final Set<int> chosen = widget.already
        .map((CoopInviteTarget t) => t.toId)
        .toSet();
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          '选择要邀请的${widget.type == CoopInviteType.merchant ? '商家' : '俱乐部'}',
        ),
        leading: CupertinoButton(
          key: const Key('coop-target-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        trailing: CupertinoButton(
          key: const Key('coop-target-done'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () {
            final List<CoopInviteTarget> all =
                v.value ?? const <CoopInviteTarget>[];
            Navigator.of(context).pop(
              all
                  .where((CoopInviteTarget t) => _picked.contains(t.toId))
                  .toList(),
            );
          },
          child: Text('确定(${_picked.length})'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: v.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (Object e, StackTrace _) => StatusView(
            message: '候选名单没加载出来',
            sub: '网络可能不稳定,稍后再试',
            large: true,
            onRetry: () => ref.invalidate(coopTargetsProvider(widget.type)),
          ),
          data: (List<CoopInviteTarget> rows) => rows.isEmpty
              ? StatusView(
                  message: widget.type == CoopInviteType.merchant
                      ? '暂时没有可对接的商家'
                      : '暂时没有可邀请的俱乐部',
                  // ★ 说清判据 —— 否则用户以为是自己搜错了。
                  sub: widget.type == CoopInviteType.merchant
                      ? '只有开放合作、且已通过审核的商家会出现在这里'
                      : '只有已开放的俱乐部会出现在这里',
                  large: true,
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    vertical: CyTokens.space2,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (BuildContext c, int i) {
                    final CoopInviteTarget t = rows[i];
                    // 已经选过的置灰并说明,不是悄悄不给勾。
                    final bool dup = chosen.contains(t.toId);
                    final bool selected = dup || _picked.contains(t.toId);
                    return Semantics(
                      selected: selected,
                      enabled: !dup,
                      button: true,
                      label: t.name,
                      value: dup ? '已在本次邀约里' : (selected ? '已选择' : '未选择'),
                      child: CupertinoButton(
                        key: Key('coop-target-${t.toId}'),
                        minimumSize: const Size.fromHeight(52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.pageX,
                          vertical: CyTokens.space2,
                        ),
                        alignment: Alignment.centerLeft,
                        foregroundColor: dup ? p.textTertiary : p.textPrimary,
                        onPressed: dup
                            ? null
                            : () => setState(
                                () => selected
                                    ? _picked.remove(t.toId)
                                    : _picked.add(t.toId),
                              ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(t.name),
                                  if (dup)
                                    Text(
                                      '已在本次邀约里',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: p.textTertiary),
                                    ),
                                ],
                              ),
                            ),
                            ExcludeSemantics(
                              child: CupertinoCheckbox(
                                value: selected,
                                onChanged: dup
                                    ? null
                                    : (bool? value) => setState(
                                        () => value == true
                                            ? _picked.add(t.toId)
                                            : _picked.remove(t.toId),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
