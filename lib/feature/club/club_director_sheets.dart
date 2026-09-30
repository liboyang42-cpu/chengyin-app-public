import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import '../../data/models/club_director.dart';
import 'club_director_controller.dart';
import 'club_ops_sections.dart';

/// 导演台 D1–D8 的半屏与行列表(活动详情页宿主的那套)。
/// 逐条对齐小程序 `pages/club/components/club-director-*` 十个组件
/// (行列表 / chips / 弹层结构)与 `pages/club/topic-detail/director.js` 的
/// 状态机闸与文案。写入一律走 [clubDirectorProvider],这里只有草稿与展示。
///
/// ★ 真源的两处行形状缺口(站点/队伍/广播喂给 row-list 的对象没有 `title`,
///   小程序那几张卡其实渲不出标题)—— App 侧把行投影补全
///   ([clubDirectorStationRows] 等),语义与 row-list 的契约 `{id,title,subtitle?,value?,valueTone?}` 一致。

/// 写完之后统一收口:toast(小程序原话)→ 收起半屏。
/// 半屏留在提交中是刻意的 —— `writeLocked` 会让确认键禁用,防双击。
Future<void> clubDirectorSettleWrite(
  BuildContext context,
  WidgetRef ref,
  int activityId,
  Future<ClubDirectorWriteResult> write,
) async {
  final ClubDirectorWriteResult result = await write;
  if (!context.mounted) return;
  clubDirectorNotifyWriteResult(
    context,
    result,
    ref.read(clubDirectorProvider(activityId)),
  );
  Navigator.of(context).pop();
}

// ─── 行模型与投影 ───

typedef ClubDirectorRowDetail = ({String label, String text});

class ClubDirectorRow {
  const ClubDirectorRow({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.value = '',
    this.valueTone = 'default',
    this.details = const <ClubDirectorRowDetail>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String value;

  /// default | success | warning | danger | muted
  final String valueTone;
  final List<ClubDirectorRowDetail> details;
}

/// D1 站点行(标题=站名,副标题=异常,值=状态)。
List<ClubDirectorRow> clubDirectorStationRows(
  List<ClubDirectorStation> stations,
) {
  return <ClubDirectorRow>[
    for (final ClubDirectorStation s in stations)
      ClubDirectorRow(
        id: s.nodeId?.toString() ?? s.nameText,
        title: s.nameText,
        subtitle: s.issueText,
        value: s.statusText,
        valueTone: s.priority == 3 ? 'default' : 'warning',
      ),
  ];
}

/// 小程序 `refreshTeamRows`:异常队伍的「卡点节点 / 提示层级 / 最近有效事件」
/// 摊成 details 三行;缺值写「待确认」,不写 0 也不留空。
List<ClubDirectorRow> clubDirectorTeamRows(List<ClubDirectorTeam> teams) {
  const String pending = '待确认';
  return <ClubDirectorRow>[
    for (final ClubDirectorTeam t in teams)
      ClubDirectorRow(
        id: t.teamId?.toString() ?? t.nameText,
        title: t.nameText,
        subtitle: t.issueText.isEmpty ? t.progressText : t.issueText,
        value: t.statusText,
        valueTone: t.isAbnormal ? 'warning' : 'default',
        details: t.isAbnormal
            ? <ClubDirectorRowDetail>[
                (
                  label: '卡点节点',
                  text: t.stuckNodeText.isEmpty ? pending : t.stuckNodeText,
                ),
                (
                  label: '提示层级',
                  text: t.hintLevelText.isEmpty ? pending : t.hintLevelText,
                ),
                (
                  label: '最近有效事件',
                  text: t.recentEventText.isEmpty ? pending : t.recentEventText,
                ),
              ]
            : const <ClubDirectorRowDetail>[],
      ),
  ];
}

List<ClubDirectorRow> clubDirectorBroadcastRows(
  List<ClubDirectorBroadcast> broadcasts,
) {
  return <ClubDirectorRow>[
    for (int i = 0; i < broadcasts.length; i++)
      ClubDirectorRow(
        id: 'broadcast-$i',
        title: broadcasts[i].contentText,
        subtitle: broadcasts[i].targetText,
        value: broadcasts[i].receiptText,
      ),
  ];
}

List<ClubDirectorRow> clubDirectorMemberRows(
  List<ClubDirectorMemberRow> members,
) {
  return <ClubDirectorRow>[
    for (final ClubDirectorMemberRow m in members)
      ClubDirectorRow(
        id: m.id,
        title: m.title,
        subtitle: m.subtitle,
        value: m.value,
        valueTone: m.muted ? 'muted' : 'default',
      ),
  ];
}

List<ClubDirectorRow> clubDirectorTakeoverRows(
  List<ClubDirectorRole> candidates,
) {
  return <ClubDirectorRow>[
    for (final ClubDirectorRole r in candidates)
      ClubDirectorRow(
        id: '${r.teamId}:${r.memberId}',
        title: r.memberNameText,
        subtitle: r.roleNameText,
        value: r.confirmationText,
      ),
  ];
}

List<ClubDirectorRow> clubDirectorChapterRows(
  List<ClubDirectorChapterOption> chapters,
) {
  return <ClubDirectorRow>[
    for (final ClubDirectorChapterOption c in chapters)
      ClubDirectorRow(id: '${c.chapterId}', title: c.title),
  ];
}

List<ClubDirectorRow> clubDirectorIncidentRows(
  List<ClubDirectorIncident> incidents,
) {
  return <ClubDirectorRow>[
    for (final ClubDirectorIncident r in incidents)
      ClubDirectorRow(
        id: r.key,
        title: r.label,
        subtitle: r.sub.isEmpty ? r.text : '${r.text}\n${r.sub}',
      ),
  ];
}

/// 写结果的提示(小程序 executeAction 各分支的 toast 原话)。
void clubDirectorNotifyWriteResult(
  BuildContext context,
  ClubDirectorWriteResult result,
  ClubDirectorState after,
) {
  switch (result) {
    case ClubDirectorWriteResult.rejected:
      CyNativeNotice.show(context, '操作未生效，请刷新后重试');
    case ClubDirectorWriteResult.unknown:
      CyNativeNotice.show(context, '结果待核对，请勿重复操作');
    case ClubDirectorWriteResult.blocked:
      if (after.writeState == ClubDirectorWriteState.storageError) {
        CyNativeNotice.show(context, '无法安全保存，请稍后重试');
      }
    case ClubDirectorWriteResult.confirmed:
      break;
  }
}

// ─── 公共外壳与行列表 ───

/// 半屏 sheet 的公共外壳 —— 与 club_topic_detail_page 的 `_SheetFrame` 同材质
/// ([CupertinoPopupSurface] 系统弹窗材质,maxHeight 0.92)。导演台的弹层都在这
/// 一页之外,所以这里给一个公开版。
class ClubDirectorSheetFrame extends StatelessWidget {
  const ClubDirectorSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.sheetKey,
  });

