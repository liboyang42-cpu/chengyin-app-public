import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_cupertino_range_slider.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_tabs.dart';
import 'search_controller.dart';

/// 打开高级筛选 bottom sheet,并把结果写回 searchFilterProvider。
/// 应用后回调 onSearch(索引页据此跳转独立结果页,对齐小程序「筛选→搜索」)。
Future<void> showSearchFilterSheet(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onSearch,
  String initialMerchantTag = '',
  String initialMerchantCityRole = '',
  void Function(String tag, String cityRole)? onMerchantFieldsChanged,
}) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.12,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _SearchFilterSheet(
              onSearch: onSearch,
              initialMerchantTag: initialMerchantTag,
              initialMerchantCityRole: initialMerchantCityRole,
              onMerchantFieldsChanged: onMerchantFieldsChanged,
              scrollController: scrollController,
            ),
  );
}

class _SearchFilterSheet extends ConsumerStatefulWidget {
  const _SearchFilterSheet({
    this.onSearch,
    required this.scrollController,
    required this.initialMerchantTag,
    required this.initialMerchantCityRole,
    this.onMerchantFieldsChanged,
  });

  final VoidCallback? onSearch;
  final ScrollController scrollController;
  final String initialMerchantTag;
  final String initialMerchantCityRole;
  final void Function(String tag, String cityRole)? onMerchantFieldsChanged;

  @override
  ConsumerState<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<_SearchFilterSheet> {
  // 价格上限(滑块的最大值)。量程对齐小程序 priceRange.max=1000。
  static const double _maxPriceCap = 1000;

  // 两端最小间隔:小程序 handleSliderMove 里 minInterval=5(%),1000*5%=50。
  static const double _minPriceGap = _maxPriceCap * 0.05;

  late DateTimeRange? _dateRange;
  late RangeValues _priceRange;
  late int? _sortType;
  late final TextEditingController _merchantTagController;
  late final TextEditingController _merchantCityRoleController;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(searchFilterProvider);
    _dateRange = filter.dateRange;
    _priceRange = RangeValues(
      filter.minPrice ?? 0,
      filter.maxPrice ?? _maxPriceCap,
    );
    _sortType = filter.sortType;
    _merchantTagController = TextEditingController(
      text: widget.initialMerchantTag,
    );
    _merchantCityRoleController = TextEditingController(
      text: widget.initialMerchantCityRole,
    );
  }

  @override
  void dispose() {
    _merchantTagController.dispose();
    _merchantCityRoleController.dispose();
    super.dispose();
  }

  /// 今天(0)/ 明天(1)快捷项:把区间锁成当天(对齐小程序 selectDate case 1/2)。
  void _setQuickDate(int which) {
    final DateTime base = DateUtils.dateOnly(DateTime.now());
    final DateTime day = which == 0 ? base : base.add(const Duration(days: 1));
    setState(() => _dateRange = DateTimeRange(start: day, end: day));
  }

