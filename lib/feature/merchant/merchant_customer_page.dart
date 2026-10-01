import '../../l10n/strings.dart';
import 'merchant_crm_strings.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_crm_console_api.dart';
import '../../data/models/merchant_crm_console.dart';
import '../../data/models/merchant_crm_export.dart';
import 'merchant_crm_panels.dart';

/// CRM 运营台的能力位(`/api/merchant/access/me` 归一化产物)。
///
/// ★ 面板与按钮的显隐全读它,不在客户端自己推 —— 猜错摆出来的入口
///   点下去必被后端拒(小程序 `loadAccess` 同口径)。
class MerchantCrmAccess {
  const MerchantCrmAccess({
    this.active = false,
    this.canReadCrm = false,
    this.canSegmentCrm = false,
    this.canExportCrm = false,
    this.canWriteMarketing = false,
    this.canManageCoupons = false,
  });

  final bool active;
  final bool canReadCrm;
  final bool canSegmentCrm;
  final bool canExportCrm;
  final bool canWriteMarketing;
  final bool canManageCoupons;

  factory MerchantCrmAccess.fromJson(Map<String, dynamic> json) {
    return MerchantCrmAccess(
      active: json['active'] == true,
      canReadCrm: json['canReadCrm'] == true,
      canSegmentCrm: json['canSegmentCrm'] == true,
      canExportCrm: json['canExportCrm'] == true,
      canWriteMarketing: json['canWriteMarketing'] == true,
      canManageCoupons: json['canManageCoupons'] == true,
    );
  }
}

/// CRM 运营台能力位(读 `/api/merchant/access/me`)。
///
/// ⚠️ 读不到时页面按「加载失败 + 重试」处理,不静默降级成「没有能力」——
///   那会让商家以为自己的岗位真没权限。
final merchantCrmAccessProvider = FutureProvider.autoDispose<MerchantCrmAccess>(
  (ref) async {
    final Map<String, dynamic> raw = await ref
        .watch(pageParityApiProvider)
        .merchantAccess();
    return MerchantCrmAccess.fromJson(raw);
  },
);

/// 导出任务的 requestId。格式对齐小程序
/// `pages/merchant/customer/index.js:1315`(`crm-export-<36 进制时间>-<36 进制随机>`)——
/// 后端按它幂等,**重试要复用同一个值**,所以由调用方持有。
String newCrmExportRequestId() {
  final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String rand = math.Random().nextInt(0xFFFFFF).toRadixString(36);
  return 'crm-export-$stamp-$rand';
}

/// 商家客户名册 + CRM 运营台。对齐小程序 `pages/merchant/customer`。
///
/// ★ 页内分区(逐段对齐快照 index.wxml):
///   计数摘要 · 高频筛选 chips + 管理 · 搜索 · 工具条 · 筛选面板 ·
///   批量标签条 · 合规触达面板 · 导出状态条 · 客户列表。
/// ★ 「定向广播」(cu-cast)不在这里 —— 快照自己的 `sendCast` 也不发请求
///   (后端没有这个接口,只弹「还发不出去」),没接口的入口不摆。
class MerchantCustomerPage extends ConsumerStatefulWidget {
  const MerchantCustomerPage({super.key});

  @override
  ConsumerState<MerchantCustomerPage> createState() =>
      _MerchantCustomerPageState();
}

class _MerchantCustomerPageState extends ConsumerState<MerchantCustomerPage> {
  // ── 能力位与首屏
  MerchantCrmAccess? _access;
  bool _accessLoading = true;
  String _accessError = '';

  // ── 查询与列表
  /// 框里当前的字;[_filters].keyword 是已提交的搜索词,回车/防抖才同步。
  String _query = '';
  CrmCustomerQuery _filters = const CrmCustomerQuery();
  final ScrollController _scroll = ScrollController();
  List<CrmCustomerRow> _rows = <CrmCustomerRow>[];

  /// 最近一次**整页**回包。计数摘要与空态都从它取 —— 文案由模型
  /// [CrmCustomerPageData.summaryText] 给,页面不再自己拼一遍。
  CrmCustomerPageData? _data;
  List<CrmAvailableTag> _availableTags = const <CrmAvailableTag>[];
  String _couponDeliveryStatus = '';
  String _notificationDeliveryStatus = '';
  int _pageNum = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _listError = '';
  Timer? _debounce;

  /// 「换明文号码」在途标记:一次只放一个,防连点把日限额度烧掉。
  bool _contactBusy = false;

  /// 同一查询的请求令牌:A 的迟到响应不得写进 B 的列表。
  int _loadToken = 0;

  // ── 工具条 / 筛选 / 批量标签
  bool _toolsOpen = false;
  bool _filterOpen = false;
  bool _selecting = false;
  final Set<int> _selectedIds = <int>{};
  final TextEditingController _batchTagName = TextEditingController();
  bool _batchSubmitting = false;
  String _batchError = '';
  List<CrmSavedSegment> _savedSegments = const <CrmSavedSegment>[];
  String _savedSegmentsError = '';
  final TextEditingController _segmentName = TextEditingController();
  bool _segmentSaving = false;

  // ── 合规触达
  bool _campaignOpen = false;
  String _channel = 'IN_APP';
  int? _segmentId;
  String _segmentLabel = '';
  int? _couponId;
  String _couponLabel = '';
  final TextEditingController _campaignTitle = TextEditingController();
  final TextEditingController _campaignContent = TextEditingController();
  CrmCampaignPreview? _preview;
  CrmCampaignTask? _task;
  String _campaignError = '';
  bool _previewing = false;
  bool _sending = false;
  List<CrmCoupon> _coupons = const <CrmCoupon>[];
  String _couponCatalogError = '';
  List<CrmCampaignTask> _campaigns = const <CrmCampaignTask>[];

