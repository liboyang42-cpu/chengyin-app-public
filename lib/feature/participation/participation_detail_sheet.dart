import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../feature/withdrawal/withdrawal_contact_dialog.dart'
    show kWithdrawalContactWechatId;
import 'participation_models.dart';

/// 真源 wxml 底部固定文案:只要 info.ruleInstructions 有值就渲染这一段
/// (展示的是写死的规则原话,不是接口字段内容)。
const String kParticipationRuleInstructionsCopy =
    '商家仅可在路线场次开始前3天申请退出。一旦场次启动，鉴于官方统一调度及'
    '多方协作的特性，商家不可中途退出或自行暂停。如遇不可抗力等紧急情况，'
    '请务必联系客服介入处理。';

/// R10「联系客服」落点:App 内没有微信原生客服会话,按 R10 口径弹平台客服
/// 微信号(与提现出口同一个客服号,复制走线下沟通),不发任何资金请求。
Future<void> showParticipationContactDialog(BuildContext context) async {
  final bool? copied = await showCupertinoDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => CupertinoAlertDialog(
      title: const Text('联系客服'),
      content: Text(
        '路线、场次或接待有问题,请通过微信联系客服处理。\n\n'
        '微信号:$kWithdrawalContactWechatId',
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('返回'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: kWithdrawalContactWechatId),
            );
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          },
          child: const Text('复制'),
        ),
      ],
    ),
  );
  if (copied == true && context.mounted) {
    CyNativeNotice.show(context, '微信号已复制');
  }
}

typedef ParticipationDetailPresenter =
    Future<ParticipationDetailResult?> Function(
      BuildContext context,
      ParticipationDetail detail,
    );

abstract interface class ParticipationDetailNativeDriver {
  Future<bool> show({
    required BuildContext context,
    required AppleLiquidSheetContent content,
  });
}

class _AppleLiquidParticipationDetailDriver
    implements ParticipationDetailNativeDriver {
  const _AppleLiquidParticipationDetailDriver();

  @override
  Future<bool> show({
    required BuildContext context,
    required AppleLiquidSheetContent content,
  }) {
    return AppleLiquidSheet.showSheet(
      heightFraction: 0.92,
      backgroundZoomScale: MediaQuery.disableAnimationsOf(context) ? 1 : 0.96,
      scrollContext: context,
      content: content,
    );
  }
}

