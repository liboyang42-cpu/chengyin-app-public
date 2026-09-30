import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_native_notice.dart';

const List<({String key, String name})> kOfficialPublishCategories =
    <({String key, String name})>[
      (key: 'city_light', name: '城市点亮日'),
      (key: 'custom', name: '自定义'),
      (key: 'festival', name: '节日'),
      (key: 'brand', name: '品牌'),
      (key: 'challenge', name: '挑战'),
    ];

const List<({String key, String name})> kOfficialCollectiveMetrics =
    <({String key, String name})>[
      (key: 'light_count', name: '点亮数'),
      (key: 'complete_count', name: '完成人数'),
      (key: 'signup_count', name: '报名人数'),
    ];

const List<String> _audienceOrder = <String>['player', 'club', 'merchant'];
const List<String> _channelOrder = <String>['inapp', 'subscribe'];

num _wireNumber(String value) => num.tryParse(value.trim()) ?? 0;

Map<String, dynamic> buildOfficialEventBody({
  required String title,
  required String subtitle,
  required String city,
  required String category,
  required DateTime? startDate,
  required DateTime? endDate,
  required bool collective,
  required String metric,
  required String threshold,
  required String xp,
  required bool badge,
}) => <String, dynamic>{
  'title': title.trim(),
  'subtitle': subtitle.trim(),
  'city': city.trim(),
  'category': category,
  'activityStart': startDate?.millisecondsSinceEpoch,
  'activityEnd': endDate?.millisecondsSinceEpoch,
  'settleTime': endDate?.millisecondsSinceEpoch,
  'collectiveEnabled': collective ? 1 : 0,
  'collectiveMetric': metric,
  'collectiveThreshold': collective ? _wireNumber(threshold) : 0,
  'rewardJson': jsonEncode(<String, dynamic>{
    'settleXp': _wireNumber(xp),
    'settleBadge': badge,
  }),
};

Map<String, dynamic> buildOfficialBroadcastBody({
  int? eventId,
  required String activityTitle,
  required String city,
  required Set<String> audience,
  required int copyMode,
  required String unifiedTitle,
  required String unifiedSub,
  required String playerTitle,
  required String playerSub,
  required String clubTitle,
  required String clubSub,
  required String merchantTitle,
  required String merchantSub,
  required Set<String> channels,
}) {
  final List<String> audienceList = _audienceOrder
      .where((String item) => audience.contains(item))
      .toList(growable: false);
  final List<String> channelList = _channelOrder
      .where((String item) => channels.contains(item))
      .toList(growable: false);
  final String fallbackTitle = activityTitle.trim().isEmpty
      ? '官方通知'
      : activityTitle.trim();
  final Map<String, dynamic> content;
  if (copyMode == 2) {
    final Map<String, ({String title, String sub})> copies =
        <String, ({String title, String sub})>{
          'player': (title: playerTitle, sub: playerSub),
          'club': (title: clubTitle, sub: clubSub),
          'merchant': (title: merchantTitle, sub: merchantSub),
        };
    content = <String, dynamic>{
      for (final String role in audienceList)
        role: <String, dynamic>{
          'title': copies[role]!.title.trim(),
          'sub': copies[role]!.sub.trim(),
        },
    };
  } else {
    content = <String, dynamic>{
      'title': unifiedTitle.trim().isEmpty
          ? fallbackTitle
          : unifiedTitle.trim(),
      'sub': unifiedSub.trim(),
    };
  }
  return <String, dynamic>{
    'eventId': eventId,
    'title': copyMode == 1
        ? (unifiedTitle.trim().isEmpty ? fallbackTitle : unifiedTitle.trim())
        : '官方通知',
    'audience': audienceList.join(','),
    'copyMode': copyMode,
    'contentJson': jsonEncode(content),
    'channels': channelList.isEmpty ? 'inapp' : channelList.join(','),
    'city': city.trim().isEmpty ? null : city.trim(),
  };
}

String? officialPublishBlocker({
  required String mode,
  required String activityTitle,
  required Set<String> audience,
}) {
  if (mode == 'activity' && activityTitle.trim().isEmpty) {
    return '输入活动标题';
  }
  if (mode == 'notice' && audience.isEmpty) return '请选择通知对象';
  return null;
}

/// 官方发布白名单闸；无法判定时失败关闭。
final officialCanPublishProvider = FutureProvider.autoDispose<bool>((
  Ref ref,
) async {
  try {
    return await ref.watch(officialApiProvider).canPublish();
  } catch (_) {
    return false;
  }
});

class OfficialPublishPage extends ConsumerStatefulWidget {
  const OfficialPublishPage({super.key});

  @override
  ConsumerState<OfficialPublishPage> createState() =>
      _OfficialPublishPageState();
}