  // ── 导出脱敏客户资料(`/api/merchant/crm/exports`,#71 落地)。
  //    状态都留在这一页上:离开页面就中止轮询,回来重新发起 —— 而**不是**
  //    在后台继续轮询到天荒地老。
  MerchantCrmExportTask? _export;
  String? _exportToken;
  String? _exportError;
  bool _exporting = false;
  bool _downloading = false;
  Timer? _exportPoll;

  /// 同一个导出任务的重试要复用同一个 requestId(后端按它幂等)。
  String? _exportRequestId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _exportPoll?.cancel();
    _debounce?.cancel();
    _scroll.dispose();
    _batchTagName.dispose();
    _segmentName.dispose();
    _campaignTitle.dispose();
    _campaignContent.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────── 能力位与首屏

  /// 读能力位 → 按能力拉首屏数据。快照 `loadAccess` 的顺序照搬:
  /// 列表 → 保存分群 → 触达历史(canWriteMarketing)→ 券(canManageCoupons)。
  Future<void> _bootstrap() async {
    setState(() {
      _accessLoading = true;
      _accessError = '';
    });
    try {
      final MerchantCrmAccess access = await ref.read(
        merchantCrmAccessProvider.future,
      );
      if (!mounted) return;
      setState(() {
        _access = access;
        _accessLoading = false;
      });
      if (!access.canReadCrm) return;
      unawaited(_load());
      unawaited(_loadSavedSegments());
      if (access.canWriteMarketing) unawaited(_loadCampaigns());
      if (access.canManageCoupons) unawaited(_loadCoupons());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accessLoading = false;
        _accessError = stringsOf(context).merchantCrmAccessError;
      });
    }
  }

  void _retryAccess() {
    ref.invalidate(merchantCrmAccessProvider);
    unawaited(_bootstrap());
  }

  bool get _canRead => _access?.canReadCrm ?? false;
  bool get _canSegment => _access?.canSegmentCrm ?? false;
  bool get _canExport => _access?.canExportCrm ?? false;
  bool get _canMarket => _access?.canWriteMarketing ?? false;
  bool get _canCoupon => _access?.canManageCoupons ?? false;

  // ──────────────────────────────────────────────────── 列表

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  /// 首屏 / 换筛选:回到第一页重新取。快照 `load()`。
  Future<void> _load() async {
    if (!_canRead) return;
    final CrmCustomerQuery query = _filters;
    final int token = ++_loadToken;
    setState(() {
      _loading = true;
      _listError = '';
    });
    try {
      final CrmCustomerPageData page = await ref
          .read(merchantCrmConsoleApiProvider)
          .customers(query);
      if (!mounted || token != _loadToken || !query.sameQuery(_filters)) return;
      setState(() {
        _data = page;
        _rows = page.rows;
        _availableTags = page.availableTags;
        _couponDeliveryStatus = page.couponDeliveryStatus;
        _notificationDeliveryStatus = page.notificationDeliveryStatus;
        _pageNum = 1;
        _hasMore = page.rows.length < page.total;
        _loading = false;
        _listError = '';
        // 换查询后旧的选择不再指向屏上的行。
        _selectedIds.clear();
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _listError = merchantCrmErrorText(context, e);
        _rows = <CrmCustomerRow>[];
      });
    }
  }

  /// 触底追加下一页。快照 `loadMore()` 只在查询没变时允许。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _rows.isEmpty) return;
    final CrmCustomerQuery query = _filters.copyWith(pageNum: _pageNum + 1);
    final int token = _loadToken;
    setState(() => _loadingMore = true);
    try {
      final CrmCustomerPageData page = await ref
          .read(merchantCrmConsoleApiProvider)
          .customers(query);
      if (!mounted || token != _loadToken || !query.sameQuery(_filters)) return;
      setState(() {
        _rows = <CrmCustomerRow>[..._rows, ...page.rows];
        _pageNum = query.pageNum;
        _hasMore = _rows.length < page.total;
        _loadingMore = false;
      });
    } on MerchantCrmApiException {
      if (!mounted || token != _loadToken) return;
      // 追加失败不动已渲染的分页:屏上的还是上次确认过的数据。
      setState(() => _loadingMore = false);
    }
  }

  // ──────────────────────────────────────────────────── 搜索与筛选

  void _onKeywordInput(String value) {
    setState(() => _query = value);
    // 输入防抖(快照 300ms):每敲一个字打一次接口既浪费,回来的顺序还可能是乱的。
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilters(_filters.copyWith(keyword: value.trim()));
    });
  }

  void _onKeywordConfirm(String value) {
    _debounce?.cancel();
    _applyFilters(_filters.copyWith(keyword: value.trim()));
  }

  void _applyFilters(CrmCustomerQuery next) {
    setState(() {
      _filters = next;
      if (next.keyword.isEmpty && _query.isNotEmpty) _query = '';
    });
    unawaited(_load());
  }

  void _onSegmentTap(String key) {
    if (key == _filters.segment) return;
    _applyFilters(_filters.copyWith(segment: key));
  }

  void _onSourceTap(int? value) {
    if (value == null) {
      _applyFilters(_filters.copyWith(clearSourceType: true));
      return;
    }
    _applyFilters(_filters.copyWith(sourceType: value));
  }

  void _onTagTap(int? value) {
    if (value == null) {
      _applyFilters(_filters.copyWith(clearTagId: true));
      return;
    }
    _applyFilters(_filters.copyWith(tagId: value));
  }

  void _clearFilters() {
    // 快照 `clearFilters`:清掉分段/来源/标签/时间窗,**搜索词保持**。
    _applyFilters(CrmCustomerQuery(keyword: _filters.keyword));
  }

  Future<void> _pickSourceDate({required bool isStart}) async {
    final DateTime now = DateTime.now();
    final String? current = isStart ? _filters.sourceStart : _filters.sourceEnd;
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: DateTime.tryParse(current ?? '') ?? now,
      minimumDate: DateTime(now.year - 5),
      maximumDate: DateTime(now.year + 1, 12, 31),
      title: isStart ? stringsOf(context).merchantCrmStartDate : stringsOf(context).merchantCrmEndDate,
    );
    if (picked == null || !mounted) return;
    final String value =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _applyFilters(
      isStart
          ? _filters.copyWith(sourceStart: value)
          : _filters.copyWith(sourceEnd: value),
    );
  }

  // ──────────────────────────────────────────────────── 批量标签

  void _toggleSelecting() {
    if (!_canSegment) return;
    setState(() {
      _selecting = !_selecting;
      _selectedIds.clear();
      _batchError = '';
    });
  }

  void _toggleSelected(int memberId) {
    if (_selectedIds.contains(memberId)) {
      setState(() => _selectedIds.remove(memberId));
      return;
    }
    if (_selectedIds.length >= kCrmBatchTagLimit) {
      CyNativeNotice.show(context, stringsOf(context).merchantCrmSelectionLimit(kCrmBatchTagLimit));
      return;
    }
    setState(() => _selectedIds.add(memberId));
  }

  Future<void> _submitBatchTag() async {
    if (!_canSegment || _batchSubmitting) return;
    final String tagName = _batchTagName.text.trim();
    if (_selectedIds.isEmpty) {
      setState(() => _batchError = stringsOf(context).merchantCrmSelectCustomer);
      return;
    }
    if (tagName.isEmpty || tagName.length > 16) {
      setState(() => _batchError = stringsOf(context).merchantCrmTagLength);
      return;
    }
    setState(() {
      _batchSubmitting = true;
      _batchError = '';
    });
    try {
      await ref
          .read(merchantCrmConsoleApiProvider)
          .batchTag(
            customerMemberIds: _selectedIds.toList(growable: false),
            tagName: tagName,
            requestId: newCrmRequestId('batch-tag'),
          );
      if (!mounted) return;
      setState(() {
        _batchSubmitting = false;
        _batchTagName.clear();
        _selecting = false;
        _selectedIds.clear();
      });
      CyNativeNotice.show(context, stringsOf(context).merchantCrmTagAdded);
      unawaited(_load());
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _batchSubmitting = false;
        _batchError = merchantCrmErrorText(context, e);
      });
    }
  }

  // ──────────────────────────────────────────────────── 分群

  Future<void> _loadSavedSegments() async {
    try {
      final List<CrmSavedSegment> segments = await ref
          .read(merchantCrmConsoleApiProvider)
          .segments();
      if (!mounted) return;
      setState(() {
        _savedSegments = segments;
        _savedSegmentsError = '';
        // 触达面板的选择跟着列表走:选中的保留,否则回第一条。
        final CrmSavedSegment? selected = segments
            .where((CrmSavedSegment s) => s.id == _segmentId)
            .firstOrNull;
        final CrmSavedSegment? first = selected ?? segments.firstOrNull;
        _segmentId = first?.id;
        _segmentLabel = first == null ? '' : merchantCrmSegmentName(context, first);
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() => _savedSegmentsError = merchantCrmErrorText(context, e));
    }
  }

  Future<void> _saveSegment() async {
    if (!_canSegment || _segmentSaving) return;
    final String name = _segmentName.text.trim();
    if (name.isEmpty || name.length > 30) {
      CyNativeNotice.show(context, stringsOf(context).merchantCrmSegmentLength);
      return;
    }
    setState(() => _segmentSaving = true);
    try {
      await ref
          .read(merchantCrmConsoleApiProvider)
          .saveSegment(
            name: name,
            filter: _filters.toFilter(),
            requestId: newCrmRequestId('segment'),
          );
      if (!mounted) return;
      setState(() {
        _segmentSaving = false;
        _segmentName.clear();
      });
      CyNativeNotice.show(context, stringsOf(context).merchantCrmSegmentSaved);
      unawaited(_loadSavedSegments());
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() => _segmentSaving = false);
      CyNativeNotice.show(context, merchantCrmErrorText(context, e), isError: true);
    }
  }

  void _applySavedSegment(CrmSavedSegment segment) {
    final CrmSegmentFilter? filter = segment.filter;
    if (filter == null) return;
    _applyFilters(
      CrmCustomerQuery(
        keyword: _filters.keyword,
        segment: filter.segment ?? 'all',
        tagId: filter.tagId,
        sourceType: filter.sourceType,
        sourceStart: filter.sourceStart,
        sourceEnd: filter.sourceEnd,
      ),
    );
  }

  // ──────────────────────────────────────────────────── 合规触达

  void _toggleCampaign() {
    if (!_canMarket) return;
    setState(() {
      _campaignOpen = !_campaignOpen;
      _campaignError = '';
    });
  }

  void _onChannelTap(String channel) {
    if (channel == 'COUPON' && !_canCoupon) return;
    if (channel == _channel) return;
    setState(() {
      _channel = channel;
      _preview = null;
      _campaignError = '';
    });
  }

  Future<void> _pickCampaignSegment() async {
    final int? picked = await showCrmPickerSheet(
      context,
      title: stringsOf(context).merchantCrmChooseSegment,
      selectedId: _segmentId,
      options: <CrmPickerOption>[
        for (final CrmSavedSegment s in _savedSegments)
          CrmPickerOption(id: s.id, label: merchantCrmSegmentName(context, s)),
      ],
    );
    if (picked == null || !mounted) return;
    final CrmSavedSegment? hit = _savedSegments
        .where((CrmSavedSegment s) => s.id == picked)
        .firstOrNull;
    if (hit == null) return;
    setState(() {
      _segmentId = hit.id;
      _segmentLabel = merchantCrmSegmentName(context, hit);
      _preview = null;
      _campaignError = '';
    });
  }

  Future<void> _pickCampaignCoupon() async {
    final int? picked = await showCrmPickerSheet(
      context,
      title: stringsOf(context).merchantCrmChooseCoupon,
      selectedId: _couponId,
      options: <CrmPickerOption>[
        for (final CrmCoupon c in _coupons)
          CrmPickerOption(id: c.id, label: merchantCrmCouponName(context, c)),
      ],
    );
    if (picked == null || !mounted) return;
    final CrmCoupon? hit = _coupons
        .where((CrmCoupon c) => c.id == picked)
        .firstOrNull;
    if (hit == null) return;
    setState(() {
      _couponId = hit.id;
      _couponLabel = merchantCrmCouponName(context, hit);
      _preview = null;
      _campaignError = '';
    });
  }

  Future<void> _loadCoupons() async {
    try {
      final List<CrmCoupon> coupons = await ref
          .read(merchantCrmConsoleApiProvider)
          .coupons();
      if (!mounted) return;
      setState(() {
        _coupons = coupons;
        _couponCatalogError = '';
        final CrmCoupon? selected = coupons
            .where((CrmCoupon c) => c.id == _couponId)
            .firstOrNull;
        final CrmCoupon? first = selected ?? coupons.firstOrNull;
        _couponId = first?.id;
        _couponLabel = first == null ? '' : merchantCrmCouponName(context, first);
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() => _couponCatalogError = merchantCrmErrorText(context, e));
    }
  }

  Future<void> _loadCampaigns() async {
    try {
      final List<CrmCampaignTask> rows = await ref
          .read(merchantCrmConsoleApiProvider)
          .campaigns();
      if (!mounted) return;
      setState(() => _campaigns = rows);
    } on MerchantCrmApiException {
      // 快照同口径:刷新失败静默降级,已加载的历史留在屏上。
    }
  }

  Future<void> _previewCampaign() async {
    if (!_canMarket || _previewing || _sending) return;
    final int? segmentId = _segmentId;
    if (segmentId == null) {
      setState(() => _campaignError = stringsOf(context).merchantCrmSegmentRequired);
      return;
    }
    if (_channel == 'COUPON' && (!_canCoupon || _couponId == null)) {
      setState(() => _campaignError = stringsOf(context).merchantCrmCouponRequired);
      return;
    }
    setState(() {
      _previewing = true;
      _campaignError = '';
      _preview = null;
    });
    try {
      final CrmCampaignPreview preview = await ref
          .read(merchantCrmConsoleApiProvider)
          .previewCampaign(segmentId: segmentId, channel: _channel);
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _preview = preview;
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _campaignError = merchantCrmErrorText(context, e);
      });
    }
  }

  /// 创建 + 投放。快照 `submitCampaign` → `_dispatchCampaign` 两步。
  ///
  /// ★★ 投放前加一次二次确认(App 侧硬要求):`创建并发送` 点下去就是
  ///   给一批真人发消息,不可撤回 —— 快照没有这一步,App 补上。
  Future<void> _sendCampaign() async {
    if (!_canMarket || _sending || _previewing) return;
    final int? segmentId = _segmentId;
    final String title = _campaignTitle.text.trim();
    final String content = _campaignContent.text.trim();
    if (segmentId == null) {
      setState(() => _campaignError = stringsOf(context).merchantCrmSegmentRequired);
      return;
    }
    if (title.isEmpty || title.length > 60) {
      setState(() => _campaignError = stringsOf(context).merchantCrmCampaignTitleLength);
      return;
    }
    if (content.isEmpty || content.length > 500) {
      setState(() => _campaignError = stringsOf(context).merchantCrmCampaignContentLength);
      return;
    }
    final int? couponId = _channel == 'COUPON' ? _couponId : null;
    if (_channel == 'COUPON' && (!_canCoupon || couponId == null)) {
      setState(() => _campaignError = stringsOf(context).merchantCrmCouponRequired);
      return;
    }

    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).merchantCrmConfirmSend,
      content:
          stringsOf(context).merchantCrmPolicySegmentSend(_segmentLabel.isEmpty ? stringsOf(context).merchantCrmPolicySelectedSegment : _segmentLabel),
      confirmText: stringsOf(context).merchantCrmSend,
      danger: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _sending = true;
      _campaignError = '';
    });
    final MerchantCrmConsoleApi api = ref.read(merchantCrmConsoleApiProvider);
    try {
      final CrmCampaignTask created = await api.createCampaign(
        segmentId: segmentId,
        channel: _channel,
        couponId: couponId,
        title: title,
        content: content,
        requestId: newCrmRequestId('campaign'),
      );
      if (!mounted) return;
      setState(() => _task = created);
      final CrmCampaignTask dispatched = await api.dispatchCampaign(
        created.id!,
      );
      if (!mounted) return;
      setState(() {
        _task = dispatched;
        _sending = false;
      });
      unawaited(_loadCampaigns());
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _campaignError = merchantCrmErrorText(context, e);
      });
    }
  }

  Future<void> _retryCampaign() async {
    final CrmCampaignTask? task = _task;
    if (!_canMarket || task == null || !task.isPartialFailed) return;
    final int? campaignId = task.id;
    if (campaignId == null) return;
    setState(() {
      _sending = true;
      _campaignError = '';
    });
    try {
      final CrmCampaignTask next = await ref
          .read(merchantCrmConsoleApiProvider)
          .retryCampaign(campaignId);
      if (!mounted) return;
      setState(() {
        _task = next;
        _sending = false;
      });
      unawaited(_loadCampaigns());
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _campaignError = merchantCrmErrorText(context, e);
      });
    }
  }

  Future<void> _openCampaign(CrmCampaignTask item) async {
    final int? campaignId = item.id;
    if (campaignId == null) return;
    try {
      final CrmCampaignTask detail = await ref
          .read(merchantCrmConsoleApiProvider)
          .campaignDetail(campaignId);
      if (!mounted) return;
      setState(() {
        _task = detail;
        _campaignOpen = true;
        _campaignError = '';
      });
    } on MerchantCrmApiException catch (e) {
      if (!mounted) return;
      setState(() => _campaignError = merchantCrmErrorText(context, e));
    }
  }

  // ──────────────────────────────────────────────────── 拨号 / 复制

  /// F15:列表里的号是服务端脱敏号,拿去拨/复制一定打不通。每次联系都先向
  /// 服务端换明文(快照 index.js:734)—— 权限、归属、同意、日限与访问审计
  /// 都在那一条链上判;拿不到就落失败提示说清原因,不静默降级。
  Future<String?> _revealPhone(int memberId, String purpose) async {
    if (_contactBusy || memberId <= 0) return null;
    _contactBusy = true;
    try {
      return await ref
          .read(merchantCrmConsoleApiProvider)
          .revealContact(memberId, purpose: purpose);
    } on MerchantCrmApiException catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          stringsOf(context).merchantCrmPolicyContactPrivacy(merchantCrmErrorText(context, e)),
          isError: true,
        );
      }
      return null;
    } finally {
      _contactBusy = false;
    }
  }

  Future<void> _callCustomer(int memberId) async {
    final String? phone = await _revealPhone(memberId, 'call');
    if (phone == null || !mounted) return;
    try {
      final bool ok = await launchUrl(Uri(scheme: 'tel', path: phone));
      if (!ok && mounted) CyNativeNotice.show(context, stringsOf(context).merchantCrmDialError);
    } catch (_) {
      if (mounted) CyNativeNotice.show(context, stringsOf(context).merchantCrmDialError, isError: true);
    }
  }

  Future<void> _copyCustomerPhone(int memberId) async {
    final String? phone = await _revealPhone(memberId, 'copy');
    if (phone == null || !mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantCrmCopied);
    } catch (_) {
      if (mounted) CyNativeNotice.show(context, stringsOf(context).merchantCrmCopyError, isError: true);
    }
  }

  // ──────────────────────────────────────────────────── 导出(#71)

  void _stopExportPoll() {
    _exportPoll?.cancel();
    _exportPoll = null;
  }

  Future<void> _createExport() async {
    if (_exporting || (_export?.isRunning ?? false)) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    _stopExportPoll();
    // 重试沿用同一个 requestId:换新的 = 后端那边多出一个任务。
    final String requestId = _exportRequestId ??= newCrmExportRequestId();
    try {
      final Map<String, dynamic> data = await ref
          .read(pageParityApiProvider)
          .createCrmExport(
            requestId: requestId,
            // ★ 与小程序同参(customer/index.js:1084/1195):导出的是**当前视图**
            //   —— 关键词 + 分群/标签/来源/时间窗一个都不能少。导全量再让人
            //   自己筛是另一回事。
            query: _filters.toExportQuery(),
          );
      if (!mounted) return;
      final MerchantCrmExportTask? task = MerchantCrmExportTask.tryParse(data);
      if (task == null) {
        setState(() {
          _exportError = stringsOf(context).merchantCrmExportCreateError;
        });
        return;
      }
      setState(() {
        _export = task;
        // 下载凭证只在创建响应里出现一次,必须存住。
        _exportToken = (data['downloadToken'] as String?) ?? _exportToken;
      });
      _scheduleExportPoll();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _exportError = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 1.5 秒一拍,与小程序同节奏(customer/index.js:1141)。
  void _scheduleExportPoll() {
    _stopExportPoll();
    if (!(_export?.isRunning ?? false)) return;
    _exportPoll = Timer(const Duration(milliseconds: 1500), _pollExport);
  }

  Future<void> _pollExport() async {
    final MerchantCrmExportTask? task = _export;
    if (task == null || !task.isRunning) return;
    try {
      final Map<String, dynamic> data = await ref
          .read(pageParityApiProvider)
          .crmExportStatus(task.id);
      if (!mounted) return;
      final MerchantCrmExportTask? next = MerchantCrmExportTask.tryParse(data);
      if (next == null) {
        // ★ 这一帧读不懂就**保留上一帧**并继续问,不是把界面落到一个编造的态上。
        setState(() => _exportError = stringsOf(context).merchantCrmExportStatusError);
        _scheduleExportPoll();
        return;
      }
      setState(() {
        _export = next;
        _exportError = next.errorMessage?.trim().isNotEmpty == true
            ? next.errorMessage!.trim()
            : null;
      });
      _scheduleExportPoll();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _exportError = e.toString().replaceFirst('Exception: ', ''),
      );
      _scheduleExportPoll();
    }
  }

  /// 下载并交给系统分享面板(装机后可以「存储到文件」/AirDrop/发给同事)。
  ///
  /// ⚠️ 凭证必须走 `X-CRM-Export-Token` 头 —— 只凭登录态下载会被拒,
  ///   而拒绝发生在文件流里,外面看起来只是「下载失败」。
  Future<void> _downloadExport() async {
    final MerchantCrmExportTask? task = _export;
    final String? token = _exportToken;
    if (task == null || !task.isSuccess) return;
    if (token == null || token.isEmpty) {
      CyNativeNotice.show(context, stringsOf(context).merchantCrmExportTokenError, isError: true);
      return;
    }
    setState(() {
      _downloading = true;
      _exportError = null;
    });
    try {
      final fileName = stringsOf(context).merchantCrmExportFile(task.id);
      final Directory dir = await getTemporaryDirectory();
      final String path = '${dir.path}/$fileName';
      await ref
          .read(pageParityApiProvider)
          .downloadCrmExport(
            taskId: task.id,
            downloadToken: token,
            savePath: path,
          );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(path, mimeType: _xlsxMime)],
          subject: stringsOf(context).merchantCrmExportSubject,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final String msg = e is DioException
          ? stringsOf(context).merchantCrmDownloadError
          : e.toString().replaceFirst('Exception: ', '');
      setState(() => _exportError = msg);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 导出状态条。**没有任务时整条不渲染** —— 空着一条「导出」栏
  /// 会让人以为这里本来就有内容没加载出来。
  Widget _exportStrip() {
    final MerchantCrmExportTask? task = _export;
    final String? error = _exportError;
    if (task == null && (error == null || error.isEmpty)) {
      return const SizedBox.shrink();
    }
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      key: const Key('merchant-crm-export-strip'),
      width: double.infinity,
      margin: const EdgeInsets.only(
        top: CyTokens.space2,
        left: CyTokens.pageX,
        right: CyTokens.pageX,
      ),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            task == null ? stringsOf(context).merchantCrmExportCreateError : merchantCrmExportStatus(context, task),
            key: const Key('merchant-crm-export-status'),
            style: t.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (error != null && error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                error,
                style: t.bodySmall?.copyWith(color: p.statusWarning),
              ),
            ),
          if (task != null && (task.isSuccess || task.isExpired || task.isFailed)) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            CyNativeButton(
              key: const Key('merchant-crm-export-download'),
              label: task.isSuccess
                  ? (_downloading ? stringsOf(context).merchantCrmDownloading : stringsOf(context).merchantCrmDownload)
                  : stringsOf(context).merchantCrmRecreateExport,
              role: CyNativeButtonRole.secondary,
              loading: _downloading,
              onPressed: _downloading
                  ? null
                  : task.isSuccess
                  ? _downloadExport
                  : _createExport,
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────── 渲染

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final bool canExport = _canExport;
    return CupertinoPageScaffold(
      backgroundColor: p.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantCrmTitle),
        trailing: canExport
            ? Semantics(
                button: true,
                label: stringsOf(context).merchantCrmExportSemantics,
                child: CupertinoButton(
                  key: const Key('merchant-crm-export'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: _exporting || (_export?.isRunning ?? false)
                      ? null
                      : _createExport,
                  child: Text(
                    (_export?.isRunning ?? false) || _exporting ? stringsOf(context).merchantCrmExporting : stringsOf(context).merchantCrmExport,
                  ),
                ),
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_accessLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_accessError.isNotEmpty) {
      return StatusView(
        message: stringsOf(context).merchantCrmAccessFailed,
        sub: _accessError,
        large: true,
        onRetry: _retryAccess,
      );
    }
    if (!_canRead) {
      return StatusView(
        message: stringsOf(context).merchantCrmDenied,
        sub: stringsOf(context).merchantCrmDeniedHint,
        large: true,
      );
    }
    final CyPalette p = CyPalette.of(context);
    // ★ 工具面板(筛选 / 批量 / 触达)加起来会超过一屏 —— 触达面板带上结果与
    //   历史能到 800pt 以上。给它们一个上限、在内部滚动,而不是把列表挤成
    //   一条缝甚至整页溢出。小程序那边面板在页面流里靠页面滚动;App 这一页
    //   只有列表是滚动的,所以在这里收口。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => Column(
        children: <Widget>[
          _summaryLine(p),
          const SizedBox(height: CyTokens.space2),
          CrmSegmentChips(
            segment: _filters.segment,
            onTap: _onSegmentTap,
            toolsOpen: _toolsOpen,
            onToggleTools: () => setState(() => _toolsOpen = !_toolsOpen),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: CySearchField(
              value: _query,
              placeholder: stringsOf(context).merchantCrmSearch,
              onChanged: _onKeywordInput,
              onSubmitted: _onKeywordConfirm,
            ),
          ),
          if (_toolsOpen)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.6,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  0,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: _toolsArea(),
              ),
            ),
          if (_canExport) _exportStrip(),
          // 快照 `cu-sync`(`loading && rows.length`):刷新时屏上还有旧名单,
          // 得说一句「在读新的」,否则用户以为这就是最新一版。
          if (_loading && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                0,
                CyTokens.pageX,
                CyTokens.space1,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    stringsOf(context).merchantCrmRefreshing,
                    style: CyType.caption1.copyWith(color: p.textSecondary),
                  ),
                ),
              ),
            ),
          Expanded(child: _listArea(p)),
          if (_canMarket && _listError.isEmpty) _castBar(p),
        ],
      ),
    );
  }

  /// 定向广播入口(快照 `cu-cast` 底栏):发给**当前筛选出的这批人**,
  /// 不是全场广播 —— 商家点之前就知道发给谁。
  Widget _castBar(CyPalette p) {
    final int count = _data?.total ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: p.bgSurface,
        border: Border(top: BorderSide(color: p.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space2,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stringsOf(context).merchantCrmAudience(count),
                    style: CyType.footnote.copyWith(color: p.textPrimary),
                  ),
                  Text(
                    stringsOf(context).merchantCrmResidualAudienceHint,
                    style: CyType.caption1.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            CrmPillButton(
              key: const Key('merchant-crm-cast'),
              label: stringsOf(context).merchantCrmBroadcast,
              primary: true,
              onTap: count > 0 ? _openCast : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCast() async {
    final int count = _data?.total ?? 0;
    if (!_canMarket || count <= 0) return;
    await showCrmBroadcastSheet(
      context,
      castCount: count,
      rows: _rows,
      query: _filters,
    );
  }

  /// 工具条 + 筛选 / 批量 / 触达面板(快照 `cu-toolbar` 与三个面板)。
  Widget _toolsArea() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      CrmToolsRow(
        filterOpen: _filterOpen,
        onToggleFilters: () => setState(() => _filterOpen = !_filterOpen),
        canSegment: _canSegment,
        selecting: _selecting,
        onToggleSelecting: _toggleSelecting,
        canMarket: _canMarket,
        campaignOpen: _campaignOpen,
        onToggleCampaign: _toggleCampaign,
      ),
      if (_filterOpen) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        CrmPanelCard(
          child: CrmFilterPanel(
            sourceType: _filters.sourceType,
            onSourceTap: _onSourceTap,
            sourceStart: _filters.sourceStart,
            sourceEnd: _filters.sourceEnd,
            onPickStart: () => _pickSourceDate(isStart: true),
            onPickEnd: () => _pickSourceDate(isStart: false),
            availableTags: _availableTags,
            tagId: _filters.tagId,
            onTagTap: _onTagTap,
            onClearFilters: _clearFilters,
            canSegment: _canSegment,
            segmentName: _segmentName,
            segmentSaving: _segmentSaving,
            onSaveSegment: _saveSegment,
            savedSegments: _savedSegments,
            onApplySegment: _applySavedSegment,
            savedSegmentsError: _savedSegmentsError,
            onRetrySavedSegments: _loadSavedSegments,
          ),
        ),
      ],
      if (_selecting) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        CrmPanelCard(
          child: CrmBatchBar(
            selectedCount: _selectedIds.length,
            tagName: _batchTagName,
            submitting: _batchSubmitting,
            onSubmit: _submitBatchTag,
            error: _batchError,
          ),
        ),
      ],
      if (_campaignOpen && _canMarket) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        CrmPanelCard(
          child: CrmCampaignPanel(
            canCoupon: _canCoupon,
            channel: _channel,
            onChannelTap: _onChannelTap,
            notificationDeliveryStatus: _notificationDeliveryStatus,
            couponDeliveryStatus: _couponDeliveryStatus,
            segmentName: _segmentLabel,
            onPickSegment: _pickCampaignSegment,
            savedSegmentsError: _savedSegmentsError,
            onRetrySavedSegments: _loadSavedSegments,
            couponName: _couponLabel,
            onPickCoupon: _pickCampaignCoupon,
            couponCatalogError: _couponCatalogError,
            onRetryCoupons: _loadCoupons,
            title: _campaignTitle,
            content: _campaignContent,
            previewing: _previewing,
            sending: _sending,
            onPreview: _previewCampaign,
            onSend: _sendCampaign,
            preview: _preview,
            error: _campaignError,
            task: _task,
            campaigns: _campaigns,
            onOpenCampaign: _openCampaign,
            onRetryTask: _retryCampaign,
          ),
        ),
      ],
    ],
  );

  /// 计数摘要(`cu-hero-sub`)。计数是**全量统计**,取 segmentCounts.all。
  Widget _summaryLine(CyPalette p) {
    final String text = merchantCrmSummary(context, _data);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space1,
        CyTokens.pageX,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: CyType.footnote.copyWith(color: p.textSecondary),
        ),
      ),
    );
  }

  Widget _listArea(CyPalette p) {
    if (_listError.isNotEmpty && _rows.isEmpty) {
      return StatusView(
        message: stringsOf(context).merchantCrmListError,
        sub: _listError,
        large: true,
        onRetry: _load,
      );
    }
    if (_loading && _rows.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_rows.isEmpty) return _emptyView();
    // ★ 相对时间按**本机时区**算,now 在这里取一次传下去 ——
    //   服务端算「3 天前」会按服务器时区,跨时区必错。
    final DateTime now = DateTime.now();
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
        itemCount: _rows.length + 1,
        itemBuilder: (BuildContext context, int i) {
          if (i == _rows.length) {
            // 底部留白 + 「正在加载更多」(快照 `cu-foot`)。
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
              child: Center(
                child: _loadingMore
                    ? Text(
                        stringsOf(context).merchantCrmMore,
                        style: CyType.caption1.copyWith(color: p.textSecondary),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          final CrmCustomerRow row = _rows[i];
          return _CrmCustomerTile(
            row: row,
            now: now,
            selecting: _selecting,
            selected: _selectedIds.contains(row.memberId),
            onTap: () {
              if (_selecting) {
                _toggleSelected(row.memberId);
                return;
              }
              context.push('/merchant/customers/${row.memberId}');
            },
            onCall: () => _callCustomer(row.memberId),
            onCopy: () => _copyCustomerPhone(row.memberId),
          );
        },
      ),
    );
  }

  /// 空态要说清「为什么空」—— 搜不到、这一段没人、一个客户都没有,
  /// 下一步动作完全不同(快照 `_emptyCopy`)。
  Widget _emptyView() {
    if (_filters.keyword.isNotEmpty) {
      return StatusView(
        message: stringsOf(context).merchantCrmSearchEmpty,
        sub: stringsOf(context).merchantCrmSearchEmptyHint,
        large: true,
        retryLabel: stringsOf(context).merchantCrmClearSearch,
        onRetry: () => _applyFilters(_filters.copyWith(keyword: '')),
      );
    }
    if (_filters.segment != 'all') {
      final String label = kCrmSegmentOptions
          .firstWhere(
            (CrmSegmentOption o) => o.key == _filters.segment,
            orElse: () => const CrmSegmentOption('all', '这一段'),
          )
          .label;
      return StatusView(
        message: stringsOf(context).merchantCrmSegmentEmpty(merchantCrmLocalText(context, label)),
        sub: stringsOf(context).merchantCrmSegmentEmptyHint,
        large: true,
        retryLabel: stringsOf(context).merchantCrmAllCustomers,
        onRetry: () => _applyFilters(_filters.copyWith(segment: 'all')),
      );
    }
    final int? countedAll = _data?.segmentCounts['all'];
    if (countedAll == null) {
      return StatusView(
        message: stringsOf(context).merchantCrmCountsUnavailable,
        sub: stringsOf(context).merchantCrmCountsUnavailableHint,
        large: true,
        retryLabel: stringsOf(context).merchantCrmReload,
        onRetry: _load,
      );
    }
    if (countedAll > 0) {
      return StatusView(
        message: stringsOf(context).merchantCrmRowsMissing,
        sub: stringsOf(context).merchantCrmRowsMissingHint(countedAll),
        large: true,
        retryLabel: stringsOf(context).merchantCrmReload,
        onRetry: _load,
      );
    }
    return StatusView(
      message: stringsOf(context).merchantCrmEmpty,
      sub: stringsOf(context).merchantCrmEmptyHint,
      large: true,
      retryLabel: stringsOf(context).merchantCrmCoop,
      onRetry: () => context.push('/merchant/coop'),
    );
  }
}