  bool _isActiveQuickDate(int which) {
    final range = _dateRange;
    if (range == null) return false;
    final DateTime base = DateUtils.dateOnly(DateTime.now());
    final DateTime day = which == 0 ? base : base.add(const Duration(days: 1));
    return DateUtils.isSameDay(range.start, day) &&
        DateUtils.isSameDay(range.end, day);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await _showCupertinoDateRangePicker(
      context: context,
      minimumDate: DateTime(now.year - 1),
      maximumDate: DateTime(now.year + 2, 12, 31),
      initialRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  void _apply() {
    final notifier = ref.read(searchFilterProvider.notifier);
    final bool priceTouched =
        _priceRange.start > 0 || _priceRange.end < _maxPriceCap;
    notifier.state = notifier.state.copyWith(
      dateRange: _dateRange,
      clearDateRange: _dateRange == null,
      minPrice: priceTouched ? _priceRange.start : null,
      maxPrice: priceTouched ? _priceRange.end : null,
      clearPrice: !priceTouched,
      sortType: _sortType,
      clearSort: _sortType == null,
    );
    widget.onMerchantFieldsChanged?.call(
      _merchantTagController.text.trim(),
      _merchantCityRoleController.text.trim(),
    );
    Navigator.of(context).pop();
    widget.onSearch?.call();
  }

  void _notifyMerchantFieldsChanged() {
    widget.onMerchantFieldsChanged?.call(
      _merchantTagController.text.trim(),
      _merchantCityRoleController.text.trim(),
    );
  }

  void _reset() {
    setState(() {
      _dateRange = null;
      _priceRange = const RangeValues(0, _maxPriceCap);
      _sortType = 1;
      _merchantTagController.clear();
      _merchantCityRoleController.clear();
    });
    _notifyMerchantFieldsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '高级筛选',
                    style: textTheme.titleLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CupertinoButton(
                  key: const Key('search-filter-reset'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: palette.textSecondary,
                  onPressed: _reset,
                  child: const Text('重置'),
                ),
                Semantics(
                  label: '关闭高级筛选',
                  button: true,
                  child: CupertinoButton(
                    key: const Key('search-filter-close'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: palette.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const ExcludeSemantics(
                      child: Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space2),

            if (widget.onMerchantFieldsChanged != null) ...<Widget>[
              Text(
                '商家发现',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              CupertinoTextField(
                key: const Key('search-filter-merchant-tag'),
                controller: _merchantTagController,
                onChanged: (_) => _notifyMerchantFieldsChanged(),
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                placeholder: '探索标签',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(CupertinoIcons.tag, size: 18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: palette.bgSurfaceSubtle,
                  border: Border.all(color: palette.borderSubtle),
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              CupertinoTextField(
                key: const Key('search-filter-merchant-city-role'),
                controller: _merchantCityRoleController,
                onChanged: (_) => _notifyMerchantFieldsChanged(),
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                placeholder: '城市角色',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(CupertinoIcons.building_2_fill, size: 18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: palette.bgSurfaceSubtle,
                  border: Border.all(color: palette.borderSubtle),
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                ),
              ),
              const SizedBox(height: CyTokens.space6),
            ],

            // 日期区间
            Text(
              '日期区间',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            // 小程序 selectDate 的快捷项:今天 / 明天(点一下即把区间锁死到当天)。
            Row(
              children: <Widget>[
                _QuickDateChip(
                  key: const Key('search-filter-date-today'),
                  label: '今天',
                  selected: _isActiveQuickDate(0),
                  onTap: () => _setQuickDate(0),
                ),
                const SizedBox(width: CyTokens.space2),
                _QuickDateChip(
                  key: const Key('search-filter-date-tomorrow'),
                  label: '明天',
                  selected: _isActiveQuickDate(1),
                  onTap: () => _setQuickDate(1),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bgSurfaceSubtle,
                border: Border.all(color: palette.borderSubtle),
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              child: CupertinoButton(
                key: const Key('search-filter-date'),
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: palette.textPrimary,
                alignment: Alignment.centerLeft,
                onPressed: _pickDateRange,
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.calendar, size: 18),
                    const SizedBox(width: CyTokens.space2),
                    Expanded(
                      child: Text(
                        _dateRange == null
                            ? '不限日期'
                            : '${_fmt(_dateRange!.start)} ~ ${_fmt(_dateRange!.end)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // .dl 段间距 = space-6(64rpx)
            const SizedBox(height: CyTokens.space6),

            // 价格区间
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '价格区间',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                Flexible(
                  child: Text(
                    '¥${_priceRange.start.toStringAsFixed(0)} - '
                    '¥${_priceRange.end.toStringAsFixed(0)}'
                    '${_priceRange.end >= _maxPriceCap ? '+' : ''}',
                    textAlign: TextAlign.end,
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            CyCupertinoRangeSlider(
              values: _priceRange,
              min: 0,
              max: _maxPriceCap,
              divisions: 40,
              startSemanticLabel: '最低价格',
              endSemanticLabel: '最高价格',
              semanticFormatter: (double value) =>
                  '¥${value.toStringAsFixed(0)}',
              activeColor: palette.textPrimary,
              trackColor: palette.bgSurfaceStrong,
              onChanged: (RangeValues value) => setState(() {
                // 5% 最小间隔:不让两端重合(对齐小程序 handleSliderMove minInterval)。
                double start = value.start;
                double end = value.end;
                if (end - start < _minPriceGap) {
                  if (start >= _maxPriceCap - _minPriceGap) {
                    start = end - _minPriceGap;
                  } else {
                    end = start + _minPriceGap;
                  }
                }
                _priceRange = RangeValues(
                  start.clamp(0.0, _maxPriceCap),
                  end.clamp(0.0, _maxPriceCap),
                );
              }),
            ),
            Text(
              '价格按活动最低票价过滤',
              style: textTheme.bodySmall?.copyWith(color: palette.textTertiary),
            ),
            // .dl 段间距 = space-6(64rpx)
            const SizedBox(height: CyTokens.space6),

            // 排序
            Text(
              '排序',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            // 排序走共用件(手册 §6 P3):分段型 iOS 26+ 是系统分段(真玻璃),
            // 旧系统回退 Cupertino 分段,并补齐 44pt 触达区。
            CyTabs(
              variant: CyTabsVariant.segmented,
              tabs: const <CyTab>[
                CyTab(key: '1', label: '最近'),
                CyTab(key: '2', label: '最热'),
              ],
              active: '${_sortType ?? 1}',
              onChanged: (String key) =>
                  setState(() => _sortType = int.parse(key)),
            ),
            // .form-btn 上边距 = space-4(32rpx)
            const SizedBox(height: CyTokens.space4),

            Semantics(
              button: true,
              child: CupertinoButton(
                key: const Key('search-filter-apply'),
                minimumSize: const Size.fromHeight(CyTokens.btnH),
                color: palette.actionPrimaryBg,
                foregroundColor: palette.actionPrimaryFg,
                borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                onPressed: _apply,
                child: const Text('应用筛选'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

Future<DateTimeRange?> _showCupertinoDateRangePicker({
  required BuildContext context,
  required DateTime minimumDate,
  required DateTime maximumDate,
  DateTimeRange? initialRange,
}) async {
  final DateTime today = DateUtils.dateOnly(DateTime.now());
  final DateTime initialStart = _clampDate(
    initialRange?.start ?? today,
    minimumDate,
    maximumDate,
  );
  final DateTime initialEnd = _clampDate(
    initialRange?.end ?? initialStart,
    initialStart,
    maximumDate,
  );
  final DateTime? pickedStart = await showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.date,
    initialDateTime: initialStart,
    minimumDate: minimumDate,
    maximumDate: maximumDate,
    title: '开始日期',
  );
  if (pickedStart == null || !context.mounted) return null;

  DateTime start = _clampDate(pickedStart, minimumDate, maximumDate);
  DateTime end = initialEnd.isBefore(start) ? start : initialEnd;
  final DateTime? pickedEnd = await showCySystemDatePicker(
    context: context,
    mode: CupertinoDatePickerMode.date,
    initialDateTime: end,
    minimumDate: minimumDate,
    maximumDate: maximumDate,
    title: '结束日期',
  );
  if (pickedEnd == null) return null;
  end = _clampDate(pickedEnd, minimumDate, maximumDate);
  if (end.isBefore(start)) start = end;
  return DateTimeRange(start: start, end: end);
}

DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
  final DateTime date = DateUtils.dateOnly(value);
  if (date.isBefore(minimum)) return DateUtils.dateOnly(minimum);
  if (date.isAfter(maximum)) return DateUtils.dateOnly(maximum);
  return date;
}

/// 日期快捷标签(今天/明天),选中态用主色描边。
class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoButton(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onPressed: onTap,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      color: selected ? palette.actionPrimaryBg : palette.bgSurfaceSubtle,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: selected ? palette.actionPrimaryFg : palette.textPrimary,
        ),
      ),
    );
  }
}
