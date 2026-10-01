import '../../l10n/strings.dart';
import 'merchant_crm_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../core/widgets/unsaved_guard.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/merchant_crm_console_api.dart';
import '../../data/models/merchant_crm_console.dart';

/// 「客户」页(CRM 运营台)的页内面板 —— 筛选 / 批量标签 / 合规触达 / 分群。
///
/// ★ 结构逐段对齐快照 `pages/merchant/customer/index.wxml` 的 `cu-head` 区块
///   (`cu-toolbar` / `cu-filter` / `cu-batch` / `cu-campaign`);
///   全部是**展示层**:状态与请求都留在页面,这里只画。
/// ★ `cu-toolbar` 里的「导出」不在这里 —— 它在 App 侧是导航栏按钮(#71 落地),
///   不重复摆第二个入口。

/// 面板的统一外框:浅色软底 + 细描边(商家恒浅色,D10)。
class CrmPanelCard extends StatelessWidget {
  const CrmPanelCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: child,
    );
  }
}

/// 面板内小标题(`cu-filter-title`)。
class CrmPanelLabel extends StatelessWidget {
  const CrmPanelLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CyTokens.space2,
        bottom: CyTokens.space1_5,
      ),
      child: Text(
        text,
        style: CyType.caption1.copyWith(
          color: CyPalette.of(context).textSecondary,
        ),
      ),
    );
  }
}

/// 页内错误条(`cy-inline-error`):说清哪一块失败 + 一个重试入口。
class CrmInlineError extends StatelessWidget {
  const CrmInlineError({
    super.key,
    required this.title,
    this.sub = '',
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String sub;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: CyType.footnote.copyWith(color: p.statusWarning),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: CyType.caption1.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
          ),
          if (onAction != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              minimumSize: const Size(44, 44),
              onPressed: onAction,
              child: Text(actionLabel ?? stringsOf(context).merchantCrmPanelRetry),
            ),
        ],
      ),
    );
  }
}

/// 顶部筛选档 chips + 尾部的「管理」(`cu-segs`)。
class CrmSegmentChips extends StatelessWidget {
  const CrmSegmentChips({
    super.key,
    required this.segment,
    required this.onTap,
    required this.toolsOpen,
    required this.onToggleTools,
  });

  final String segment;
  final ValueChanged<String> onTap;
  final bool toolsOpen;
  final VoidCallback onToggleTools;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: Row(
        children: <Widget>[
          for (final CrmSegmentOption option in kCrmSegmentOptions)
            Padding(
              padding: const EdgeInsets.only(right: CyTokens.space2),
              child: CyChip(
                label: merchantCrmLocalText(context, option.label),
                selected: option.key == segment,
                onTap: () => onTap(option.key),
              ),
            ),
          CyChip(
            label: toolsOpen ? stringsOf(context).merchantCrmPanelCollapse : stringsOf(context).merchantCrmPanelManage,
            selected: toolsOpen,
            onTap: onToggleTools,
          ),
        ],
      ),
    );
  }
}

/// 工具条(`cu-toolbar`):更多筛选 / 批量标签 / 合规触达。
///
/// 「导出」在导航栏(#71),不在这里重复。
class CrmToolsRow extends StatelessWidget {
  const CrmToolsRow({
    super.key,
    required this.filterOpen,
    required this.onToggleFilters,
    required this.canSegment,
    required this.selecting,
    required this.onToggleSelecting,
    required this.canMarket,
    required this.campaignOpen,
    required this.onToggleCampaign,
  });

  final bool filterOpen;
  final VoidCallback onToggleFilters;
  final bool canSegment;
  final bool selecting;
  final VoidCallback onToggleSelecting;
  final bool canMarket;
  final bool campaignOpen;
  final VoidCallback onToggleCampaign;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CyTokens.space2,
      runSpacing: CyTokens.space2,
      children: <Widget>[
        CrmPillButton(
          label: filterOpen ? stringsOf(context).merchantCrmPanelCloseFilters : stringsOf(context).merchantCrmPanelFilters,
          onTap: onToggleFilters,
        ),
        if (canSegment)
          CrmPillButton(
            label: selecting ? stringsOf(context).merchantCrmPanelCancelBatch : stringsOf(context).merchantCrmPanelBatch,
            onTap: onToggleSelecting,
          ),
        if (canMarket)
          CrmPillButton(
            label: campaignOpen ? stringsOf(context).merchantCrmPanelCloseCampaign : stringsOf(context).merchantCrmPanelCampaign,
            primary: true,
            onTap: onToggleCampaign,
          ),
      ],
    );
  }
}