/// Excel 的 MIME。★ 不给的话 iOS 分享面板会给文件一个通用图标,
/// 收到的人点开可能找不到能打开它的 App。
const String _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// 客户列表的一行(快照 `cu-row`):头像 / 姓名 + 分层徽标 + 备注 /
/// 最近动作 / 备注内容 / 电话(可拨号、可复制)或「为什么不给号」。
class _CrmCustomerTile extends StatelessWidget {
  const _CrmCustomerTile({
    required this.row,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onCall,
    required this.onCopy,
  });

  final CrmCustomerRow row;
  final DateTime now;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final String action = merchantCrmAction(context, row, now);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (selecting) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: _CrmCheckbox(on: selected),
            ),
            const SizedBox(width: CyTokens.space2),
          ],
          // ★ fallback 取 avatarName 的首字,不是 displayName ——
          //   用 displayName 会在没留姓名时把「未留姓名」的「未」渲成姓氏首字。
          CyAvatar(
            url: row.avatar,
            fallback: row.avatarName.isEmpty
                ? null
                : row.avatarName.characters.first,
          ),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        merchantCrmCustomerName(context, row),
                        style: CyType.body.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.tierText.isNotEmpty) ...<Widget>[
                      const SizedBox(width: CyTokens.space1_5),
                      _TierPill(
                        label: merchantCrmLocalText(context, row.tierText),
                        warning: row.tierIsWarning,
                      ),
                    ],
                    if (row.noteText.isNotEmpty) ...<Widget>[
                      const SizedBox(width: CyTokens.space1_5),
                      CyTag(label: stringsOf(context).merchantCrmNote),
                    ],
                  ],
                ),
                if (action.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      action,
                      style: CyType.footnote.copyWith(color: p.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (row.noteText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.noteText,
                      style: CyType.footnote.copyWith(color: p.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (row.phoneText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space1),
                    child: Row(
                      children: <Widget>[
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: onCall,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              row.phoneText,
                              style: CyType.footnote.copyWith(color: p.brand),
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space2,
                          ),
                          minimumSize: const Size(44, 44),
                          onPressed: onCopy,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            alignment: Alignment.center,
                            child: Icon(
                              CupertinoIcons.doc_on_doc,
                              size: 18,
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (row.hintText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.hintText,
                      style: CyType.footnote.copyWith(color: p.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const CupertinoListTileChevron(),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: selecting
          ? selected ? stringsOf(context).merchantCrmDeselectName(merchantCrmCustomerName(context, row)) : stringsOf(context).merchantCrmSelectName(merchantCrmCustomerName(context, row))
          : stringsOf(context).merchantCrmViewName(merchantCrmCustomerName(context, row)),
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        onPressed: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: content,
        ),
      ),
    );
  }
}

/// 选择态复选框。
class _CrmCheckbox extends StatelessWidget {
  const _CrmCheckbox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? p.brand : p.bgSurface,
        shape: BoxShape.circle,
        border: Border.all(color: on ? p.brand : p.borderStrong),
      ),
      child: on
          ? Icon(CupertinoIcons.check_mark, size: 14, color: p.textInverse)
          : null,
    );
  }
}

/// 分层徽标(`cy-badge` 的 App 对应)。文字本身说明状态(不只靠颜色,V5)。
class _TierPill extends StatelessWidget {
  const _TierPill({required this.label, required this.warning});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final Color fg = warning ? p.statusWarning : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: warning ? p.statusWarning.withValues(alpha: 0.12) : p.bgSurfaceStrong,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: CyType.caption2.copyWith(color: fg)),
    );
  }
}
