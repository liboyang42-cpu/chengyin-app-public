import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';

/// 可邀请的合作者(`/api/user/list`)。
///
/// ★★ App 此前**完全没有这块**:专业版编辑器把 collaboratorIds 恒设成
///   `[我自己]`,没有任何添加别人的入口 —— 合作者这个功能在 App 里等于不存在。
///
/// ⚠️ 小程序那个选择器里的搜索框**只存值、没接过滤逻辑**(它自己的注释:
///   「既有选择器这里只存值、没有真正接入过滤逻辑,原样保留」)。
///   这边不照抄那个假搜索框 —— 点了没反应的控件比没有更坏,
///   而 `publicMemberList` 本来就支持 keyword,直接接真的。
class CollaboratorCandidate {
  const CollaboratorCandidate({
    required this.id,
    required this.name,
    required this.avatar,
    required this.followText,
  });

  final int id;
  final String name;
  final String avatar;

  /// 关注数文本。★ null / 空串 → 「—」,**不是 0**:
  ///   拿不到这个数和"这个人没有粉丝"是两回事(判据同小程序 followText)。
  final String followText;

  factory CollaboratorCandidate.fromJson(Map<String, dynamic> json) {
    final Object? follow = json['followNum'];
    final String n = (json['nickname'] ?? '').toString().trim();
    return CollaboratorCandidate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: n.isEmpty ? '未命名用户' : n,
      avatar: (json['avatar'] ?? '').toString(),
      followText: (follow == null || follow.toString().isEmpty)
          ? '—'
          : follow.toString(),
    );
  }
}

final collaboratorCandidatesProvider = FutureProvider.autoDispose
    .family<List<CollaboratorCandidate>, String>((
      Ref ref,
      String keyword,
    ) async {
      final rows = await ref
          .watch(registrationApiProvider)
          .publicMemberList(keyword: keyword.isEmpty ? null : keyword);
      return rows.map(CollaboratorCandidate.fromJson).toList();
    });

/// 选一个合作者。选中即回传即关闭 —— 不需要「确定」按钮:
/// 这不是表单,点遮罩关掉不丢任何用户输入(语义同小程序那个选择器)。
Future<CollaboratorCandidate?> showCollaboratorPicker(
  BuildContext context, {
  required List<int> alreadyPicked,
}) {
  return showCupertinoSheet<CollaboratorCandidate>(
    context: context,
    showDragHandle: true,
    topGap: 0.25,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _PickerSheet(
              alreadyPicked: alreadyPicked,
              scrollController: scrollController,
            ),
  );
}

class _PickerSheet extends ConsumerStatefulWidget {
  const _PickerSheet({
    required this.alreadyPicked,
    required this.scrollController,
  });
  final List<int> alreadyPicked;
  final ScrollController scrollController;

  @override
  ConsumerState<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends ConsumerState<_PickerSheet> {
  /// 真正拿去请求的关键词。
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final async = ref.watch(collaboratorCandidatesProvider(_keyword));
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('选择合作者'),
        leading: CupertinoButton(
          key: const Key('collaborator-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.space4,
                CyTokens.space3,
                CyTokens.space4,
                0,
              ),
              // Apple 的搜索框自带放大镜、清除钮和系统搜索键盘。
              child: CupertinoSearchTextField(
                key: const Key('collaborator-search'),
                placeholder: '搜索',
                itemColor: palette.textTertiary,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
                onChanged: (String v) => setState(() {
                  // 清空即回到全量列表:否则清掉字还停在上次的搜索结果上。
                  if (v.trim().isEmpty) _keyword = '';
                }),
                // 真的去搜,不是摆设。
                onSubmitted: (String v) => setState(() => _keyword = v.trim()),
              ),
            ),
            if (async.isLoading && _keyword.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: CyTokens.space1),
                child: CupertinoActivityIndicator(radius: 7),
              ),
            const SizedBox(height: CyTokens.space3),
            Expanded(
              child: async.when(
                loading: () =>
                    const CySkeleton(type: CySkeletonType.list, count: 4),
                error: (Object e, _) => StatusView(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  message: '合作者列表没能加载出来',
                  sub: '请检查网络后点「重试」再试一次',
                  onRetry: () =>
                      ref.invalidate(collaboratorCandidatesProvider(_keyword)),
                ),
                data: (List<CollaboratorCandidate> list) => list.isEmpty
                    ? StatusView(
                        icon: Icons.person_search_outlined,
                        // 空态要分清「搜不到」和「一个人都没有」。
                        message: _keyword.isEmpty
                            ? '还没有可邀请的合作者'
                            : '没有匹配「$_keyword」的用户',
                        sub: _keyword.isEmpty
                            ? '等有创作者注册后会出现在这里；也可以先返回，稍后再来添加合作者。'
                            : '换个昵称试试',
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.space4,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, int i) => _Row(
                          candidate: list[i],
                          // 已选过 / 拿不到 id 都不给邀请 —— 点了也没意义。
                          picked: widget.alreadyPicked.contains(list[i].id),
                          onPick: () => Navigator.of(context).pop(list[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.candidate,
    required this.picked,
    required this.onPick,
  });

  final CollaboratorCandidate candidate;
  final bool picked;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bool invitable = !picked && candidate.id > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        children: <Widget>[
          CyAvatar(url: candidate.avatar, fallback: candidate.name, size: 36),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(candidate.name, style: textTheme.titleSmall),
                Text(
                  '关注：${candidate.followText}',
                  style: textTheme.labelSmall?.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton.tinted(
            key: Key('invite-${candidate.id}'),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onPressed: invitable ? onPick : null,
            child: Text(
              // 三态各说各的:能邀 / 已邀过 / 数据不全没法邀。
              picked ? '已邀请' : (candidate.id > 0 ? '邀请' : '无法邀请'),
            ),
          ),
        ],
      ),
    );
  }
}