/// 半屏只收集意图:按钮按下即收起弹窗,由宿主「我的参与」页执行确认弹窗/跳转
/// —— 对齐真源 `_leave`(先 close 再 navigateTo,不在弹窗上压页面)。
Future<ParticipationDetailResult?> showParticipationDetail(
  BuildContext context,
  ParticipationDetail detail, {
  ParticipationDetailNativeDriver? nativeDriver,
}) async {
  ParticipationDetailResult? result;
  void act(ParticipationDetailActionKind kind) {
    result = ParticipationDetailResult(kind: kind, detail: detail);
  }

  final List<AppleLiquidSheetRow> performanceRows = <AppleLiquidSheetRow>[
    if (detail.dateText.isNotEmpty)
      AppleLiquidSheetRow.value(
        title: '活动日期',
        value: detail.dateText,
        systemImage: 'calendar',
      ),
    // 真源:没有真值整行不渲染。玩家侧 /api/registration/info 通常不带
    // nodeName,不再摆「待分配」占位行。
    if (detail.nodeName != null)
      AppleLiquidSheetRow.value(
        title: '最终分配节点',
        value: detail.nodeName!,
        systemImage: 'mappin.and.ellipse',
      ),
    // 商家填的「每日可接待时段」(cooperateDate),不是场次排期 —— 标签随真源。
    if (detail.cooperateDate != null)
      AppleLiquidSheetRow.value(
        title: '接待时间',
        value: detail.cooperateDate!,
        systemImage: 'clock',
      ),
  ];

  final List<AppleLiquidSheetRow> actionRows = <AppleLiquidSheetRow>[
    AppleLiquidSheetRow.button(
      title: '开始玩',
      semanticLabel: '开始玩',
      systemImage: 'play.fill',
      dismissesSheet: true,
      onPressed: () => act(ParticipationDetailActionKind.startPlay),
    ),
    if (detail.canCancel)
      AppleLiquidSheetRow.button(
        title: '取消参与',
        semanticLabel: '取消参与',
        systemImage: 'xmark.circle',
        dismissesSheet: true,
        onPressed: () => act(ParticipationDetailActionKind.cancel),
      ),
    if (detail.needModify)
      AppleLiquidSheetRow.button(
        title: '去修改',
        semanticLabel: '去修改',
        systemImage: 'square.and.pencil',
        dismissesSheet: true,
        onPressed: () => act(ParticipationDetailActionKind.modify),
      ),
    if (detail.showContactService)
      AppleLiquidSheetRow.button(
        title: '联系客服',
        semanticLabel: '联系客服',
        systemImage: 'person.crop.circle.badge.questionmark',
        dismissesSheet: true,
        onPressed: () => act(ParticipationDetailActionKind.contact),
      ),
    // 核验扫码与核销进度统计同一开关(真源 info.status == 1)。
    if (detail.showOrderStats)
      AppleLiquidSheetRow.button(
        title: '核验扫码',
        semanticLabel: '核验扫码',
        systemImage: 'qrcode.viewfinder',
        dismissesSheet: true,
        onPressed: () => act(ParticipationDetailActionKind.scan),
      ),
  ];

  try {
    final bool shownNatively =
        await (nativeDriver ?? const _AppleLiquidParticipationDetailDriver()).show(
          context: context,
          content: AppleLiquidSheetContent(
            title: '参与详情',
            doneSemanticLabel: '关闭参与详情，返回参与列表',
            detents: const AppleLiquidSheetDetents(
              initialHeight: 560,
              expandedHeight: 760,
            ),
            sections: <AppleLiquidSheetSection>[
              AppleLiquidSheetSection(
                rows: <AppleLiquidSheetRow>[
                  AppleLiquidSheetRow.identity(
                    title: detail.topicName,
                    role: detail.modeText.isEmpty ? '参与记录' : detail.modeText,
                    activityType: detail.statusText,
                    description: detail.activityDescription,
                    avatarUrl: detail.coverUrl.isEmpty ? null : detail.coverUrl,
                    systemImage: 'figure.walk',
                  ),
                ],
              ),
              if (detail.showRemainingBadge)
                AppleLiquidSheetSection(
                  rows: <AppleLiquidSheetRow>[
                    AppleLiquidSheetRow.text(
                      title: detail.remainingDaysText,
                      systemImage: 'clock.badge.exclamationmark',
                    ),
                  ],
                ),
              if (performanceRows.isNotEmpty)
                AppleLiquidSheetSection(title: '履约信息', rows: performanceRows),
              if (detail.showOrderStats)
                AppleLiquidSheetSection(
                  title: '核销进度',
                  rows: <AppleLiquidSheetRow>[
                    AppleLiquidSheetRow.factsGrid(
                      title: '核销进度',
                      columns: 2,
                      facts: <AppleLiquidSheetFact>[
                        AppleLiquidSheetFact(
                          label: '待核销',
                          value: '${detail.pendingVerification ?? '—'}人',
                          systemImage: 'person.crop.circle.badge.clock',
                        ),
                        AppleLiquidSheetFact(
                          label: '已核销/总订单',
                          value:
                              '${detail.verifiedCount ?? '—'}/${detail.totalOrderCount ?? '—'}人',
                          systemImage: 'checkmark.seal',
                        ),
                      ],
                    ),
                  ],
                ),
              // 真源:只要有 templateId 这块就必须渲染、必须可点;
              // 没图时文字入口照常,图只是锦上添花。
              if (detail.templateId != null)
                AppleLiquidSheetSection(
                  title: '模板',
                  rows: <AppleLiquidSheetRow>[
                    AppleLiquidSheetRow.button(
                      title: detail.templateName.isEmpty
                          ? '查看商家模板'
                          : detail.templateName,
                      subtitle: '模板详情',
                      systemImage: 'rectangle.stack',
                      semanticLabel:
                          '查看商家模板「${detail.templateName.isEmpty ? '查看商家模板' : detail.templateName}」详情',
                      dismissesSheet: true,
                      onPressed: () =>
                          act(ParticipationDetailActionKind.openTemplate),
                    ),
                  ],
                ),
              if (detail.hasRuleInstructions)
                AppleLiquidSheetSection(
                  title: '退出与暂停规则说明',
                  rows: <AppleLiquidSheetRow>[
                    AppleLiquidSheetRow.text(
                      title: kParticipationRuleInstructionsCopy,
                      systemImage: 'info.circle',
                    ),
                  ],
                ),
              AppleLiquidSheetSection(title: '操作', rows: actionRows),
            ],
          ),
        );
    if (shownNatively) return result;
  } on MissingPluginException {
    // 原生 sheet 插件未注册时保留完整 Cupertino 详情。
  } on PlatformException {
    // 原生 presentation 被系统拒绝时保留完整 Cupertino 详情。
  }
  if (!context.mounted) return result;

  return showCupertinoModalPopup<ParticipationDetailResult>(
    context: context,
    builder: (BuildContext popupContext) =>
        _ParticipationDetailFallback(detail: detail),
  );
}

