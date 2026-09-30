// 发布活动 —— 对应小程序 pages/publish/activity(入口 components/cy/publish-sheet 的 goActivity)。
//
// App 此前**发不了活动**:只有 /api/topic/create(发主题),
// 而 /api/activity/publish 的模型与客户端方法早就写好、零调用方。
//
// ★★ 后端有四道闸(ApiActivityController:633-660):
//   ① 登录 ② **仅俱乐部主理人可发布** ③ 配额 ④ 内容安全审核
//   前两条前端提前判,后两条只能等后端回 —— 提前判的那两条要**说清怎么解锁**,
//   不是把按钮灰掉了事(灰按钮不告诉人怎么才能用)。
//
// ★ 分三步照小程序的 STEPS:基本信息 / 活动内容 / 票务。
//   步只管展示分组,字段语义与提交接口一字未改。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/category.dart';
import '../../data/models/activity_publish.dart';
import '../../data/models/publish_draft.dart';
import 'publish_capability.dart';
import '../../core/widgets/upload_hints.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'collaborator_picker.dart';
import 'publish_image_cropper.dart';

/// 只负责活动发布选择器的可测试数据缝；真实实现仍是现有 API。
final activityPublishCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>(
      (Ref ref) => ref.watch(categoryApiProvider).list(type: '2'),
    );

final activityPublishTemplatesProvider = FutureProvider.autoDispose
    .family<List<PublishTemplate>, String>(
      (Ref ref, String keyword) =>
          ref.watch(publishApiProvider).templateMyList(keyword: keyword),
    );

/// 小程序在提交时强制每张活动票的履约窗口等于活动起止时间。
/// App 在日期变更时就做同步，让提交前校验与最终 payload 使用同一个事实。
List<TicketDraft> alignActivityTicketSchedule(
  List<TicketDraft> tickets, {
  required DateTime? startDate,
  required DateTime? endDate,
}) => <TicketDraft>[
  for (final TicketDraft ticket in tickets)
    TicketDraft(
      name: ticket.name,
      price: ticket.price,
      startTime: startDate,
      endTime: endDate,
      totalStock: ticket.totalStock,
    ),
];

String _loadMessage(Object error, String fallback) {
  final String message = error.toString().trim();
  if (message.startsWith('Exception: ') && message.length > 11) {
    return message.substring(11);
  }
  if (message.startsWith('Bad state: ') && message.length > 11) {
    return message.substring(11);
  }
  return fallback;
}

Future<List<Category>?> showActivityCategoryPicker(
  BuildContext context, {
  required WidgetRef ref,
  required List<int> selectedIds,
}) => showCupertinoSheet<List<Category>>(
  context: context,
  showDragHandle: true,
  topGap: 0.24,
  scrollableBuilder: (BuildContext context, ScrollController controller) =>
      _ActivityCategorySheet(
        ref: ref,
        selectedIds: selectedIds,
        controller: controller,
      ),
);

Future<PublishTemplate?> showActivityTemplatePicker(
  BuildContext context, {
  required WidgetRef ref,
  required int? selectedId,
}) => showCupertinoSheet<PublishTemplate>(
  context: context,
  showDragHandle: true,
  topGap: 0.24,
  scrollableBuilder: (BuildContext context, ScrollController controller) =>
      _ActivityTemplateSheet(
        ref: ref,
        selectedId: selectedId,
        controller: controller,
      ),
);

class _ActivityCategorySheet extends StatefulWidget {
  const _ActivityCategorySheet({
    required this.ref,
    required this.selectedIds,
    required this.controller,
  });

  final WidgetRef ref;
  final List<int> selectedIds;
  final ScrollController controller;

  @override
  State<_ActivityCategorySheet> createState() => _ActivityCategorySheetState();
}