/// 工具条里的小胶囊按钮。命中区 44pt(A1/L9)。
class CrmPillButton extends StatelessWidget {
  const CrmPillButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final Color bg = primary ? p.brand : p.bgSurface;
    final Color fg = primary ? p.textInverse : p.textPrimary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: loading ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: primary ? null : Border.all(color: p.borderSubtle),
        ),
        child: loading
            ? const CupertinoActivityIndicator(radius: 8)
            : Text(
                label,
                style: CyType.footnote.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// 筛选面板(`cu-filter`)。
class CrmFilterPanel extends StatelessWidget {
  const CrmFilterPanel({
    super.key,
    required this.sourceType,
    required this.onSourceTap,
    required this.sourceStart,
    required this.sourceEnd,
    required this.onPickStart,
    required this.onPickEnd,
    required this.availableTags,
    required this.tagId,
    required this.onTagTap,
    required this.onClearFilters,
    required this.canSegment,
    required this.segmentName,
    required this.segmentSaving,
    required this.onSaveSegment,
    required this.savedSegments,
    required this.onApplySegment,
    required this.savedSegmentsError,
    required this.onRetrySavedSegments,
  });

  final int? sourceType;
  final ValueChanged<int?> onSourceTap;
  final String? sourceStart;
  final String? sourceEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final List<CrmAvailableTag> availableTags;
  final int? tagId;
  final ValueChanged<int?> onTagTap;
  final VoidCallback onClearFilters;
  final bool canSegment;
  final TextEditingController segmentName;
  final bool segmentSaving;
  final VoidCallback onSaveSegment;
  final List<CrmSavedSegment> savedSegments;
  final ValueChanged<CrmSavedSegment> onApplySegment;
  final String savedSegmentsError;
  final VoidCallback onRetrySavedSegments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CrmPanelLabel(stringsOf(context).merchantCrmPanelSource),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            CyChip(
              label: stringsOf(context).merchantCrmPanelAll,
              selected: sourceType == null,
              onTap: () => onSourceTap(null),
            ),
            CyChip(
              label: stringsOf(context).merchantCrmPanelTheme,
              selected: sourceType == 1,
              onTap: () => onSourceTap(1),
            ),
            CyChip(
              label: stringsOf(context).merchantCrmPanelActivity,
              selected: sourceType == 2,
              onTap: () => onSourceTap(2),
            ),
          ],
        ),
        CrmPanelLabel(stringsOf(context).merchantCrmPanelSourceTime),
        Row(
          children: <Widget>[
            Expanded(
              child: CrmDateField(
                value: sourceStart,
                placeholder: stringsOf(context).merchantCrmPanelStart,
                onTap: onPickStart,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              child: Text(
                stringsOf(context).merchantCrmPanelTo,
                style: CyType.footnote.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
            Expanded(
              child: CrmDateField(
                value: sourceEnd,
                placeholder: stringsOf(context).merchantCrmPanelEnd,
                onTap: onPickEnd,
              ),
            ),
          ],
        ),
        if (availableTags.isNotEmpty) ...<Widget>[
          CrmPanelLabel(stringsOf(context).merchantCrmPanelTags),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: CyTokens.space2),
                  child: CyChip(
                    label: stringsOf(context).merchantCrmPanelAllTags,
                    selected: tagId == null,
                    onTap: () => onTagTap(null),
                  ),
                ),
                for (final CrmAvailableTag tag in availableTags)
                  Padding(
                    padding: const EdgeInsets.only(right: CyTokens.space2),
                    child: CyChip(
                      label: tag.tagName,
                      selected: tagId == tag.id,
                      onTap: () => onTagTap(tag.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space3),
        Align(
          alignment: Alignment.centerLeft,
          child: CrmPillButton(label: stringsOf(context).merchantCrmPanelClear, onTap: onClearFilters),
        ),
        if (canSegment) ...<Widget>[
          CrmPanelLabel(stringsOf(context).merchantCrmPanelSaveSegment),
          Row(
            children: <Widget>[
              Expanded(
                child: CrmTextField(
                  controller: segmentName,
                  placeholder: stringsOf(context).merchantCrmPanelNameFilter,
                  maxLength: 30,
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              CrmPillButton(
                label: stringsOf(context).merchantCrmPanelSaveSegment,
                primary: true,
                loading: segmentSaving,
                onTap: segmentSaving ? null : onSaveSegment,
              ),
            ],
          ),
        ],
        if (savedSegments.isNotEmpty) ...<Widget>[
          CrmPanelLabel(stringsOf(context).merchantCrmPanelSegments),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final CrmSavedSegment segment in savedSegments)
                  Padding(
                    padding: const EdgeInsets.only(right: CyTokens.space2),
                    child: CyChip(
                      label: merchantCrmSegmentName(context, segment),
                      selected: false,
                      onTap: () => onApplySegment(segment),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (savedSegmentsError.isNotEmpty)
          CrmInlineError(
            title: stringsOf(context).merchantCrmPanelSegmentsError,
            sub: savedSegmentsError,
            onAction: onRetrySavedSegments,
          ),
      ],
    );
  }
}

/// 只读日期字段(`cy-date-field` 的 App 对应):点一下弹系统日期选择器。
class CrmDateField extends StatelessWidget {
  const CrmDateField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool filled = value != null && value!.isNotEmpty;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: filled ? p.inputBgFilled : p.inputBgEmpty,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Text(
          filled ? value! : placeholder,
          style: CyType.footnote.copyWith(
            color: filled ? p.textPrimary : p.inputPlaceholder,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 面板里的单行输入框。
class CrmTextField extends StatelessWidget {
  const CrmTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.maxLength,
  });

  final TextEditingController controller;
  final String placeholder;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      decoration: BoxDecoration(
        color: p.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      alignment: Alignment.centerLeft,
      child: CupertinoTextField(
        controller: controller,
        // 硬截断(快照 `maxlength`),不是软计数 —— 计数行会顶乱版面。
        inputFormatters: <TextInputFormatter>[
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        placeholder: placeholder,
        placeholderStyle: CyType.footnote.copyWith(color: p.inputPlaceholder),
        style: CyType.footnote.copyWith(color: p.textPrimary),
        decoration: const BoxDecoration(),
      ),
    );
  }
}

/// 多行输入(触达内容)。
class CrmTextArea extends StatelessWidget {
  const CrmTextArea({
    super.key,
    required this.controller,
    required this.placeholder,
    this.maxLength,
  });

  final TextEditingController controller;
  final String placeholder;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: p.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: CupertinoTextField(
        controller: controller,
        inputFormatters: <TextInputFormatter>[
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        minLines: 3,
        maxLines: 6,
        placeholder: placeholder,
        placeholderStyle: CyType.footnote.copyWith(color: p.inputPlaceholder),
        style: CyType.footnote.copyWith(color: p.textPrimary),
        decoration: const BoxDecoration(),
      ),
    );
  }
}

/// 批量标签条(`cu-batch`)。
class CrmBatchBar extends StatelessWidget {
  const CrmBatchBar({
    super.key,
    required this.selectedCount,
    required this.tagName,
    required this.submitting,
    required this.onSubmit,
    required this.error,
  });

  final int selectedCount;
  final TextEditingController tagName;
  final bool submitting;
  final VoidCallback onSubmit;
  final String error;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stringsOf(context).merchantCrmPanelSelectionCount(selectedCount, kCrmBatchTagLimit),
          style: CyType.footnote.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space2),
        Row(
          children: <Widget>[
            Expanded(
              child: CrmTextField(
                controller: tagName,
                placeholder: stringsOf(context).merchantCrmPanelTagHint,
                maxLength: 16,
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            CrmPillButton(
              label: stringsOf(context).merchantCrmPanelAdd,
              primary: true,
              loading: submitting,
              onTap: submitting ? null : onSubmit,
            ),
          ],
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space1),
            child: Text(
              error,
              style: CyType.caption1.copyWith(color: p.statusDanger),
            ),
          ),
      ],
    );
  }
}

/// 合规触达面板(`cu-campaign`)。
class CrmCampaignPanel extends StatelessWidget {
  const CrmCampaignPanel({
    super.key,
    required this.canCoupon,
    required this.channel,
    required this.onChannelTap,
    required this.notificationDeliveryStatus,
    required this.couponDeliveryStatus,
    required this.segmentName,
    required this.onPickSegment,
    required this.savedSegmentsError,
    required this.onRetrySavedSegments,
    required this.couponName,
    required this.onPickCoupon,
    required this.couponCatalogError,
    required this.onRetryCoupons,
    required this.title,
    required this.content,
    required this.previewing,
    required this.sending,
    required this.onPreview,
    required this.onSend,
    required this.preview,
    required this.error,
    required this.task,
    required this.campaigns,
    required this.onOpenCampaign,
    required this.onRetryTask,
  });

  final bool canCoupon;
  final String channel;
  final ValueChanged<String> onChannelTap;
  final String notificationDeliveryStatus;
  final String couponDeliveryStatus;
  final String segmentName;
  final VoidCallback onPickSegment;
  final String savedSegmentsError;
  final VoidCallback onRetrySavedSegments;
  final String couponName;
  final VoidCallback onPickCoupon;
  final String couponCatalogError;
  final VoidCallback onRetryCoupons;
  final TextEditingController title;
  final TextEditingController content;
  final bool previewing;
  final bool sending;
  final VoidCallback onPreview;
  final VoidCallback onSend;
  final CrmCampaignPreview? preview;
  final String error;
  final CrmCampaignTask? task;
  final List<CrmCampaignTask> campaigns;
  final ValueChanged<CrmCampaignTask> onOpenCampaign;
  final VoidCallback onRetryTask;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool busy = previewing || sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          stringsOf(context).merchantCrmPanelCampaignTitle,
          style: CyType.headline.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          stringsOf(context).merchantCrmPolicyConsent,
          style: CyType.caption1.copyWith(color: p.textSecondary),
        ),
        if (notificationDeliveryStatus.isNotEmpty ||
            couponDeliveryStatus.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            stringsOf(context).merchantCrmResidualDeliveryChannels(merchantCrmDeliveryPolicy(context, notificationDeliveryStatus), merchantCrmDeliveryPolicy(context, couponDeliveryStatus)),
            style: CyType.caption1.copyWith(color: p.textTertiary),
          ),
        ],
        CrmPanelLabel(stringsOf(context).merchantCrmPanelChannel),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            CyChip(
              label: stringsOf(context).merchantCrmPanelInAppChannel,
              selected: channel == 'IN_APP',
              onTap: () => onChannelTap('IN_APP'),
            ),
            if (canCoupon)
              CyChip(
                label: stringsOf(context).merchantCrmPanelCouponChannel,
                selected: channel == 'COUPON',
                onTap: () => onChannelTap('COUPON'),
              ),
          ],
        ),
        CrmPanelLabel(stringsOf(context).merchantCrmPanelSaveSegment),
        CrmPickerRow(
          value: segmentName.isEmpty ? stringsOf(context).merchantCrmPanelSegmentHint : segmentName,
          enabled: !busy,
          onTap: onPickSegment,
        ),
        // 快照 `cu-inline-error`:分群读失败时筛选面板与触达面板都要说
        // (`savedSegmentsError && (filterOpen || campaignOpen)`)——
        // 触达选出的分群正是这一份,读不到还让用户干点一个空选择器最坏。
        if (savedSegmentsError.isNotEmpty)
          CrmInlineError(
            title: stringsOf(context).merchantCrmPanelSegmentsError,
            sub: savedSegmentsError,
            onAction: onRetrySavedSegments,
          ),
        if (channel == 'COUPON') ...<Widget>[
          CrmPanelLabel(stringsOf(context).merchantCrmPanelCoupons),
          CrmPickerRow(
            value: couponName.isEmpty ? stringsOf(context).merchantCrmPanelCouponEmpty : couponName,
            enabled: !busy,
            onTap: onPickCoupon,
          ),
          if (couponCatalogError.isNotEmpty)
            CrmInlineError(
              title: stringsOf(context).merchantCrmPanelCouponError,
              sub: couponCatalogError,
              onAction: onRetryCoupons,
            ),
        ],
        CrmPanelLabel(stringsOf(context).merchantCrmPanelTitle),
        CrmTextField(
          controller: title,
          placeholder: stringsOf(context).merchantCrmPanelTitle,
          maxLength: 60,
        ),
        CrmPanelLabel(stringsOf(context).merchantCrmPanelContent),
        CrmTextArea(
          controller: content,
          placeholder: stringsOf(context).merchantCrmPanelContentHint,
          maxLength: 500,
        ),
        const SizedBox(height: CyTokens.space3),
        Wrap(
          spacing: CyTokens.space2,
          runSpacing: CyTokens.space2,
          children: <Widget>[
            CrmPillButton(
              label: stringsOf(context).merchantCrmPanelPreviewCount,
              loading: previewing,
              onTap: busy ? null : onPreview,
            ),
            CrmPillButton(
              label: stringsOf(context).merchantCrmPanelCreateSend,
              primary: true,
              loading: sending,
              onTap: busy ? null : onSend,
            ),
          ],
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              error,
              style: CyType.caption1.copyWith(color: p.statusDanger),
            ),
          ),
        if (preview != null) _previewBlock(context, preview!),
        if (task != null) _resultBlock(context, task!, saving: sending),
        if (campaigns.isNotEmpty) _historyBlock(context),
      ],
    );
  }

  Widget _previewBlock(BuildContext context, CrmCampaignPreview value) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            stringsOf(context).merchantCrmPanelSegmentCount(value.totalCount, value.recipientLimit),
            style: CyType.footnote.copyWith(color: p.textSecondary),
          ),
          Text(
            stringsOf(context).merchantCrmPanelConsentedCount(value.consentedCount, value.frequencyLimitedCount),
            style: CyType.footnote.copyWith(color: p.textSecondary),
          ),
          Text(
            stringsOf(context).merchantCrmPanelReachableCount(value.deliverableCount),
            style: CyType.footnote.copyWith(color: p.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _resultBlock(
    BuildContext context,
    CrmCampaignTask value, {
    required bool saving,
  }) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            merchantCrmCampaignStatus(context, value),
            style: CyType.headline.copyWith(color: p.textPrimary),
          ),
          Text(
            stringsOf(context).merchantCrmPanelDeliveredCount(value.deliveredCount, value.noConsentCount),
            style: CyType.footnote.copyWith(color: p.textSecondary),
          ),
          Text(
            stringsOf(context).merchantCrmPanelFailureCount(value.frequencySkippedCount, value.failedCount),
            style: CyType.footnote.copyWith(color: p.textSecondary),
          ),
          if (value.isPartialFailed && value.retryableCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: CrmPillButton(
                label: stringsOf(context).merchantCrmPanelRetryCount(value.retryableCount),
                loading: saving,
                onTap: saving ? null : onRetryTask,
              ),
            ),
          for (final CrmCampaignRecipient receipt in value.recipients)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    receipt.hasNameFallback ? stringsOf(context).merchantCrmUnnamed : receipt.customerName,
                    style: CyType.footnote.copyWith(color: p.textPrimary),
                  ),
                  Text(
                    merchantCrmRecipientStatus(context, receipt),
                    style: CyType.caption1.copyWith(color: p.textSecondary),
                  ),
                  if (receipt.messageReceiptId != null)
                    Text(
                      stringsOf(context).merchantCrmPanelMessageReceipt(receipt.messageReceiptId!),
                      style: CyType.caption1.copyWith(color: p.textTertiary),
                    ),
                  if (receipt.couponHistoryId != null)
                    Text(
                      stringsOf(context).merchantCrmPanelCouponReceipt(receipt.couponHistoryId!),
                      style: CyType.caption1.copyWith(color: p.textTertiary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyBlock(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CrmPanelLabel(stringsOf(context).merchantCrmPanelRecent),
        for (final CrmCampaignTask item in campaigns)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => onOpenCampaign(item),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      merchantCrmCampaignTitle(context, item),
                      style: CyType.footnote.copyWith(color: p.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${item.deliveredCount} / ${item.recipientCount}',
                    style: CyType.footnote.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(width: CyTokens.space1),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: p.textTertiary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 单选行(保存分群 / 优惠券下拉的 App 形态):点一下弹选择半屏。
class CrmPickerRow extends StatelessWidget {
  const CrmPickerRow({
    super.key,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        decoration: BoxDecoration(
          color: p.inputBgEmpty,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value,
                style: CyType.footnote.copyWith(color: p.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择半屏的一个选项。
class CrmPickerOption {
  const CrmPickerOption({required this.id, required this.label, this.subtitle});

  final int id;
  final String label;
  final String? subtitle;
}

/// 选择半屏(短列表)。返回选中的 id;下滑/取消返回 null。
///
/// ⚠️ `showCupertinoSheet` 把半屏挂在 **rootNavigator** 上(Flutter `sheet.dart`
///   里的 `Navigator.of(context, rootNavigator: true)`),而「商家 = 恒浅」是
///   **路由层**那层 Theme(`app_router` 的 `_merchantLight`)—— 半屏是路由页的
///   **兄弟节点**,拿不到它,`CyPalette.of` 于是掉到根主题 `AppTheme.dark()`,
///   恒浅商家页上弹出一块黑面板(实测底色 = 纯黑,见
///   `test/feature/merchant/merchant_crm_sheet_theme_test.dart`)。仓里已有同类
///   坑的登记:`test/light_pages_no_static_colors_test.dart` 头注释的
///   publish_chooser_sheet。这里把**宿主页那层 Theme** 原样带进半屏。
Future<int?> showCrmPickerSheet(
  BuildContext context, {
  required String title,
  required List<CrmPickerOption> options,
  int? selectedId,
}) {
  final ThemeData hostTheme = Theme.of(context);
  return showCupertinoSheet<int>(
    context: context,
    showDragHandle: true,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        Theme(
          data: hostTheme,
          child: _CrmPickerSheet(
            title: title,
            options: options,
            selectedId: selectedId,
            controller: controller,
          ),
        ),
  );
}

class _CrmPickerSheet extends StatelessWidget {
  const _CrmPickerSheet({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.controller,
  });

  final String title;
  final List<CrmPickerOption> options;
  final int? selectedId;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Material(
      color: p.bgPage,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: CyTokens.space6),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(CyTokens.space4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: CyType.headline.copyWith(color: p.textPrimary),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.pageX,
                  vertical: CyTokens.space4,
                ),
                child: Text(
                  stringsOf(context).merchantCrmPanelOptionsEmpty,
                  textAlign: TextAlign.center,
                  style: CyType.footnote.copyWith(color: p.textSecondary),
                ),
              ),
            for (final CrmPickerOption option in options)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => Navigator.of(context).pop(option.id),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.pageX,
                    vertical: CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              option.label,
                              style: CyType.body.copyWith(
                                color: p.textPrimary,
                              ),
                            ),
                            if (option.subtitle != null)
                              Text(
                                option.subtitle!,
                                style: CyType.caption1.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (option.id == selectedId)
                        Icon(
                          CupertinoIcons.check_mark,
                          size: 18,
                          color: p.brand,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 定向广播的半屏(快照 `cu-cast`,`index.wxml:243-293` + `index.js:609-830`)。
///
/// ★ 人数、同意、频控、日限**全由服务端重算**:草稿期只给「按当前筛选估的」,
///   点发送先打一次 preview 换真值,再二次确认才真发 —— 没有「一点就发」。
/// ★ 草稿保护走仓里的 `UnsavedGuard`(快照 `onCastRequestClose`):写了一半
///   下滑/返回不能静默丢掉。按门禁 `unsaved_guard_sheet_contract_test.dart`
///   的口径,守卫在场 ⇒ 这个 sheet 不许能拖。
Future<void> showCrmBroadcastSheet(
  BuildContext context, {
  required int castCount,
  required List<CrmCustomerRow> rows,
  required CrmCustomerQuery query,
}) {
  // ★ 商家恒浅:sheet 挂在 rootNavigator 上,拿不到路由层那层浅色 Theme
  //   (`merchant_crm_sheet_theme_test.dart` 记的同一个坑),把宿主主题带过去。
  final ThemeData hostTheme = Theme.of(context);
  return showCyNativeSheet<void>(
    context,
    detents: CyNativeSheetDetents.large,
    dismissible: false,
    grabber: false,
    builder: (BuildContext context) => Theme(
      data: hostTheme,
      child: CrmBroadcastSheet(castCount: castCount, rows: rows, query: query),
    ),
  );
}

/// 广播范围的一档分组(就地从已加载的名单行聚合,快照 `buildCastGroups`)。
class CrmCastGroup {
  CrmCastGroup({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  final int count;
  bool picked = false;
}

class CrmBroadcastSheet extends ConsumerStatefulWidget {
  const CrmBroadcastSheet({
    super.key,
    required this.castCount,
    required this.rows,
    required this.query,
  });

  /// 当前筛选命中的人数(服务端 total)。
  final int castCount;

  /// 已加载的名单行 —— 人数与列表所见一致,不会「预览 8 人实际发了 30 人」。
  final List<CrmCustomerRow> rows;

  /// 与客户名册同源的筛选。
  final CrmCustomerQuery query;

  @override
  ConsumerState<CrmBroadcastSheet> createState() => _CrmBroadcastSheetState();
}

class _CrmBroadcastSheetState extends ConsumerState<CrmBroadcastSheet> {
  String _scope = 'all';
  List<CrmCastGroup> _groups = <CrmCastGroup>[];
  final TextEditingController _text = TextEditingController();
  int _targetCount = 0;
  String _previewText = '';
  bool _hasServerPreview = false;
  CrmBroadcastResult? _result;
  String _error = '';
  bool _sending = false;
  String? _requestId;

  @override
  void initState() {
    super.initState();
    _targetCount = widget.castCount;
    _previewText = crmCastEstimateText(widget.castCount);
    _text.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onDraftChanged);
    _text.dispose();
    super.dispose();
  }

  /// 草稿一变就换一份请求 id:同一份草稿重试才复用同一个 id(服务端幂等)。
  void _onDraftChanged() => setState(() {
    _requestId = null;
    _error = '';
  });

  String get _displayPreviewText {
    if (_hasServerPreview) return _previewText;
    if (_scope == 'all') return stringsOf(context).merchantCrmResidualEstimate(widget.castCount);
    final count = _groups.where((group) => group.picked).length;
    if (count == 0) return stringsOf(context).merchantCrmResidualNotSelected;
    return _scope == 'team' ? stringsOf(context).merchantCrmResidualTeamEstimate(_targetCount, count) : stringsOf(context).merchantCrmResidualRoleEstimate(_targetCount, count);
  }

  bool get _dirty => _result == null && _text.text.trim().isNotEmpty;

  void _onScope(String scope) {
    if (scope == _scope) return;
    _requestId = null;
    setState(() {
      _scope = scope;
      _groups = scope == 'all' ? <CrmCastGroup>[] : _buildGroups(scope);
      _error = '';
    });
    _refreshEstimate();
  }

  void _toggleGroup(String id) {
    _requestId = null;
    setState(() {
      for (final CrmCastGroup group in _groups) {
        if (group.id == id) group.picked = !group.picked;
      }
      _error = '';
    });
    _refreshEstimate();
  }

  /// 分组就地从 rows 聚合(快照 `buildCastGroups`):后端只在客户行上给
  /// `teamName` / `roleName`,没进过队或不带角色的客户不进任何分组,不补 0。
  List<CrmCastGroup> _buildGroups(String scope) {
    final Map<String, int> bucket = <String, int>{};
    for (final CrmCustomerRow row in widget.rows) {
      final String? name = scope == 'team' ? row.teamName : row.roleName;
      if (name == null || name.isEmpty) continue;
      bucket[name] = (bucket[name] ?? 0) + 1;
    }
    return <CrmCastGroup>[
      for (final MapEntry<String, int> entry in bucket.entries)
        CrmCastGroup(
          id: '$scope:${entry.key}',
          name: entry.key,
          count: entry.value,
        ),
    ];
  }

  /// 本地估算文案(快照 `refreshCastPreview`)。真值由服务端预览给。
  void _refreshEstimate() {
    _hasServerPreview = false;
    if (_scope == 'all') {
      setState(() {
        _targetCount = widget.castCount;
        _previewText = crmCastEstimateText(widget.castCount);
      });
      return;
    }
    final List<CrmCastGroup> picked = _groups
        .where((CrmCastGroup g) => g.picked)
        .toList(growable: false);
    final int count = picked.fold(
      0,
      (int sum, CrmCastGroup g) => sum + g.count,
    );
    final String unit = _scope == 'team' ? '队' : '类角色';
    setState(() {
      _targetCount = count;
      _previewText = picked.isEmpty
          ? '还没选'
          : '$count 人 · ${picked.length} $unit · 点发送先核一遍';
    });
  }

  CrmBroadcastPayload _payload() => CrmBroadcastPayload(
    keyword: widget.query.keyword,
    segment: widget.query.segment,
    tagId: widget.query.tagId,
    sourceType: widget.query.sourceType,
    sourceStart: widget.query.sourceStart,
    sourceEnd: widget.query.sourceEnd,
    scope: _scope == 'team' ? 'TEAM' : (_scope == 'role' ? 'ROLE' : 'ALL'),
    groups: <String>[
      for (final CrmCastGroup group in _groups)
        if (group.picked) group.name,
    ],
  );

  /// 真实顺序:服务端预览(同意/频控/日限按服务端真值)→ 确认弹窗 → 真发送。
  /// 预览没出结果不弹确认;确认框说清「发给谁、谁会收不到」。
  Future<void> _send() async {
    final String content = _text.text.trim();
    if (content.isEmpty || _targetCount <= 0 || _sending || _result != null) {
      return;
    }
    final CrmBroadcastPayload payload = _payload();
    setState(() {
      _sending = true;
      _error = '';
    });
    final CrmBroadcastPreview preview;
    try {
      preview = await ref
          .read(merchantCrmConsoleApiProvider)
          .previewBroadcast(payload);
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = merchantCrmErrorText(context, e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _previewText = merchantCrmBroadcastPreviewText(context, preview);
      _hasServerPreview = true;
    });
    if (crmBroadcastDailyExhausted(preview)) {
      await cyConfirm(
        context,
        title: stringsOf(context).merchantCrmPanelDailyLimit,
        content:
            stringsOf(context).merchantCrmPolicyDailyLimit(preview.merchantDailyLimit),
        confirmText: stringsOf(context).merchantCrmPanelGotIt,
        showCancel: false,
      );
      return;
    }
    if (preview.deliverableCount <= 0) {
      await cyConfirm(
        context,
        title: stringsOf(context).merchantCrmPanelUnreachable,
        content: _previewText,
        confirmText: stringsOf(context).merchantCrmPanelGotIt,
        showCancel: false,
      );
      return;
    }
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).merchantCrmPanelConfirmSend,
      content: stringsOf(context).merchantCrmPolicyIrreversible(_previewText),
      confirmText: stringsOf(context).merchantCrmPanelSend,
      cancelText: stringsOf(context).merchantCrmPanelReconsider,
    );
    if (!confirmed || !mounted) return;
    await _sendConfirmed(payload, content);
  }

  /// requestId 在草稿变化时重置(见 `_onDraftChanged`),同一份草稿重试复用
  /// 同一个 id —— 网络抖动重发不会多发一条。
  Future<void> _sendConfirmed(
    CrmBroadcastPayload payload,
    String content,
  ) async {
    if (_sending || _result != null) return;
    _requestId ??= newCrmRequestId('broadcast');
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final CrmBroadcastResult result = await ref
          .read(merchantCrmConsoleApiProvider)
          .sendBroadcast(payload, content: content, requestId: _requestId!);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _result = result;
        _requestId = null;
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = merchantCrmErrorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool canSend =
        _text.text.trim().isNotEmpty && _targetCount > 0 && !_sending;
    return CupertinoPageScaffold(
      // 原生承载时透明,透出系统 sheet 背景(S3)。
      backgroundColor: isCyNativeSheet(context) ? Colors.transparent : p.bgPage,
      child: UnsavedGuard(
        isDirty: () => _dirty,
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              _header(p),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    0,
                    CyTokens.pageX,
                    CyTokens.space3,
                  ),
                  children: <Widget>[
                    Wrap(
                      spacing: CyTokens.space2,
                      runSpacing: CyTokens.space2,
                      children: <Widget>[
                        CyChip(
                          label: stringsOf(context).merchantCrmPanelAll,
                          selected: _scope == 'all',
                          onTap: _sending ? null : () => _onScope('all'),
                        ),
                        CyChip(
                          label: stringsOf(context).merchantCrmPanelTeams,
                          selected: _scope == 'team',
                          onTap: _sending ? null : () => _onScope('team'),
                        ),
                        CyChip(
                          label: stringsOf(context).merchantCrmPanelRoles,
                          selected: _scope == 'role',
                          onTap: _sending ? null : () => _onScope('role'),
                        ),
                      ],
                    ),
                    if (_scope != 'all') ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      if (_groups.isEmpty)
                        _emptyGroups(p)
                      else
                        CrmPanelCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: <Widget>[
                              for (final CrmCastGroup group in _groups)
                                _groupRow(p, group),
                            ],
                          ),
                        ),
                    ],
                    CrmPanelLabel(stringsOf(context).merchantCrmPanelInAppContent),
                    CrmTextArea(
                      controller: _text,
                      placeholder: stringsOf(context).merchantCrmPanelBroadcastHint,
                      maxLength: 120,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space1),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_text.text.length}/120',
                          style: CyType.caption1.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: CyTokens.space2),
                    CrmPanelCard(
                      padding: const EdgeInsets.all(CyTokens.space2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            stringsOf(context).merchantCrmPanelPreview,
                            style: CyType.footnote.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(width: CyTokens.space2),
                          Expanded(
                            child: Text(
                              _displayPreviewText,
                              textAlign: TextAlign.right,
                              style: CyType.caption1.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space2),
                        child: Text(
                          _error,
                          style: CyType.caption1.copyWith(
                            color: p.statusDanger,
                          ),
                        ),
                      ),
                    if (_result != null) _resultBlock(p, _result!),
                  ],
                ),
              ),
              _footer(p, canSend),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(CyPalette p) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.space2,
      CyTokens.space2,
      CyTokens.space2,
      0,
    ),
    child: Row(
      children: <Widget>[
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          // maybePop 走守卫:写了内容才会拦一次(快照 `onCastRequestClose`)。
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(stringsOf(context).merchantCrmPanelCancel, style: CyType.footnote.copyWith(color: p.brand)),
        ),
        Expanded(
          child: Text(
            stringsOf(context).merchantCrmPanelBroadcast,
            textAlign: TextAlign.center,
            style: CyType.headline.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(width: 44),
      ],
    ),
  );

  Widget _groupRow(CyPalette p, CrmCastGroup group) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: _sending ? null : () => _toggleGroup(group.id),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space3,
        vertical: CyTokens.space2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.name,
                  style: CyType.footnote.copyWith(color: p.textPrimary),
                ),
                Text(
                  stringsOf(context).merchantCrmPanelGroupCount(group.count),
                  style: CyType.caption1.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            group.picked ? stringsOf(context).merchantCrmPanelSelected : stringsOf(context).merchantCrmPanelSelect,
            style: CyType.footnote.copyWith(
              color: group.picked ? p.brand : p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyGroups(CyPalette p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
    child: Column(
      children: <Widget>[
        Text(
          _scope == 'team' ? stringsOf(context).merchantCrmPanelNoTeams : stringsOf(context).merchantCrmPanelNoRoles,
          style: CyType.headline.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          _scope == 'team'
              ? stringsOf(context).merchantCrmPanelNoTeamsHint
              : stringsOf(context).merchantCrmPanelNoRolesHint,
          textAlign: TextAlign.center,
          style: CyType.caption1.copyWith(color: p.textSecondary),
        ),
      ],
    ),
  );

  /// 发送结果**只认服务端回执**:发了几人、跳过几人及原因都来自服务端留痕。
  Widget _resultBlock(CyPalette p, CrmBroadcastResult result) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space3),
    child: CrmPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            merchantCrmBroadcastStatus(context, result),
            style: CyType.headline.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            stringsOf(context).merchantCrmResidualDelivered(result.deliveredCount, result.noConsentCount),
            style: CyType.caption1.copyWith(color: p.textSecondary),
          ),
          Text(
            stringsOf(context).merchantCrmResidualSkipped(result.frequencySkippedCount, result.failedCount),
            style: CyType.caption1.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            stringsOf(context).merchantCrmPolicyDeliveryRecord,
            style: CyType.caption1.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    ),
  );

  Widget _footer(CyPalette p, bool canSend) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.pageX,
      CyTokens.space2,
      CyTokens.pageX,
      CyTokens.space2,
    ),
    child: _result != null
        ? CrmPillButton(
            label: stringsOf(context).merchantCrmPanelDone,
            primary: true,
            onTap: () => Navigator.of(context).pop(),
          )
        : CrmPillButton(
            label: stringsOf(context).merchantCrmPanelSend,
            primary: true,
            loading: _sending,
            onTap: canSend ? _send : null,
          ),
  );
}