  final String title;
  final Widget child;
  final Key? sheetKey;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
      child: CupertinoPopupSurface(
        child: Container(
          key: sheetKey,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.space3,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        key: const Key('sheet-close'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 24,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `club-director-row-list`:卡+行+分隔线,行数据全部由宿主算好。
class ClubDirectorRowList extends StatelessWidget {
  const ClubDirectorRowList({
    super.key,
    required this.rows,
    this.selectable = false,
    this.selectedId,
    this.onRowTap,
  });

  final List<ClubDirectorRow> rows;
  final bool selectable;
  final String? selectedId;
  final ValueChanged<String>? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final CyPalette palette = CyPalette.of(context);
    return ClubOpsCard(
      children: <Widget>[
        for (final ClubDirectorRow row in rows)
          GestureDetector(
            key: Key('director-row-${row.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: selectable ? () => onRowTap?.call(row.id) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space4,
                vertical: CyTokens.space3,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          row.title,
                          style: TextStyle(
                            fontSize: CyTokens.typeBody,
                            fontWeight: selectable && row.id == selectedId
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: palette.textPrimary,
                          ),
                        ),
                        for (final String line
                            in row.subtitle
                                .split('\n')
                                .where((String s) => s.isNotEmpty))
                          Text(
                            line,
                            style: TextStyle(
                              fontSize: CyTokens.typeCaption,
                              color: palette.textTertiary,
                            ),
                          ),
                        for (final ClubDirectorRowDetail d in row.details)
                          Text(
                            '${d.label}：${d.text}',
                            style: TextStyle(
                              fontSize: CyTokens.typeCaption,
                              color: palette.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selectable && row.id == selectedId)
                    Padding(
                      padding: const EdgeInsets.only(right: CyTokens.space1_5),
                      child: Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 16,
                        color: palette.actionPrimaryFg,
                      ),
                    ),
                  if (row.value.isNotEmpty)
                    Text(
                      row.value,
                      style: TextStyle(
                        fontSize: CyTokens.typeBody,
                        color: _toneColor(palette, row.valueTone),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Color _toneColor(CyPalette palette, String tone) {
    switch (tone) {
      case 'success':
        return CyTokens.statusSuccess;
      case 'warning':
        return CyTokens.statusWarning;
      case 'danger':
        return CyTokens.statusDanger;
      case 'muted':
        return palette.textTertiary;
      default:
        return palette.textPrimary;
    }
  }
}

/// `club-director-chip-group`:单选 chip 行(范围/角色/处理方式共用)。
class ClubDirectorChips extends StatelessWidget {
  const ClubDirectorChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<({String id, String label})> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final CyPalette palette = CyPalette.of(context);
    return Wrap(
      spacing: CyTokens.space2,
      runSpacing: CyTokens.space2,
      children: options
          .map(
            (({String id, String label}) option) => GestureDetector(
              key: Key('director-chip-${option.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: option.id == value ? null : () => onChanged(option.id),
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space3,
                  vertical: CyTokens.space1,
                ),
                decoration: BoxDecoration(
                  color: option.id == value
                      ? palette.actionPrimaryBg
                      : palette.bgSurfaceSubtle,
                  borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: option.id == value
                        ? palette.actionPrimaryFg
                        : palette.textSecondary,
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class ClubDirectorSectionTitle extends StatelessWidget {
  const ClubDirectorSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CyTokens.space4,
        bottom: CyTokens.space1,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: CyTokens.typeLabel,
          fontWeight: FontWeight.w600,
          color: CyPalette.of(context).textTertiary,
        ),
      ),
    );
  }
}

/// 原因/内容输入。真源是 textarea maxlength=200。
class ClubDirectorTextField extends StatelessWidget {
  const ClubDirectorTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.label,
    this.maxLines = 3,
    this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? label;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(
              top: CyTokens.space3,
              bottom: CyTokens.space1,
            ),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: palette.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          ),
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            placeholderStyle: TextStyle(color: palette.textTertiary),
            style: TextStyle(
              fontSize: CyTokens.typeBody,
              color: palette.textPrimary,
            ),
            maxLength: 200,
            maxLines: maxLines,
            minLines: 2,
            onChanged: onChanged,
            padding: const EdgeInsets.all(CyTokens.space3),
          ),
        ),
      ],
    );
  }
}

/// `club-director-unknown` —— 写入结果未知时的安全出口条。
/// 这不是提示,是唯一能把「发没发出去不确定」收敛掉的入口(真源注释)。
class ClubDirectorUnknownBar extends StatelessWidget {
  const ClubDirectorUnknownBar({
    super.key,
    required this.state,
    required this.onReconcile,
    required this.onRetry,
  });

  final ClubDirectorState state;
  final VoidCallback onReconcile;
  final VoidCallback onRetry;

  bool get visible =>
      state.writeLocked ||
      state.writeState == ClubDirectorWriteState.storageError;

  String get _title {
    switch (state.writeState) {
      case ClubDirectorWriteState.storageError:
        return '无法安全提交';
      case ClubDirectorWriteState.unknownWrite:
        return '结果待核对';
      default:
        return '操作处理中';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        0,
      ),
      child: ClubOpsCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _title,
                  key: const Key('director-unknown-title'),
                  style: TextStyle(
                    fontSize: CyTokens.typeBody,
                    fontWeight: FontWeight.w700,
                    color: CyTokens.statusWarning,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  state.writeMessage,
                  style: TextStyle(
                    fontSize: CyTokens.typeCaption,
                    color: palette.textSecondary,
                  ),
                ),
                if (state.writeState == ClubDirectorWriteState.unknownWrite)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space2),
                    child: Row(
                      children: <Widget>[
                        CupertinoButton(
                          key: const Key('director-unknown-reconcile'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space2,
                          ),
                          minimumSize: const Size(44, 44),
                          onPressed: onReconcile,
                          child: Text(
                            '核对结果',
                            style: TextStyle(
                              fontSize: CyTokens.typeBody,
                              color: palette.brand,
                            ),
                          ),
                        ),
                        if (state.canRetryUnknownWrite)
                          CupertinoButton(
                            key: const Key('director-unknown-retry'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: CyTokens.space2,
                            ),
                            minimumSize: const Size(44, 44),
                            onPressed: onRetry,
                            child: Text(
                              '重试原操作',
                              style: TextStyle(
                                fontSize: CyTokens.typeBody,
                                color: palette.brand,
                              ),
                            ),
                          ),
                      ],
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

/// 导演台半屏的统一弹出:底部弹层 + 系统弹窗材质(铁律:不自绘浮层)。
Future<void> showClubDirectorSheet(
  BuildContext context, {
  required String title,
  required Widget child,
  Key? sheetKey,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) =>
        ClubDirectorSheetFrame(title: title, sheetKey: sheetKey, child: child),
  );
}

// ─── D4 手动解锁章节 ───

class ClubDirectorChapterSheet extends ConsumerStatefulWidget {
  const ClubDirectorChapterSheet({super.key, required this.activityId});

  final int activityId;

  /// 小程序 `openManualUnlock` 的闸。
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    int activityId,
  ) async {
    final ClubDirectorState s = ref.read(clubDirectorProvider(activityId));
    if (s.writeLocked) return;
    if (s.projection?.canUnlockChapter != true) {
      CyNativeNotice.show(context, '当前没有可解锁的章节');
      return;
    }
    await showClubDirectorSheet(
      context,
      title: '手动解锁章节',
      sheetKey: const Key('director-chapter-sheet'),
      child: ClubDirectorChapterSheet(activityId: activityId),
    );
  }

  @override
  ConsumerState<ClubDirectorChapterSheet> createState() =>
      _ClubDirectorChapterSheetState();
}

class _ClubDirectorChapterSheetState
    extends ConsumerState<ClubDirectorChapterSheet> {
  final TextEditingController _reason = TextEditingController();
  String? _selectedId;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ClubDirectorState s = ref.watch(
      clubDirectorProvider(widget.activityId),
    );
    final List<ClubDirectorChapterOption> options =
        s.projection?.unlockChapterOptions ??
        const <ClubDirectorChapterOption>[];
    final String selected =
        _selectedId ?? (options.isEmpty ? '' : '${options.first.chapterId}');
    final bool disabled = s.writeLocked || _reason.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClubDirectorRowList(
            rows: clubDirectorChapterRows(options),
            selectable: true,
            selectedId: selected,
            onRowTap: (String id) => setState(() => _selectedId = id),
          ),
          ClubDirectorTextField(
            key: const Key('director-unlock-reason'),
            controller: _reason,
            label: '现场原因(必填)',
            placeholder: '写明为什么要手动解锁,会进审计记录',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('director-unlock-confirm'),
            label: '解锁',
            width: double.infinity,
            onPressed: disabled
                ? null
                : () async {
                    final int? chapterId = int.tryParse(selected);
                    final String reason = _reason.text.trim();
                    if (chapterId == null || reason.isEmpty) {
                      CyNativeNotice.show(context, '请填写手动解锁原因');
                      return;
                    }
                    await clubDirectorSettleWrite(
                      context,
                      ref,
                      widget.activityId,
                      ref
                          .read(
                            clubDirectorProvider(widget.activityId).notifier,
                          )
                          .unlockChapter(chapterId: chapterId, reason: reason),
                    );
                  },
          ),
          if (s.writeMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                s.writeMessage,
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: CyPalette.of(context).textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── D5 队伍进度(只读)───

class ClubDirectorTeamSheet extends ConsumerWidget {
  const ClubDirectorTeamSheet({super.key, required this.activityId});

  final int activityId;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    int activityId,
  ) {
    return showClubDirectorSheet(
      context,
      title: '队伍进度',
      sheetKey: const Key('director-team-sheet'),
      child: ClubDirectorTeamSheet(activityId: activityId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClubDirectorProjection? p = ref
        .watch(clubDirectorProvider(activityId))
        .projection;
    final List<ClubDirectorRow> teams = clubDirectorTeamRows(
      p?.teams ?? const <ClubDirectorTeam>[],
    );
    final List<ClubDirectorRow> collab = clubDirectorBroadcastRows(
      p?.broadcasts ?? const <ClubDirectorBroadcast>[],
    );
    // 纯只读展示,没有主键 —— 稿子里唯二的操作是关闭。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClubDirectorRowList(rows: teams),
          if (collab.isNotEmpty) ...<Widget>[
            const ClubDirectorSectionTitle('队伍协作'),
            ClubDirectorRowList(rows: collab),
          ],
        ],
      ),
    );
  }
}

// ─── D6 角色分配 / 角色接管 ───

class ClubDirectorRoleSheet extends ConsumerStatefulWidget {
  const ClubDirectorRoleSheet({super.key, required this.activityId});

  final int activityId;

  /// 小程序 `openRoleSheet` 的闸。
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    int activityId,
  ) async {
    final ClubDirectorState s = ref.read(clubDirectorProvider(activityId));
    if (s.writeLocked) return;
    if (s.projection?.canAssignRoles != true) {
      CyNativeNotice.show(context, '当前不能调整角色');
      return;
    }
    if (s.projection?.roleMemberRows.isNotEmpty != true) {
      CyNativeNotice.show(context, '还没有可分角色的成员');
      return;
    }
    await showClubDirectorSheet(
      context,
      title: '角色分配',
      sheetKey: const Key('director-role-sheet'),
      child: ClubDirectorRoleSheet(activityId: activityId),
    );
  }

  @override
  ConsumerState<ClubDirectorRoleSheet> createState() =>
      _ClubDirectorRoleSheetState();
}

class _ClubDirectorRoleSheetState extends ConsumerState<ClubDirectorRoleSheet> {
  String? _memberId;
  String? _roleCode;
  _TakeoverDraft? _takeover;

  /// 接管的填写态(小程序 `takeoverDraft`)。
  String? _targetId;
  final TextEditingController _takeoverReason = TextEditingController();

  @override
  void dispose() {
    _takeoverReason.dispose();
    super.dispose();
  }

  void _pickMember(String id) {
    final ClubDirectorProjection p = ref
        .read(clubDirectorProvider(widget.activityId))
        .projection!;
    final ClubDirectorRole? row = p.roles
        .where((ClubDirectorRole r) => '${r.teamId}:${r.memberId}' == id)
        .firstOrNull;
    if (row == null || row.teamId == null || row.memberId == null) {
      CyNativeNotice.show(context, '成员信息待同步');
      return;
    }
    setState(() {
      _memberId = id;
      _roleCode = p.roleOptions.any((o) => o.roleCode == row.roleCode)
          ? row.roleCode
          : (p.roleOptions.firstOrNull?.roleCode ?? '');
    });
  }

  void _openTakeover(String sourceId) {
    final ClubDirectorProjection p = ref
        .read(clubDirectorProvider(widget.activityId))
        .projection!;
    if (!p.canTakeoverRoles) {
      CyNativeNotice.show(context, '当前不能接管角色');
      return;
    }
    final ClubDirectorRole? source = p.roles
        .where((ClubDirectorRole r) => '${r.teamId}:${r.memberId}' == sourceId)
        .firstOrNull;
    if (source == null ||
        !source.isConfirmedRoleSource ||
        source.teamId == null ||
        source.memberId == null) {
      CyNativeNotice.show(context, '来源角色待确认');
      return;
    }
    final List<ClubDirectorRole> targets = p.roles
        .where(
          (ClubDirectorRole r) =>
              r.teamId == source.teamId &&
              r.memberId != null &&
              r.memberId != source.memberId &&
              r.roleCode.isEmpty,
        )
        .toList(growable: false);
    if (targets.isEmpty) {
      CyNativeNotice.show(context, '同队没有待分配成员');
      return;
    }
    setState(() {
      _takeover = _TakeoverDraft(
        teamId: source.teamId!,
        sourceMemberId: source.memberId!,
        targets: targets,
      );
      _targetId = '${targets.first.teamId}:${targets.first.memberId}';
      _takeoverReason.clear();
    });
  }

  Future<void> _pickTarget() async {
    final _TakeoverDraft? draft = _takeover;
    if (draft == null) return;
    final CyPalette palette = CyPalette.of(context);
    final String? picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: const Text('接管给'),
        actions: draft.targets
            .map(
              (ClubDirectorRole t) => CupertinoActionSheetAction(
                key: Key('director-takeover-target-${t.memberId}'),
                child: Text(
                  t.memberNameText,
                  style: TextStyle(color: palette.textPrimary),
                ),
                onPressed: () =>
                    Navigator.of(sheetContext).pop('${t.teamId}:${t.memberId}'),
              ),
            )
            .toList(growable: false),
        cancelButton: CupertinoActionSheetAction(
          child: Text('取消', style: TextStyle(color: palette.textPrimary)),
          onPressed: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _targetId = picked);
  }

  Future<void> _confirmTakeover() async {
    final ClubDirectorProjection p = ref
        .read(clubDirectorProvider(widget.activityId))
        .projection!;
    final _TakeoverDraft? draft = _takeover;
    final String? targetId = _targetId;
    final String reason = _takeoverReason.text.trim();
    if (draft == null || targetId == null) return;
    if (!p.canTakeoverRoles) {
      CyNativeNotice.show(context, '当前不能接管角色');
      return;
    }
    final int? targetMemberId = int.tryParse(targetId.split(':').last);
    if (ClubDirectorTakeover.validate(
          roles: p.roles,
          teamId: draft.teamId,
          sourceMemberId: draft.sourceMemberId,
          targetMemberId: targetMemberId,
          reason: reason,
        ) ==
        null) {
      CyNativeNotice.show(context, '请选同队待分配成员并填写原因');
      return;
    }
    await clubDirectorSettleWrite(
      context,
      ref,
      widget.activityId,
      ref
          .read(clubDirectorProvider(widget.activityId).notifier)
          .takeover(
            teamId: draft.teamId,
            sourceMemberId: draft.sourceMemberId,
            targetMemberId: targetMemberId!,
            reason: reason,
          ),
    );
  }

  Future<void> _confirmAssignment() async {
    final ClubDirectorProjection p = ref
        .read(clubDirectorProvider(widget.activityId))
        .projection!;
    final String? memberId = _memberId;
    final String? roleCode = _roleCode;
    if (!p.canAssignRoles ||
        memberId == null ||
        roleCode == null ||
        roleCode.isEmpty) {
      CyNativeNotice.show(context, '请先选择有效角色');
      return;
    }
    final List<String> parts = memberId.split(':');
    final int? teamId = int.tryParse(parts.first);
    final int? member = parts.length > 1 ? int.tryParse(parts.last) : null;
    if (teamId == null || member == null) {
      CyNativeNotice.show(context, '请先选择有效角色');
      return;
    }
    await clubDirectorSettleWrite(
      context,
      ref,
      widget.activityId,
      ref
          .read(clubDirectorProvider(widget.activityId).notifier)
          .assignRole(teamId: teamId, memberId: member, roleCode: roleCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final ClubDirectorState s = ref.watch(
      clubDirectorProvider(widget.activityId),
    );
    final ClubDirectorProjection? p = s.projection;
    if (p == null) return const SizedBox.shrink();
    final _TakeoverDraft? draft = _takeover;
    final ClubDirectorRole? target = draft?.targets
        .where((ClubDirectorRole t) => '${t.teamId}:${t.memberId}' == _targetId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ClubDirectorSectionTitle('选择成员'),
          ClubDirectorRowList(
            rows: clubDirectorMemberRows(p.roleMemberRows),
            selectable: true,
            selectedId: _memberId,
            onRowTap: _pickMember,
          ),
          if (p.roleOptions.isNotEmpty) ...<Widget>[
            const ClubDirectorSectionTitle('分配固定角色'),
            ClubDirectorChips(
              options: p.roleOptions
                  .map((o) => (id: o.roleCode, label: o.label))
                  .toList(growable: false),
              value: _roleCode ?? '',
              onChanged: (String id) => setState(() => _roleCode = id),
            ),
          ],
          if (p.takeoverCandidates.isNotEmpty) ...<Widget>[
            const ClubDirectorSectionTitle('角色接管'),
            ClubDirectorRowList(
              rows: clubDirectorTakeoverRows(p.takeoverCandidates),
              selectable: true,
              selectedId: draft == null
                  ? null
                  : '${draft.teamId}:${draft.sourceMemberId}',
              onRowTap: _openTakeover,
            ),
          ],
          if (draft != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: ClubOpsCard(
                children: <Widget>[
                  ClubOpsRow(
                    key: const Key('director-takeover-target'),
                    title: '接管给',
                    value: target?.memberNameText ?? '选择同队待分配成员',
                    valueColor: palette.textSecondary,
                    onTap: _pickTarget,
                  ),
                  ClubOpsRow(
                    title: '接管原因(必填)',
                    minHeight: 0,
                    trailing: const SizedBox.shrink(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.space4,
                      0,
                      CyTokens.space4,
                      CyTokens.space3,
                    ),
                    child: ClubDirectorTextField(
                      key: const Key('director-takeover-reason'),
                      controller: _takeoverReason,
                      placeholder: '写明为什么要接管,会进审计记录',
                      label: null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CyNativeButton(
                      key: const Key('director-takeover-cancel'),
                      label: '取消接管',
                      role: CyNativeButtonRole.secondary,
                      width: double.infinity,
                      onPressed: s.writeLocked
                          ? null
                          : () => setState(() => _takeover = null),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CyNativeButton(
                      key: const Key('director-takeover-confirm'),
                      label: '确认接管',
                      width: double.infinity,
                      onPressed:
                          s.writeLocked || _takeoverReason.text.trim().isEmpty
                          ? null
                          : () => _confirmTakeover(),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('director-role-confirm'),
            label: '确认分配',
            width: double.infinity,
            onPressed: s.writeLocked ? null : _confirmAssignment,
          ),
        ],
      ),
    );
  }
}

class _TakeoverDraft {
  const _TakeoverDraft({
    required this.teamId,
    required this.sourceMemberId,
    required this.targets,
  });

  final int teamId;
  final int sourceMemberId;
  final List<ClubDirectorRole> targets;
}

// ─── D7 定向广播 ───

const List<({String id, String label})> kClubDirectorBroadcastScopes =
    <({String id, String label})>[
      (id: 'ALL', label: '全部玩家'),
      (id: 'TEAM', label: '定向队伍'),
      (id: 'ROLE', label: '定向角色'),
    ];

class ClubDirectorBroadcastSheet extends ConsumerStatefulWidget {
  const ClubDirectorBroadcastSheet({super.key, required this.activityId});

  final int activityId;

  /// 小程序 `openBroadcast` 的闸(成员弹层里那枚入口也走这里)。
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    int activityId,
  ) async {
    final ClubDirectorState s = ref.read(clubDirectorProvider(activityId));
    if (s.writeLocked) return;
    if (s.projection?.canBroadcast != true) {
      CyNativeNotice.show(context, '当前不能发送广播');
      return;
    }
    await showClubDirectorSheet(
      context,
      title: '定向广播',
      sheetKey: const Key('director-broadcast-sheet'),
      child: ClubDirectorBroadcastSheet(activityId: activityId),
    );
  }

  @override
  ConsumerState<ClubDirectorBroadcastSheet> createState() =>
      _ClubDirectorBroadcastSheetState();
}

class _ClubDirectorBroadcastSheetState
    extends ConsumerState<ClubDirectorBroadcastSheet> {
  String _scope = 'ALL';
  int _targetIndex = 0;
  final TextEditingController _content = TextEditingController();

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _confirm(ClubDirectorProjection p) async {
    final List<ClubDirectorBroadcastTarget> targets = p.broadcastTargets(
      _scope,
    );
    final ClubDirectorBroadcastTarget? selected = _targetIndex < targets.length
        ? targets[_targetIndex]
        : null;
    final int? count = p.broadcastRecipientCount(selected);
    final bool ready = count != null && count > 0 && selected != null;
    final String content = _content.text.trim();
    if (!p.canBroadcast || !ready) {
      CyNativeNotice.show(context, '接收范围待确认，暂不能发送');
      return;
    }
    if (content.isEmpty) {
      CyNativeNotice.show(context, '请输入广播内容');
      return;
    }
    await clubDirectorSettleWrite(
      context,
      ref,
      widget.activityId,
      ref
          .read(clubDirectorProvider(widget.activityId).notifier)
          .broadcast(
            targetType: _scope,
            content: content,
            targetId: _scope == 'TEAM' ? selected.id : null,
            roleCode: _scope == 'ROLE' ? selected.id as String : null,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final ClubDirectorState s = ref.watch(
      clubDirectorProvider(widget.activityId),
    );
    final ClubDirectorProjection? p = s.projection;
    if (p == null) return const SizedBox.shrink();
    final List<ClubDirectorBroadcastTarget> targets = p.broadcastTargets(
      _scope,
    );
    final ClubDirectorBroadcastTarget? selected = _targetIndex < targets.length
        ? targets[_targetIndex]
        : null;
    final int? count = p.broadcastRecipientCount(selected);
    final bool ready = count != null && count > 0 && selected != null;
    final String previewText = selected == null
        ? '定向范围待选择 · 人数待确认'
        : '${selected.label} · ${count == null ? '人数待确认' : '$count 人'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ClubDirectorSectionTitle('范围'),
          ClubDirectorChips(
            options: kClubDirectorBroadcastScopes,
            value: _scope,
            onChanged: (String id) => setState(() {
              _scope = id;
              _targetIndex = 0;
            }),
          ),
          if (_scope != 'ALL')
            ClubDirectorRowList(
              rows: <ClubDirectorRow>[
                for (int i = 0; i < targets.length; i++)
                  ClubDirectorRow(
                    id: '${targets[i].id}',
                    title: targets[i].label,
                    value: targets[i].memberCount == null
                        ? '人数待确认'
                        : '${targets[i].memberCount} 人',
                  ),
              ],
              selectable: true,
              selectedId: selected == null ? null : '${selected.id}',
              onRowTap: (String id) => setState(() {
                for (int i = 0; i < targets.length; i++) {
                  if ('${targets[i].id}' == id) _targetIndex = i;
                }
              }),
            ),
          const ClubDirectorSectionTitle('内容'),
          ClubDirectorTextField(
            key: const Key('director-broadcast-content'),
            controller: _content,
            placeholder: '输入广播内容',
            onChanged: (_) => setState(() {}),
          ),
          ClubDirectorRowList(rows: clubDirectorBroadcastRows(p.broadcasts)),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('director-broadcast-send'),
            label: '发送',
            width: double.infinity,
            onPressed: s.writeLocked || !ready ? null : () => _confirm(p),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              previewText,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── D8 现场事件 ───

class ClubDirectorIncidentSheet extends ConsumerStatefulWidget {
  const ClubDirectorIncidentSheet({super.key, required this.activityId});

  final int activityId;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    int activityId,
  ) {
    return showClubDirectorSheet(
      context,
      title: '现场事件',
      sheetKey: const Key('director-incident-sheet'),
      child: ClubDirectorIncidentSheet(activityId: activityId),
    );
  }

  @override
  ConsumerState<ClubDirectorIncidentSheet> createState() =>
      _ClubDirectorIncidentSheetState();
}

class _ClubDirectorIncidentSheetState
    extends ConsumerState<ClubDirectorIncidentSheet> {
  String? _selectedKey;
  String _mode = '';

  void _select(String key) {
    final ClubDirectorProjection p = ref
        .read(clubDirectorProvider(widget.activityId))
        .projection!;
    final ClubDirectorIncident? row = p.incidents
        .where((ClubDirectorIncident i) => i.key == key)
        .firstOrNull;
    // 只有一个可选动作时直接选中,省一次点击;没有可选动作时清空。
    setState(() {
      _selectedKey = key;
      _mode = row != null && row.modes.length == 1 ? row.modes.first.id : '';
    });
  }

  Future<void> _submit(ClubDirectorProjection p) async {
    final ClubDirectorIncident? row = p.incidents
        .where((ClubDirectorIncident i) => i.key == _selectedKey)
        .firstOrNull;
    if (row == null) {
      CyNativeNotice.show(context, '先选一条要处理的事件');
      return;
    }
    if (_mode.isEmpty) {
      CyNativeNotice.show(context, '先选处理方式');
      return;
    }
    final ClubDirectorController c = ref.read(
      clubDirectorProvider(widget.activityId).notifier,
    );

    if (_mode == 'resume' && row.nodeId != null) {
      await clubDirectorSettleWrite(
        context,
        ref,
        widget.activityId,
        c.stationResume(row.nodeId!),
      );
      return;
    }

    if (_mode == 'reject' && row.submissionId != null) {
      final String? reason = await showCySystemTextInputAlert(
        context: context,
        title: '驳回重交',
        placeholder: '驳回原因（至少 2 个字，玩家会看到）',
        confirmText: '确认驳回',
        cancelText: '再想想',
      );
      if (reason == null) return;
      final String trimmed = reason.trim();
      if (trimmed.length < 2) {
        if (!mounted) return;
        CyNativeNotice.show(context, '请填写驳回原因');
        return;
      }
      if (!mounted) return;
      await clubDirectorSettleWrite(
        context,
        ref,
        widget.activityId,
        c.rejectSubmission(submissionId: row.submissionId!, reason: trimmed),
      );
      return;
    }

    if (_mode == 'pause' && row.nodeId != null) {
      final List<ClubDirectorFallbackPlan> plans = row.planOptions;
      if (plans.length > 1) {
        CyNativeNotice.show(context, '有多个备用方案，请到后台指定');
        return;
      }
      final ClubDirectorFallbackPlan? plan = plans.isEmpty ? null : plans.first;
      final String? reason = await showCySystemTextInputAlert(
        context: context,
        title: '暂停本站',
        placeholder: '暂停原因（至少 2 个字，会同步给商家与玩家）',
        confirmText: '确认暂停',
        cancelText: '再想想',
      );
      if (reason == null) return;
      final String trimmed = reason.trim();
      if (trimmed.length < 2) {
        if (!mounted) return;
        CyNativeNotice.show(context, '请填写暂停原因');
        return;
      }
      if (!mounted) return;
      await clubDirectorSettleWrite(
        context,
        ref,
        widget.activityId,
        c.stationPause(row.nodeId!, reason: trimmed, plan: plan),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final ClubDirectorState s = ref.watch(
      clubDirectorProvider(widget.activityId),
    );
    final ClubDirectorProjection? p = s.projection;
    final List<ClubDirectorIncident> incidents =
        p?.incidents ?? const <ClubDirectorIncident>[];
    final ClubDirectorIncident? selected = incidents
        .where((ClubDirectorIncident i) => i.key == _selectedKey)
        .firstOrNull;
    final List<({String id, String label})> modes =
        selected?.modes ?? const <({String id, String label})>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClubDirectorRowList(
            rows: clubDirectorIncidentRows(incidents),
            selectable: true,
            selectedId: _selectedKey,
            onRowTap: _select,
          ),
          const ClubDirectorSectionTitle('处理方式'),
          ClubDirectorChips(
            options: modes,
            value: _mode,
            onChanged: (String id) => setState(() => _mode = id),
          ),
          const SizedBox(height: CyTokens.space4),
          CyNativeButton(
            key: const Key('director-incident-confirm'),
            label: '确认处理',
            width: double.infinity,
            onPressed: _mode.isEmpty || s.writeLocked
                ? null
                : () => _submit(p!),
          ),
          // 组件默认 caption(真源:暂停的作用域只有本站,权益与已完成提交不动)。
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '暂停只影响本站，不改变已发放的权益与已完成的提交。',
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