class _OfficialPublishPageState extends ConsumerState<OfficialPublishPage> {
  static const List<String> _controllerKeys = <String>[
    'title',
    'subtitle',
    'city',
    'threshold',
    'xp',
    'unifiedTitle',
    'unifiedSub',
    'playerTitle',
    'playerSub',
    'clubTitle',
    'clubSub',
    'merchantTitle',
    'merchantSub',
  ];
  late final Map<String, TextEditingController> _c =
      <String, TextEditingController>{
        for (final String key in _controllerKeys) key: TextEditingController(),
      };
  String _mode = 'activity';
  int _categoryIndex = 0;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _collective = false;
  int _metricIndex = 0;
  bool _badge = true;
  final Set<String> _audience = <String>{};
  int _copyMode = 1;
  final Set<String> _channels = <String>{'inapp'};
  bool _busy = false;

  @override
  void dispose() {
    for (final TextEditingController controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? get _blocker => officialPublishBlocker(
    mode: _mode,
    activityTitle: _c['title']!.text,
    audience: _audience,
  );

  Future<void> _submit() async {
    if (_busy || _blocker != null) return;
    setState(() => _busy = true);
    try {
      int? eventId;
      if (_mode == 'activity') {
        eventId = await ref
            .read(officialApiProvider)
            .publishEvent(
              buildOfficialEventBody(
                title: _c['title']!.text,
                subtitle: _c['subtitle']!.text,
                city: _c['city']!.text,
                category: kOfficialPublishCategories[_categoryIndex].key,
                startDate: _startDate,
                endDate: _endDate,
                collective: _collective,
                metric: kOfficialCollectiveMetrics[_metricIndex].key,
                threshold: _c['threshold']!.text,
                xp: _c['xp']!.text,
                badge: _badge,
              ),
            );
      }
      if (_audience.isNotEmpty) {
        await ref
            .read(officialApiProvider)
            .broadcast(
              buildOfficialBroadcastBody(
                eventId: eventId,
                activityTitle: _c['title']!.text,
                city: _c['city']!.text,
                audience: _audience,
                copyMode: _copyMode,
                unifiedTitle: _c['unifiedTitle']!.text,
                unifiedSub: _c['unifiedSub']!.text,
                playerTitle: _c['playerTitle']!.text,
                playerSub: _c['playerSub']!.text,
                clubTitle: _c['clubTitle']!.text,
                clubSub: _c['clubSub']!.text,
                merchantTitle: _c['merchantTitle']!.text,
                merchantSub: _c['merchantSub']!.text,
                channels: _channels,
              ),
            );
      }
      if (!mounted) return;
      final String receipt = _mode == 'notice'
          ? '通知已发送'
          : _audience.isEmpty
          ? '活动已发布'
          : '已发布并通知';
      if (_mode == 'activity') {
        final OverlayState rootOverlay = Overlay.of(context, rootOverlay: true);
        context.pop(eventId);
        CyNativeNotice.show(
          rootOverlay.context,
          receipt,
          overlayState: rootOverlay,
        );
      } else {
        CyNativeNotice.show(context, receipt);
        setState(() => _busy = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      CyNativeNotice.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> can = ref.watch(officialCanPublishProvider);
    final CyPalette palette = CyPalette.of(context);
    // 去掉外层的 Material `Scaffold`(整页是 Cupertino 结构,Scaffold 只多
    // 一层 Material 与一套它自己的键盘 inset 处理);内容垫层仍按仓内写法
    // 用透明 `Material` 包住 —— 页内无显式字号的 Text 靠它拿到正文色与字号。
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      // 导航栏背景交给系统(M5:不自定义 bar 底色,否则会盖掉系统的
      // scroll edge effect 与玻璃自适应)。
      navigationBar: const CupertinoNavigationBar(middle: Text('发起官方活动')),
      child: Material(
        color: Colors.transparent,
        child: can.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (Object error, StackTrace stack) => StatusView(
            icon: CupertinoIcons.lock,
            message: '暂时确认不了你的发布权限',
            sub: '可以再试一次,或从后台发布',
            onRetry: () => ref.invalidate(officialCanPublishProvider),
          ),
          data: (bool ok) => ok
              ? _form(context)
              : const StatusView(
                  icon: CupertinoIcons.lock,
                  message: '你还没有官方发布权限',
                  sub: '官方活动由平台白名单账号发布,需要开通请联系平台',
                ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space4,
        CyTokens.pageX,
        CyTokens.space8,
      ),
      children: <Widget>[
        CupertinoSlidingSegmentedControl<String>(
          key: const Key('official-mode'),
          groupValue: _mode,
          children: const <String, Widget>{
            'activity': Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('发活动'),
            ),
            'notice': Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('只发通知'),
            ),
          },
          onValueChanged: (String? value) {
            if (!_busy && value != null) setState(() => _mode = value);
          },
        ),
        if (_mode == 'activity') ..._activityFields(),
        const SizedBox(height: CyTokens.space5),
        _sectionTitle(_mode == 'activity' ? '通知配置 （可选）' : '通知配置'),
        Text(
          '勾选通知对象，可“一起发”（统一文案）或“分开发”（三类各写各的）',
          style: CyType.footnote.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: CyTokens.space3),
        Row(
          children: <Widget>[
            _audienceButton('player', '玩家'),
            const SizedBox(width: CyTokens.space2),
            _audienceButton('club', '俱乐部'),
            const SizedBox(width: CyTokens.space2),
            _audienceButton('merchant', '商家'),
          ],
        ),
        const SizedBox(height: CyTokens.space3),
        CupertinoSlidingSegmentedControl<int>(
          key: const Key('official-copy-mode'),
          groupValue: _copyMode,
          children: const <int, Widget>{
            1: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('一起发'),
            ),
            2: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('分开发'),
            ),
          },
          onValueChanged: (int? value) {
            if (!_busy && value != null) setState(() => _copyMode = value);
          },
        ),
        const SizedBox(height: CyTokens.space3),
        if (_copyMode == 1) ...<Widget>[
          _field('unifiedTitle', '标题', '统一通知标题'),
          _field('unifiedSub', '内容', '统一通知内容', maxLines: 3),
        ] else
          ..._selectedSplitFields(),
        _switchRow(
          label: '站内信',
          value: _channels.contains('inapp'),
          onChanged: (bool value) => _toggleChannel('inapp', value),
        ),
        _switchRow(
          label: '订阅消息',
          value: _channels.contains('subscribe'),
          onChanged: (bool value) => _toggleChannel('subscribe', value),
        ),
        const SizedBox(height: CyTokens.space4),
        CupertinoButton(
          key: const Key('official-publish'),
          minimumSize: const Size.fromHeight(44),
          color: palette.actionPrimaryBg,
          disabledColor: palette.bgSubtle,
          foregroundColor: (_busy || _blocker != null)
              ? palette.textPlaceholder
              : palette.actionPrimaryFg,
          onPressed: (_busy || _blocker != null) ? null : _submit,
          child: _busy
              ? const CupertinoActivityIndicator()
              : Text(_blocker ?? (_mode == 'activity' ? '发布活动' : '发送通知')),
        ),
      ],
    );
  }

  List<Widget> _activityFields() => <Widget>[
    const SizedBox(height: CyTokens.space5),
    _sectionTitle('活动配置'),
    _field(
      'title',
      '标题',
      '如：成都点亮日',
      textInputAction: TextInputAction.next,
      autofillHints: const <String>[AutofillHints.name],
    ),
    _field('subtitle', '副标题', '一句话说明', textInputAction: TextInputAction.next),
    _field(
      'city',
      '城市',
      '如：成都',
      textInputAction: TextInputAction.next,
      autofillHints: const <String>[AutofillHints.addressCity],
    ),
    _choice(
      key: const Key('official-category'),
      label: '分类',
      value: kOfficialPublishCategories[_categoryIndex].name,
      onPressed: _pickCategory,
    ),
    _choice(
      key: const Key('official-start-date'),
      label: '活动开始',
      value: _dateLabel(_startDate),
      onPressed: () => _pickDate(start: true),
    ),
    _choice(
      key: const Key('official-end-date'),
      label: '活动结束',
      value: _dateLabel(_endDate),
      onPressed: () => _pickDate(start: false),
    ),
    _switchRow(
      label: '集体玩法',
      value: _collective,
      onChanged: (bool value) => setState(() => _collective = value),
    ),
    if (_collective) ...<Widget>[
      _choice(
        key: const Key('official-metric'),
        label: '集体指标',
        value: kOfficialCollectiveMetrics[_metricIndex].name,
        onPressed: _pickMetric,
      ),
      _field(
        'threshold',
        '达标阈值',
        '如：1000',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
      ),
    ],
    _field(
      'xp',
      '结算成长值',
      '如：50',
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
    ),
    _switchRow(
      label: '限定徽章',
      value: _badge,
      onChanged: (bool value) => setState(() => _badge = value),
    ),
  ];

  List<Widget> _selectedSplitFields() => <Widget>[
    if (_audience.contains('player'))
      ..._splitFields('player', '给玩家', '标题：出门点亮领限定徽章'),
    if (_audience.contains('club'))
      ..._splitFields('club', '给俱乐部', '标题：带团参与得战队榜积分'),
    if (_audience.contains('merchant'))
      ..._splitFields('merchant', '给商家', '标题：客流洪峰，入驻活动路线'),
  ];

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space3),
    child: CySectionTitle(text),
  );

  Widget _field(
    String key,
    String label,
    String placeholder, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Semantics(
        textField: true,
        label: label,
        child: CupertinoTextField(
          key: Key('official-$key'),
          controller: _c[key],
          minLines: maxLines > 1 ? 2 : 1,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          autocorrect: keyboardType == TextInputType.text,
          enableSuggestions: keyboardType == TextInputType.text,
          onChanged: (_) => setState(() {}),
          placeholder: placeholder,
          prefix: Padding(
            padding: const EdgeInsets.only(left: CyTokens.space3),
            child: SizedBox(
              width: 80,
              child: Text(label, style: TextStyle(color: palette.textPrimary)),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.space3,
            vertical: 12,
          ),
          style: CyType.callout.copyWith(color: palette.textPrimary),
          placeholderStyle: CyType.callout.copyWith(
            color: palette.textPlaceholder,
          ),
          decoration: BoxDecoration(
            color: palette.inputBgEmpty,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            border: Border.all(color: palette.borderSubtle),
          ),
        ),
      ),
    );
  }

  Widget _choice({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onPressed,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: CupertinoButton(
        key: key,
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        color: palette.actionSecondaryBg,
        foregroundColor: palette.textPrimary,
        onPressed: _busy ? null : onPressed,
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, textAlign: TextAlign.left)),
            Text(value, style: TextStyle(color: palette.textSecondary)),
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.chevron_forward, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return Semantics(
      label: label,
      toggled: value,
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: TextStyle(color: palette.textPrimary)),
            ),
            CupertinoSwitch(value: value, onChanged: _busy ? null : onChanged),
          ],
        ),
      ),
    );
  }

  Widget _audienceButton(String wire, String label) {
    final CyPalette palette = CyPalette.of(context);
    final bool selected = _audience.contains(wire);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: CupertinoButton(
          key: Key('official-audience-$wire'),
          minimumSize: const Size.fromHeight(44),
          padding: EdgeInsets.zero,
          color: selected ? palette.actionPrimaryBg : palette.actionSecondaryBg,
          foregroundColor: selected
              ? palette.actionPrimaryFg
              : palette.textPrimary,
          onPressed: _busy
              ? null
              : () => setState(() {
                  selected ? _audience.remove(wire) : _audience.add(wire);
                }),
          child: Text(label),
        ),
      ),
    );
  }

  List<Widget> _splitFields(String key, String title, String placeholder) =>
      <Widget>[
        _sectionTitle(title),
        _field('${key}Title', '标题', placeholder),
        _field('${key}Sub', '内容', '内容', maxLines: 3),
      ];

  void _toggleChannel(String wire, bool selected) => setState(() {
    selected ? _channels.add(wire) : _channels.remove(wire);
  });

  Future<void> _pickCategory() async {
    final int? selected = await _actionSheet(
      title: '分类',
      current: _categoryIndex,
      labels: kOfficialPublishCategories
          .map((({String key, String name}) item) => item.name)
          .toList(growable: false),
    );
    if (selected != null && mounted) setState(() => _categoryIndex = selected);
  }

  Future<void> _pickMetric() async {
    final int? selected = await _actionSheet(
      title: '集体指标',
      current: _metricIndex,
      labels: kOfficialCollectiveMetrics
          .map((({String key, String name}) item) => item.name)
          .toList(growable: false),
    );
    if (selected != null && mounted) setState(() => _metricIndex = selected);
  }

  Future<int?> _actionSheet({
    required String title,
    required int current,
    required List<String> labels,
  }) => showCupertinoModalPopup<int>(
    context: context,
    semanticsDismissible: true,
    builder: (BuildContext popupContext) => CupertinoActionSheet(
      title: Text(title),
      actions: <Widget>[
        for (int index = 0; index < labels.length; index++)
          CupertinoActionSheetAction(
            isDefaultAction: index == current,
            onPressed: () => Navigator.of(popupContext).pop(index),
            child: Text(labels[index]),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(popupContext).pop(),
        child: const Text('取消'),
      ),
    ),
  );

  Future<void> _pickDate({required bool start}) async {
    final DateTime initial = (start ? _startDate : _endDate) ?? DateTime.now();
    final DateTime? result = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: initial,
      minimumDate: DateTime(1970),
      maximumDate: DateTime(2100),
      title: start ? '活动开始' : '活动结束',
    );
    if (result != null && mounted) {
      setState(() => start ? _startDate = result : _endDate = result);
    }
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return '选择日期';
    String two(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }
}