class _ActivityCategorySheetState extends State<_ActivityCategorySheet> {
  bool _loading = true;
  String? _error;
  List<Category> _items = <Category>[];
  late final Set<int> _selected = widget.selectedIds.toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Category> items = await widget.ref.read(
        activityPublishCategoriesProvider.future,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _loadMessage(error, '活动类型加载失败');
      });
    }
  }

  void _retry() {
    widget.ref.invalidate(activityPublishCategoriesProvider);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _SheetHeader(
              title: '选择活动类型',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(child: _body()),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space4),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('已选 ${_selected.length} 个')),
                  CupertinoButton(
                    key: const Key('activity-categories-confirm'),
                    minimumSize: const Size(96, 44),
                    color: palette.actionPrimaryBg,
                    disabledColor: palette.actionSecondaryBg,
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            _items
                                .where(
                                  (Category item) =>
                                      _selected.contains(item.id),
                                )
                                .toList(),
                          ),
                    child: Text(
                      '完成',
                      style: TextStyle(
                        color: _selected.isEmpty
                            ? palette.textPlaceholder
                            : palette.actionPrimaryFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CupertinoActivityIndicator());
    if (_error != null) {
      return _SheetFailure(message: _error!, onRetry: _retry);
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无可选活动类型'));
    }
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      controller: widget.controller,
      children: <Widget>[
        for (final Category item in _items)
          Semantics(
            button: true,
            selected: _selected.contains(item.id),
            label: item.name,
            child: CupertinoButton(
              key: Key('activity-category-${item.id}'),
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
              foregroundColor: palette.textPrimary,
              onPressed: () => setState(() {
                if (!_selected.add(item.id)) _selected.remove(item.id);
              }),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(item.name, textAlign: TextAlign.left)),
                  if (_selected.contains(item.id))
                    Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: palette.brand,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityTemplateSheet extends StatefulWidget {
  const _ActivityTemplateSheet({
    required this.ref,
    required this.selectedId,
    required this.controller,
  });

  final WidgetRef ref;
  final int? selectedId;
  final ScrollController controller;

  @override
  State<_ActivityTemplateSheet> createState() => _ActivityTemplateSheetState();
}

class _ActivityTemplateSheetState extends State<_ActivityTemplateSheet> {
  bool _loading = true;
  String? _error;
  List<PublishTemplate> _items = <PublishTemplate>[];
  PublishTemplate? _selected;
  final TextEditingController _search = TextEditingController();
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<PublishTemplate> items = await widget.ref.read(
        activityPublishTemplatesProvider(_keyword).future,
      );
      if (!mounted) return;
      PublishTemplate? selected;
      for (final PublishTemplate item in items) {
        if (item.id == widget.selectedId) {
          selected = item;
          break;
        }
      }
      setState(() {
        _items = items;
        _selected = selected;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _loadMessage(error, '我的模板加载失败');
      });
    }
  }

  void _retry() {
    widget.ref.invalidate(activityPublishTemplatesProvider(_keyword));
    _load();
  }

  void _submitSearch(String value) {
    final String keyword = value.trim();
    if (keyword == _keyword) return;
    _keyword = keyword;
    widget.ref.invalidate(activityPublishTemplatesProvider(_keyword));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _SheetHeader(
              title: '选择我的模板',
              onClose: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.space4,
                vertical: CyTokens.space2,
              ),
              child: CupertinoSearchTextField(
                key: const Key('activity-template-search'),
                controller: _search,
                placeholder: '搜索我的模板',
                onSubmitted: _submitSearch,
              ),
            ),
            Expanded(child: _body()),
            Padding(
              padding: const EdgeInsets.all(CyTokens.space4),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: const Key('activity-template-confirm'),
                  minimumSize: const Size.fromHeight(44),
                  color: palette.actionPrimaryBg,
                  disabledColor: palette.actionSecondaryBg,
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text(
                    '使用这个模板',
                    style: TextStyle(
                      color: _selected == null
                          ? palette.textPlaceholder
                          : palette.actionPrimaryFg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CupertinoActivityIndicator());
    if (_error != null) {
      return _SheetFailure(message: _error!, onRetry: _retry);
    }
    if (_items.isEmpty) {
      return Center(child: Text(_keyword.isEmpty ? '还没有可引用的模板' : '没有匹配的模板'));
    }
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      controller: widget.controller,
      children: <Widget>[
        for (final PublishTemplate item in _items)
          Semantics(
            button: true,
            selected: _selected?.id == item.id,
            label: item.title,
            child: CupertinoButton(
              key: Key('activity-template-${item.id}'),
              minimumSize: const Size.fromHeight(60),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
              foregroundColor: palette.textPrimary,
              onPressed: () => setState(
                () => _selected = _selected?.id == item.id ? null : item,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(item.title, textAlign: TextAlign.left)),
                  if (_selected?.id == item.id)
                    Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: palette.brand,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.space4,
      CyTokens.space2,
      CyTokens.space2,
      CyTokens.space2,
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: CyTokens.typeBody,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        CupertinoButton(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: onClose,
          child: const Icon(CupertinoIcons.xmark_circle_fill),
        ),
      ],
    ),
  );
}

class _SheetFailure extends StatelessWidget {
  const _SheetFailure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: CyTokens.space3),
          CupertinoButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class PublishActivityPage extends ConsumerStatefulWidget {
  const PublishActivityPage({super.key});
  @override
  ConsumerState<PublishActivityPage> createState() =>
      _PublishActivityPageState();
}

class _PublishActivityPageState extends ConsumerState<PublishActivityPage> {
  ActivityPublishForm _form = const ActivityPublishForm();
  int _step = 0;
  bool _submitting = false;
  bool _uploadingCover = false;
  List<Category> _selectedCategories = <Category>[];
  PublishTemplate? _selectedTemplate;

  static const List<String> _stepTitles = <String>['基本信息', '活动内容', '票务'];

  BoxDecoration _inputDecoration() {
    final CyPalette palette = CyPalette.of(context);
    return BoxDecoration(
      color: palette.inputBgEmpty,
      border: Border.all(color: palette.borderSubtle),
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
    );
  }

  Widget _field({
    required Key key,
    required String label,
    required String placeholder,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    return CyField(
      label: label,
      child: CupertinoTextField(
        key: key,
        placeholder: placeholder,
        maxLines: maxLines,
        keyboardType:
            keyboardType ??
            (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        textInputAction:
            textInputAction ??
            (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
        autocorrect: keyboardType == null,
        enableSuggestions: keyboardType == null,
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: _inputDecoration(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickPoi() async {
    final result = await context
        .push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (result == null || !mounted) return;
    setState(
      () => _form = _form.copyWith(
        addressName: result.name,
        address: result.name,
        longitude: result.longitude.toString(),
        latitude: result.latitude.toString(),
      ),
    );
  }

  Future<void> _pickDate({required bool start}) async {
    final DateTime now = DateTime.now();
    final DateTime? value = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.dateAndTime,
      initialDateTime:
          (start ? _form.startDate : _form.endDate) ??
          DateTime(now.year, now.month, now.day, 10),
      minimumDate: now.subtract(const Duration(days: 1)),
      maximumDate: now.add(const Duration(days: 365 * 2)),
      title: start ? '选择开始时间' : '选择结束时间',
    );
    if (value == null || !mounted) return;
    final List<TicketDraft> tickets = alignActivityTicketSchedule(
      _form.tickets,
      startDate: start ? value : _form.startDate,
      endDate: start ? _form.endDate : value,
    );
    setState(
      () => _form = start
          ? _form.copyWith(startDate: value, tickets: tickets)
          : _form.copyWith(endDate: value, tickets: tickets),
    );
  }

  Future<void> _pickCategories() async {
    final List<Category>? categories = await showActivityCategoryPicker(
      context,
      ref: ref,
      selectedIds: _form.categoryIds,
    );
    if (categories == null || !mounted) return;
    setState(() {
      _selectedCategories = categories;
      _form = _form.copyWith(
        categoryIds: categories.map((Category item) => item.id).toList(),
      );
    });
  }

  Future<void> _pickTemplate() async {
    final PublishTemplate? template = await showActivityTemplatePicker(
      context,
      ref: ref,
      selectedId: _form.templateId,
    );
    if (template == null || !mounted) return;
    setState(() {
      _selectedTemplate = template;
      _form = _form.copyWith(templateId: template.id);
    });
  }

  Future<void> _submit() async {
    final String? blocker = _form.blocker;
    if (blocker != null) {
      _toast(blocker, isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(activityApiProvider).publishActivity(_form);
      if (!mounted) return;
      _toast('已提交,审核通过后会出现在列表里');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // ★ 后端的话原样透出 —— 配额满、内容审核不过都由它说,
      //   自己编一句「发布失败」用户不知道该改什么。
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String m, {bool isError = false}) =>
      CyNativeNotice.show(context, m, isError: isError);

  @override
  Widget build(BuildContext context) {
    final PublishCapability cap =
        ref.watch(publishCapabilityProvider).value ?? const PublishCapability();
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('发布活动')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: cap.isClubLeader ? _form_(cap) : const _LockedCard(),
        ),
      ),
    );
  }

  Widget _form_(PublishCapability cap) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      children: <Widget>[
        _StepBar(step: _step, titles: _stepTitles),
        if (cap.quotaText != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                cap.quotaText!,
                key: const Key('publish-activity-quota'),
                style: TextStyle(
                  fontSize: CyTokens.typeCaption,
                  color: p.textTertiary,
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(CyTokens.space4),
            children: <Widget>[
              if (_step == 0) ..._basic(),
              if (_step == 1) ..._content(),
              if (_step == 2) ...<Widget>[
                // 合作者。小程序的活动发布页有这块,App 建页时漏了。
                // ⚠️ 后端字段叫 collaborators(复数、不带 Ids),
                //   与专业发布的 collaboratorIds **不是一个名字**。
                Text(
                  '合作者',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
                ..._collaborators(),
                const SizedBox(height: CyTokens.space4),
                ..._ticket(),
              ],
            ],
          ),
        ),
        _Footer(
          step: _step,
          last: _step == _stepTitles.length - 1,
          submitting: _submitting,
          // ★ 提交钮**不置灰** —— 灰掉就不知道缺什么了。
          //   点下去把 blocker 原样说出来。
          blocker: _form.blocker,
          onBack: _step == 0 ? null : () => setState(() => _step -= 1),
          onNext: () => setState(() => _step += 1),
          onSubmit: _submit,
        ),
      ],
    );
  }

  List<Widget> _basic() => <Widget>[
    _field(
      key: const Key('activity-name'),
      label: '活动标题',
      placeholder: '活动标题',
      onChanged: (String v) => _form = _form.copyWith(name: v),
    ),
    const SizedBox(height: CyTokens.space3),
    CupertinoButton(
      key: const Key('activity-address'),
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
      color: CyPalette.of(context).inputBgEmpty,
      onPressed: _pickPoi,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              (_form.addressName ?? '').isEmpty
                  ? '请输入活动地点'
                  : _form.addressName!,
              style: TextStyle(
                color: (_form.addressName ?? '').isEmpty
                    ? CyPalette.of(context).textPlaceholder
                    : CyPalette.of(context).textPrimary,
              ),
            ),
          ),
          const Icon(CupertinoIcons.location, size: 18),
        ],
      ),
    ),
    const SizedBox(height: CyTokens.space3),
    _DateRow(
      label: '开始时间',
      value: _form.startDate,
      keyName: 'activity-start',
      onTap: () => _pickDate(start: true),
    ),
    _DateRow(
      label: '结束时间',
      value: _form.endDate,
      keyName: 'activity-end',
      onTap: () => _pickDate(start: false),
    ),
    const SizedBox(height: CyTokens.space2),
    _SelectionRow(
      key: const Key('activity-categories'),
      label: '活动类型',
      value: _selectedCategories.isEmpty
          ? '请选择至少一个活动类型'
          : _selectedCategories.map((Category item) => item.name).join('、'),
      empty: _selectedCategories.isEmpty,
      onTap: _pickCategories,
    ),
  ];

  /// 传封面。★ 失败不清掉已有的图(同玩法编辑器)。
  Future<void> _pickCover() async {
    setState(() => _uploadingCover = true);
    try {
      final List<String>? urls = await pickCropAndUploadPublishImages(
        context,
        ref,
        maxCount: 1,
        aspect: PublishCropAspect.landscape16x9,
      );
      if (urls != null && urls.isNotEmpty && mounted) {
        setState(() => _form = _form.copyWith(imgUrl: urls.first));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  List<Widget> _content() => <Widget>[
    _field(
      key: const Key('activity-desc'),
      label: '活动说明',
      placeholder: '活动说明',
      maxLines: 6,
      onChanged: (String v) => _form = _form.copyWith(description: v),
    ),
    const SizedBox(height: CyTokens.space3),
    // ⚠️ 我建这页时漏了封面输入 —— 而 ActivityPublishForm 一直有 imgUrl,
    //   toJson 也一直在发。**和玩法编辑器那次一模一样的错,我自己刚犯过**:
    //   模型支持、接口收、界面没地方填 ⇒ 永远发空。
    if ((_form.imgUrl ?? '').isEmpty)
      CupertinoButton(
        key: const Key('activity-cover-upload'),
        minimumSize: const Size.fromHeight(44),
        color: CyPalette.of(context).actionSecondaryBg,
        onPressed: _uploadingCover ? null : _pickCover,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(CupertinoIcons.photo, size: 18),
            const SizedBox(width: CyTokens.space2),
            Text(_uploadingCover ? '上传中…' : uploadHint('活动封面', kHint16x9)),
          ],
        ),
      )
    else
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            child: CyNetImage(
              _form.imgUrl,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Row(
            children: <Widget>[
              CupertinoButton(
                key: const Key('activity-cover-replace'),
                minimumSize: const Size(44, 44),
                onPressed: _uploadingCover ? null : _pickCover,
                child: const Text('换一张'),
              ),
              CupertinoButton(
                key: const Key('activity-cover-remove'),
                minimumSize: const Size(44, 44),
                onPressed: _uploadingCover
                    ? null
                    : () => setState(() => _form = _form.copyWith(imgUrl: '')),
                child: const Text('移除'),
              ),
            ],
          ),
        ],
      ),
    const SizedBox(height: CyTokens.space3),
    _SelectionRow(
      key: const Key('activity-template'),
      label: '引用我的模板',
      value: _selectedTemplate?.title ?? '请选择模板',
      empty: _selectedTemplate == null,
      onTap: _pickTemplate,
    ),
  ];

  /// 已选合作者的名字,只为显示。★ 提交只发 id;
  /// 名字随选随记,不再去查一次 —— 那会为了一行字多打一次后端。
  final Map<int, String> _collaboratorNames = <int, String>{};

  List<Widget> _collaborators() => <Widget>[
    for (final int id in _form.collaborators)
      Row(
        key: Key('collaborator-$id'),
        children: <Widget>[
          Expanded(child: Text(_collaboratorNames[id] ?? '用户 #$id')),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () => setState(
              () => _form = _form.copyWith(
                collaborators: _form.collaborators
                    .where((int x) => x != id)
                    .toList(),
              ),
            ),
            child: const Icon(CupertinoIcons.xmark, size: 16),
          ),
        ],
      ),
    CupertinoButton(
      key: const Key('activity-add-collaborator'),
      minimumSize: const Size.fromHeight(44),
      color: CyPalette.of(context).actionSecondaryBg,
      onPressed: () async {
        final CollaboratorCandidate? picked = await showCollaboratorPicker(
          context,
          alreadyPicked: _form.collaborators,
        );
        if (picked == null || !mounted) return;
        setState(() {
          _collaboratorNames[picked.id] = picked.name;
          _form = _form.copyWith(
            collaborators: <int>[..._form.collaborators, picked.id],
          );
        });
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(CupertinoIcons.person_add, size: 18),
          SizedBox(width: CyTokens.space2),
          Text('添加合作者'),
        ],
      ),
    ),
  ];

  List<Widget> _ticket() => <Widget>[
    for (int i = 0; i < _form.tickets.length; i++)
      _TicketCard(
        index: i,
        draft: _form.tickets[i],
        onChanged: (TicketDraft t) {
          final List<TicketDraft> next = _form.tickets.toList()..[i] = t;
          setState(() => _form = _form.copyWith(tickets: next));
        },
        onRemove: () {
          final List<TicketDraft> next = _form.tickets.toList()..removeAt(i);
          setState(() => _form = _form.copyWith(tickets: next));
        },
      ),
    const SizedBox(height: CyTokens.space3),
    CupertinoButton(
      key: const Key('activity-add-ticket'),
      minimumSize: const Size.fromHeight(44),
      color: CyPalette.of(context).actionSecondaryBg,
      onPressed: () => setState(
        () => _form = _form.copyWith(
          tickets: <TicketDraft>[
            ..._form.tickets,
            TicketDraft(startTime: _form.startDate, endTime: _form.endDate),
          ],
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(CupertinoIcons.add, size: 18),
          SizedBox(width: CyTokens.space2),
          Text('添加一张票'),
        ],
      ),
    ),
  ];
}

/// 未解锁时**换一整张卡**说清怎么解锁 —— 不是灰按钮。
class _LockedCard extends StatelessWidget {
  const _LockedCard();
  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(CupertinoIcons.lock, size: 32, color: p.textTertiary),
            const SizedBox(height: CyTokens.space3),
            Text(
              '仅俱乐部主理人可发布活动',
              key: const Key('publish-activity-locked'),
              style: TextStyle(
                fontSize: CyTokens.typeCardTitle,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            Text(
              '成为主理人后解锁。普通用户可以发布主题/路线。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: p.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.titles});
  final int step;
  final List<String> titles;
  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < titles.length; i++)
            Expanded(
              child: Column(
                children: <Widget>[
                  Container(
                    height: 2,
                    color: i <= step ? p.textPrimary : p.borderSubtle,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1} ${titles[i]}',
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: i <= step ? p.textPrimary : p.textTertiary,
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

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.keyName,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CupertinoButton(
      key: Key(keyName),
      minimumSize: const Size.fromHeight(48),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.centerLeft,
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: p.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              // ★ 没选就说「未选择」,不显示一个默认日期 ——
              //   默认日期会被当成已经选好了。
              value == null
                  ? '未选择'
                  : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-'
                        '${value!.day.toString().padLeft(2, '0')} '
                        '${value!.hour.toString().padLeft(2, '0')}:'
                        '${value!.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: value == null ? p.textTertiary : p.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    super.key,
    required this.label,
    required this.value,
    required this.empty,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      minimumSize: const Size.fromHeight(52),
      padding: EdgeInsets.zero,
      foregroundColor: palette.textPrimary,
      onPressed: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
        decoration: BoxDecoration(
          color: palette.inputBgEmpty,
          border: Border.all(color: palette.borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            Text(label, style: TextStyle(color: palette.textSecondary)),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: empty ? palette.textPlaceholder : palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space1),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });
  final int index;
  final TicketDraft draft;
  final ValueChanged<TicketDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '第 ${index + 1} 张票',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: p.textTertiary,
                ),
              ),
              const Spacer(),
              // 44pt 热区。
              SizedBox(
                width: 44,
                height: 44,
                child: CupertinoButton(
                  key: Key('ticket-remove-$index'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                  child: const Icon(CupertinoIcons.xmark, size: 16),
                ),
              ),
            ],
          ),
          CupertinoTextField(
            key: Key('ticket-name-$index'),
            placeholder: '请输入票单名称',
            textInputAction: TextInputAction.next,
            autocorrect: true,
            enableSuggestions: true,
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: p.inputBgEmpty,
              border: Border.all(color: p.borderSubtle),
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            onChanged: (String v) => onChanged(
              TicketDraft(
                name: v,
                price: draft.price,
                startTime: draft.startTime,
                endTime: draft.endTime,
                totalStock: draft.totalStock,
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            key: Key('ticket-price-$index'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            // ★ 提示写「免费填 0」—— 留空和填 0 是两回事,模型也是这么分的。
            placeholder: '价格(免费填 0)',
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: p.inputBgEmpty,
              border: Border.all(color: p.borderSubtle),
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            onChanged: (String v) => onChanged(
              TicketDraft(
                name: draft.name,
                price: v.trim().isEmpty ? null : double.tryParse(v.trim()),
                startTime: draft.startTime,
                endTime: draft.endTime,
                totalStock: draft.totalStock,
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          CupertinoTextField(
            key: Key('ticket-stock-$index'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            placeholder: '总库存',
            padding: const EdgeInsets.all(CyTokens.space3),
            decoration: BoxDecoration(
              color: p.inputBgEmpty,
              border: Border.all(color: p.borderSubtle),
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            onChanged: (String v) => onChanged(
              TicketDraft(
                name: draft.name,
                price: draft.price,
                startTime: draft.startTime,
                endTime: draft.endTime,
                totalStock: v.trim().isEmpty ? null : int.tryParse(v.trim()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.last,
    required this.submitting,
    required this.blocker,
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });
  final int step;
  final bool last;
  final bool submitting;
  final String? blocker;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space4),
        child: Row(
          children: <Widget>[
            if (onBack != null)
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: CupertinoButton(
                    key: const Key('activity-back'),
                    minimumSize: const Size.fromHeight(44),
                    color: CyPalette.of(context).actionSecondaryBg,
                    onPressed: onBack,
                    child: const Text('上一步'),
                  ),
                ),
              ),
            if (onBack != null) const SizedBox(width: CyTokens.space3),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 44,
                child: CupertinoButton(
                  key: const Key('activity-primary'),
                  minimumSize: const Size.fromHeight(44),
                  color: CyPalette.of(context).actionPrimaryBg,
                  disabledColor: CyPalette.of(context).actionSecondaryBg,
                  onPressed: submitting ? null : (last ? onSubmit : onNext),
                  child: Text(
                    submitting ? '提交中…' : (last ? '发布' : '下一步'),
                    style: TextStyle(
                      color: submitting
                          ? CyPalette.of(context).textDisabled
                          : CyPalette.of(context).actionPrimaryFg,
                    ),
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