class _ParticipationDetailFallback extends StatelessWidget {
  const _ParticipationDetailFallback({required this.detail});

  final ParticipationDetail detail;

  void _act(BuildContext context, ParticipationDetailActionKind kind) {
    Navigator.of(
      context,
    ).pop(ParticipationDetailResult(kind: kind, detail: detail));
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Material(
            color: palette.bgPage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space3,
                    CyTokens.space2,
                    CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '参与详情',
                          style: TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CyNativeIconButton(
                        key: const Key('participation-detail-close'),
                        label: '关闭参与详情',
                        icon: const CyNativeButtonIcon(
                          sfSymbol: 'xmark.circle.fill',
                          fallback: CupertinoIcons.xmark_circle_fill,
                        ),
                        iconSize: 24,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space2,
                      CyTokens.pageX,
                      CyTokens.space4,
                    ),
                    children: <Widget>[
                      Text(
                        detail.topicName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        <String>[
                          if (detail.modeText.isNotEmpty) detail.modeText,
                          detail.statusText,
                          if (detail.dateText.isNotEmpty) detail.dateText,
                        ].join(' · '),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                      if (detail.showRemainingBadge) ...<Widget>[
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          detail.remainingDaysText,
                          // 状态色走 CyPalette 双值,不用 CyTokens 暗色常量(C4)。
                          style: TextStyle(
                            color: palette.statusWarning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: CyTokens.space4),
                      if (detail.activityDescription != null)
                        _FallbackValue(
                          title: '活动说明',
                          value: detail.activityDescription!,
                        ),
                      if (detail.nodeName != null)
                        _FallbackValue(
                          title: '最终分配节点',
                          value: detail.nodeName!,
                        ),
                      if (detail.cooperateDate != null)
                        _FallbackValue(
                          title: '接待时间',
                          value: detail.cooperateDate!,
                        ),
                      if (detail.showOrderStats)
                        _FallbackValue(
                          title: '核销进度',
                          value:
                              '待核销 ${detail.pendingVerification ?? '—'}人 · '
                              '已核销/总订单 ${detail.verifiedCount ?? '—'}/${detail.totalOrderCount ?? '—'}人',
                        ),
                      if (detail.templateId != null)
                        CupertinoButton(
                          key: const Key('participation-action-template'),
                          padding: const EdgeInsets.symmetric(
                            vertical: CyTokens.space1,
                          ),
                          onPressed: () => _act(
                            context,
                            ParticipationDetailActionKind.openTemplate,
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(CupertinoIcons.doc_on_doc, size: 16),
                              const SizedBox(width: CyTokens.space1),
                              Expanded(
                                child: Text(
                                  detail.templateName.isEmpty
                                      ? '查看商家模板'
                                      : detail.templateName,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              const Icon(CupertinoIcons.chevron_forward),
                            ],
                          ),
                        ),
                      if (detail.hasRuleInstructions)
                        _FallbackValue(
                          title: '退出与暂停规则说明',
                          value: kParticipationRuleInstructionsCopy,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space2,
                    CyTokens.pageX,
                    CyTokens.space4,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    spacing: CyTokens.space2,
                    runSpacing: CyTokens.space2,
                    children: <Widget>[
                      CyNativeButton(
                        key: const Key('participation-action-start-play'),
                        label: '开始玩',
                        onPressed: () => _act(
                          context,
                          ParticipationDetailActionKind.startPlay,
                        ),
                      ),
                      if (detail.canCancel)
                        CyNativeButton(
                          key: const Key('participation-action-cancel'),
                          label: '取消参与',
                          role: CyNativeButtonRole.destructive,
                          onPressed: () => _act(
                            context,
                            ParticipationDetailActionKind.cancel,
                          ),
                        ),
                      if (detail.needModify)
                        CyNativeButton(
                          key: const Key('participation-action-modify'),
                          label: '去修改',
                          role: CyNativeButtonRole.secondary,
                          onPressed: () => _act(
                            context,
                            ParticipationDetailActionKind.modify,
                          ),
                        ),
                      if (detail.showContactService)
                        CyNativeButton(
                          key: const Key('participation-action-contact'),
                          label: '联系客服',
                          role: CyNativeButtonRole.secondary,
                          onPressed: () => _act(
                            context,
                            ParticipationDetailActionKind.contact,
                          ),
                        ),
                      if (detail.showOrderStats)
                        CyNativeButton(
                          key: const Key('participation-action-scan'),
                          label: '核验扫码',
                          role: CyNativeButtonRole.secondary,
                          onPressed: () =>
                              _act(context, ParticipationDetailActionKind.scan),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FallbackValue extends StatelessWidget {
  const _FallbackValue({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
