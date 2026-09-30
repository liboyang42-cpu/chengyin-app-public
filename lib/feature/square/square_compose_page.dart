import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' show DioException;

import '../../core/widgets/cy_confirm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/feature_flags.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/square_api.dart';
import '../../data/models/completed_play.dart';
import '../../data/models/square_draft.dart';
import '../../data/models/square_post.dart';
import '../play/my_plays_page.dart';
import '../auth/auth_controller.dart';
import 'square_controller.dart';
import 'square_local_draft_store.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_notice.dart';

const Map<String, String> _safetyLabelOptions = <String, String>{
  'DANGEROUS_ACTIVITY': '危险活动',
  'SENSITIVE_CONTENT': '敏感内容',
  'FLASHING_IMAGES': '闪烁画面',
  'SPOILER': '剧透',
  'TEMPORARY_CLOSURE': '临时关闭',
  'ACCESSIBILITY_LIMIT': '无障碍限制',
  'WEATHER_RISK': '天气风险',
};

/// 小程序 `components/cy/post-compose` 的 `MAX_PICS`:一条帖最多 6 张图。
const int _maxComposePics = 6;

enum SquareComposeIntent { photo, location, route }

SquareComposeIntent? squareComposeIntentFromValue(String? value) {
  return switch (value) {
    'photo' => SquareComposeIntent.photo,
    'location' => SquareComposeIntent.location,
    'route' => SquareComposeIntent.route,
    _ => null,
  };
}

/// 专业广场发帖：在 Threads 式轻量编辑器中补齐城瘾的业务关联与对话策略。
class SquareComposePage extends ConsumerStatefulWidget {
  const SquareComposePage({super.key, this.initialPost, this.initialIntent});

  final SquarePost? initialPost;
  final SquareComposeIntent? initialIntent;

  @override
  ConsumerState<SquareComposePage> createState() => _SquareComposePageState();
}

class _SquareComposePageState extends ConsumerState<SquareComposePage>
    with WidgetsBindingObserver {
  late SquareDraft _draft;
  String? _linkName;
  late final TextEditingController _contentController;
  bool _busy = false;
  bool _uploading = false;
  bool _completed = false;
  late final SquareLocalDraftStore _localDraftStore;
  int? _draftOwnerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localDraftStore = ref.read(squareLocalDraftStoreProvider);
    _draftOwnerId = ref.read(authControllerProvider).user?.id;
    final post = widget.initialPost;
    _draft = post == null
        ? SquareDraft(
            workflowId: 'square-${DateTime.now().microsecondsSinceEpoch}',
          )
        : SquareDraft(
            workflowId:
                'square-edit-${post.id}-${DateTime.now().microsecondsSinceEpoch}',
            id: post.id,
            expectedVersion: post.version,
            sourceLifecycle: post.lifecycle,
            contents: post.contents ?? '',
            pics: post.pics,
            existingMediaIds: post.mediaIds,
            existingPicCount: post.pics.length,
            address: post.address,
            cityCode: post.cityCode,
            // 关联要原样带进编辑态:后端对 data_id 是「无值即清 0」,不发就把旧关联清掉。
            dataId: post.dataId,
            dataType: post.dataType,
            referenceType: post.referenceType,
            referenceId: post.referenceId,
            communityId: post.communityId,
            audience: post.audience,
            commentPolicy: post.commentPolicy,
            replyApprovalEnabled: post.replyApprovalEnabled,
            slowModeSeconds: post.slowModeSeconds,
            disclosureType: post.disclosureType,
            mentionedMemberIds: post.mentionedMemberIds,
            safetyLabels: post.safetyLabels,
          );
    _contentController = TextEditingController(text: _draft.contents);
    _linkName = post?.sportName;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreLocalDraft();
      if (!mounted || widget.initialPost != null) return;
      switch (widget.initialIntent) {
        case SquareComposeIntent.photo:
          await _addPhoto();
        case SquareComposeIntent.location:
          await _pickLocation();
        case SquareComposeIntent.route:
          await _pickReferenceOption('ROUTE', '路线');
        case null:
          break;
      }
    });
  }

  Future<void> _restoreLocalDraft() async {
    final ownerId = _draftOwnerId;
    if (ownerId == null || ownerId <= 0) return;
    final editingId = widget.initialPost?.id;
    final restored = await _localDraftStore.read(ownerId, postId: editingId);
    if (!mounted || restored == null) return;
    if (editingId != null && restored.id != editingId) return;
    if (editingId == null && restored.id != null) return;
    if (editingId == null &&
        (_draft.canSave || _contentController.text.trim().isNotEmpty)) {
      return;
    }
    setState(() {
      _draft = restored;
      _contentController.text = restored.contents;
    });
    CyNativeNotice.show(context, '已恢复上次未保存的草稿');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_persistLocalDraft());
    _contentController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistLocalDraft());
    }
  }

  Future<bool> _persistLocalDraft() async {
    final ownerId = _draftOwnerId;
    if (_completed || ownerId == null || ownerId <= 0 || !_draft.canSave) {
      return false;
    }
    return _localDraftStore.save(ownerId, _draft);
  }

  Future<void> _addPhoto() async {
    if (_draft.pics.length >= _maxComposePics) {
      CyNativeNotice.show(context, '最多 $_maxComposePics 张图片');
      return;
    }
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      // 走仓内既有的 `/api/common/uploadOSS` 上传:后端只回 fileName/url
      // (没有 v1 那套 byteSize/mimeType/uploadReceipt 回执),发布也只吃 pics 里的地址。
      final String url = await ref.read(playApiProvider).uploadImage(file.path);
      if (!mounted) return;
      setState(
        () => _draft = _draft.copyWith(
          pics: <String>[..._draft.pics, url],
          // 三条并行列表要跟着 pics 等长(v1 媒体登记那条链路按长度校验);
          // 后端没给这些字段,就如实留空,不编一个假回执。
          picByteSizes: <int>[..._draft.picByteSizes, 0],
          picMimeTypes: <String>[..._draft.picMimeTypes, ''],
          picUploadReceipts: <String>[..._draft.picUploadReceipts, ''],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        '图片没传上去:${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 选择地点。小程序在发布帖文的图片和活动之间提供这个入口，
  /// App 复用已有地图选点页，返回后仍停在当前发布页。
  Future<void> _pickLocation() async {
    final result = await context
        .push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (result == null || !mounted) return;
    String? cityCode;
    try {
      final city = await ref
          .read(mapApiProvider)
          .reverseGeocode(
            longitude: result.longitude,
            latitude: result.latitude,
          );
      if (city.resolved && city.city.trim().isNotEmpty) {
        cityCode = city.city.trim();
      }
    } catch (_) {
      cityCode = null;
    }
    if (!mounted) return;
    if ((cityCode ?? '').isEmpty) {
      CyNativeNotice.show(context, '未能识别地点所在城市，请重新选择', isError: true);
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        address: result.name,
        cityCode: cityCode,
        longitude: result.longitude.toString(),
        latitude: result.latitude.toString(),
      );
    });
  }

  void _clearLocation() {
    setState(() {
      _draft = SquareDraft(
        workflowId: _draft.workflowId,
        id: _draft.id,
        expectedVersion: _draft.expectedVersion,
        contents: _draft.contents,
        pics: _draft.pics,
        picByteSizes: _draft.picByteSizes,
        picMimeTypes: _draft.picMimeTypes,
        picUploadReceipts: _draft.picUploadReceipts,
        existingMediaIds: _draft.existingMediaIds,
        existingPicCount: _draft.existingPicCount,
        dataId: _draft.dataId,
        dataType: _draft.dataType,
        referenceType: _draft.referenceType,
        referenceId: _draft.referenceId,
        communityId: _draft.communityId,
        audience: _draft.audience,
        commentPolicy: _draft.commentPolicy,
        replyApprovalEnabled: _draft.replyApprovalEnabled,
        slowModeSeconds: _draft.slowModeSeconds,
        disclosureType: _draft.disclosureType,
        mentionedMemberIds: _draft.mentionedMemberIds,
        safetyLabels: _draft.safetyLabels,
      );
    });
  }

  /// 选一局已完成的活动关联进来(对齐小程序 activity-picker 组件)。
  Future<void> _pickPlay() async {
    final picked = await showCupertinoSheet<CompletedPlay>(
      context: context,
      showDragHandle: true,
      topGap: 0.28,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _PlayPicker(scrollController: scrollController),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // dataType 与 dataId 必须同时给,否则关联态不自洽。
      _draft = _draft.copyWith(
        dataId: picked.activityId != null && picked.activityId! > 0
            ? picked.activityId
            : picked.topicId,
        dataType: picked.activityId != null && picked.activityId! > 0 ? 1 : 2,
        referenceType: picked.activityId != null && picked.activityId! > 0
            ? 'ACTIVITY'
            : 'TOPIC',
        referenceId: picked.activityId != null && picked.activityId! > 0
            ? picked.activityId
            : picked.topicId,
      );
      _linkName = picked.name;
    });
  }

  Future<void> _pickReferenceOption(String type, String title) async {
    try {
      final options = await ref.read(squareApiProvider).referenceOptions(type);
      if (!mounted) return;
      if (options.isEmpty) {
        CyNativeNotice.show(context, '暂无可关联的$title');
        return;
      }
      final selectedId = await showCupertinoModalPopup<int>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text('关联$title'),
          actions: options
              .map(
                (option) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(
                    sheetContext,
                  ).pop((option['id'] as num?)?.toInt()),
                  child: Text('${option['name'] ?? title}'),
                ),
              )
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selectedId == null || !mounted) return;
      final selected = options.firstWhere(
        (option) => (option['id'] as num?)?.toInt() == selectedId,
      );
      setState(() {
        _draft = _draft.copyWith(
          dataId: selectedId,
          dataType: type == 'ROUTE' ? 3 : 5,
          referenceType: type,
          referenceId: selectedId,
          address: type == 'POI' ? '${selected['name'] ?? ''}' : _draft.address,
          cityCode: type == 'POI'
              ? '${selected['city_code'] ?? selected['cityCode'] ?? ''}'
              : _draft.cityCode,
        );
        _linkName = '${selected['name'] ?? title}';
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickClub() async {
    try {
      final clubs = await ref.read(clubApiProvider).my();
      if (!mounted) return;
      if (clubs.isEmpty) {
        CyNativeNotice.show(context, '你还没有加入可关联的俱乐部');
        return;
      }
      final selectedId = await showCupertinoModalPopup<int>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('关联俱乐部'),
          actions: clubs
              .map(
                (club) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(club.id),
                  child: Text(club.name),
                ),
              )
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selectedId == null || !mounted) return;
      final selected = clubs.firstWhere((club) => club.id == selectedId);
      setState(() {
        _draft = _draft.copyWith(
          referenceType: 'CLUB',
          referenceId: selected.id,
          communityId: selected.id,
          audience: 'COMMUNITY',
        );
        _linkName = selected.name;
      });
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _pickMention() async {
    try {
      final members = await ref
          .read(squareApiProvider)
          .referenceOptions('MEMBER');
      if (!mounted) return;
      final available = members
          .where(
            (member) => !_draft.mentionedMemberIds.contains(
              (member['id'] as num?)?.toInt(),
            ),
          )
          .toList(growable: false);
      if (available.isEmpty) {
        CyNativeNotice.show(context, '暂无更多可提及的关注用户');
        return;
      }
      final selectedId = await showCupertinoModalPopup<int>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const Text('选择可以回复的人'),
          actions: available
              .map(
                (member) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(
                    sheetContext,
                  ).pop((member['id'] as num?)?.toInt()),
                  child: Text('${member['name'] ?? '城瘾用户'}'),
                ),
              )
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );
      if (selectedId == null || !mounted) return;
      setState(
        () => _draft = _draft.copyWith(
          mentionedMemberIds: <int>[..._draft.mentionedMemberIds, selectedId],
        ),
      );
    } catch (error) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<String?> _pickPolicy(String title, Map<String, String> options) =>
      showCupertinoModalPopup<String>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: Text(title),
          actions: options.entries
              .map(
                (MapEntry<String, String> entry) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(entry.key),
                  child: Text(entry.value),
                ),
              )
              .toList(growable: false),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('取消'),
          ),
        ),
      );

  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    if (_draft.id != null && _draft.sourceLifecycle != 'DRAFT') {
      final saved = await _persistLocalDraft();
      if (mounted) {
        if (saved) {
          CyNativeNotice.show(context, '修改稿已保存在本机，提交时会重新审核');
        } else {
          CyNativeNotice.show(context, '本机修改稿保存失败，请先复制正文', isError: true);
        }
        setState(() => _busy = false);
      }
      return;
    }
    if (!ref.read(featureFlagProvider('communityPostWrite'))) {
      final saved = await _persistLocalDraft();
      if (mounted) {
        if (saved) {
          CyNativeNotice.show(context, '已保存在本机，恢复发布后可继续');
        } else {
          CyNativeNotice.show(context, '本机草稿保存失败，请先复制正文', isError: true);
        }
        setState(() => _busy = false);
      }
      return;
    }
    try {
      final api = ref.read(squareApiProvider);
      final guideline = await api.activeGuideline();
      final int guidelineId = (guideline['id'] as num?)?.toInt() ?? 0;
      if (guidelineId <= 0) throw SquarePublishException('社区规范尚未启用');
      await api.saveDraft(_draft, guidelineVersionId: guidelineId);
      _completed = true;
      final ownerId = _draftOwnerId;
      if (ownerId != null) {
        await _localDraftStore.clear(ownerId, postId: _draft.id);
      }
      ref.invalidate(squareDraftsProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, '草稿已保存');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      final saved = await _persistLocalDraft();
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        saved
            ? '${e.toString().replaceFirst('Exception: ', '')}，已保存在本机'
            : '${e.toString().replaceFirst('Exception: ', '')}；本机草稿也保存失败，请先复制正文',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final String contents = _draft.contents.trim();
    // 小程序同款必填闸:发布键的禁用只是视觉,真正的校验这一句。
    if (contents.isEmpty) {
      CyNativeNotice.show(context, '请输入内容');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 与小程序同一条端点、同一组字段:`/api/creativesquare/action`。
      // 编辑态只发 id + 正文 + 关联,图片/地点由后端保留原值(R10-06)。
      await ref
          .read(squareApiProvider)
          .publishPost(
            id: _draft.id,
            contents: contents,
            pics: _draft.pics,
            address: _draft.address,
            longitude: _draft.longitude,
            latitude: _draft.latitude,
            dataId: _draft.dataId,
            dataType: _draft.dataType,
            requestId: _draft.workflowId,
          );
      _completed = true;
      final ownerId = _draftOwnerId;
      if (ownerId != null) {
        await _localDraftStore.clear(ownerId, postId: _draft.id);
      }
      ref.invalidate(squareListProvider);
      if (!mounted) return;
      // 回列表/详情并刷新就是回执:新帖会出现在列表第一条(详情页回来时自己重读)。
      CyNativeNotice.show(context, widget.initialPost == null ? '已发布' : '已保存');
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      // ★ 三分:权限 / 内容被拒 / 真故障。前两类**不给重试** ——
      //   重试一万次也不会变成自己的帖,也不会让违规文案通过。
      if (e is SquarePublishException && !e.retryable) {
        await cyConfirm(
          context,
          title: e.isNotOwner ? '不能编辑这条内容' : '内容没能通过审核',
          content: e.isNotOwner ? e.message : '${e.message}\n\n请修改文字后再发布。',
          confirmText: e.isNotOwner ? '知道了' : '去修改',
          showCancel: false,
        );
        return;
      }
      final String message = _publishFailureText(e);
      final saved = await _persistLocalDraft();
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        saved ? '$message，已保存在本机' : '$message；本机草稿也保存失败，请先复制正文',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 失败原文透传:后端的话照说;网络层的英文异常换成小程序同款人话
  /// (两者用户要做的事不一样 —— 一个改内容,一个看网络)。
  String _publishFailureText(Object error) {
    if (error is SquarePublishException) return error.message;
    if (error is DioException) return '网络错误，请检查连接后重试';
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final blocker = _draft.blocker;
    final writeEnabled = ref.watch(featureFlagProvider('communityPostWrite'));
    // 编辑态只有正文 + 关联能提交(R10-06):图片/地点后端保留原值 ——
    // 工具摆出来却提交不上去,就是骗用户(小程序为此整块收起了附件工具)。
    final bool editing = widget.initialPost != null;

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.initialPost == null ? '发布帖文' : '编辑帖文'),
        // 真源 components/cy/post-compose/index.wxml topbar 的「草稿箱」钮:
        // 草稿是「新建」的存档,编辑态正文不回草稿槽,所以只在非编辑态给入口。
        trailing: widget.initialPost == null
            ? Semantics(
                button: true,
                label: '草稿箱',
                child: CupertinoButton(
                  key: const Key('square-compose-drafts-entry'),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  onPressed: () => context.push('/square/drafts'),
                  child: const Text('草稿箱'),
                ),
              )
            : null,
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              children: <Widget>[
                if (!writeEnabled) ...<Widget>[
                  Container(
                    key: Key('community-post-write-closed'),
                    padding: const EdgeInsets.all(CyTokens.space3),
                    decoration: BoxDecoration(
                      color: palette.bgSubtle,
                      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      border: Border.all(color: palette.borderSubtle),
                    ),
                    child: const Text('发布暂停。你可继续编辑并保存到本机，恢复后再发布。'),
                  ),
                  const SizedBox(height: CyTokens.space3),
                ],
                CupertinoTextField(
                  key: const Key('square-compose-content'),
                  controller: _contentController,
                  maxLines: 6,
                  minLines: 4,
                  maxLength: 5000,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  placeholder: '有什么新鲜好玩的分享吗？',
                  placeholderStyle: textTheme.bodyLarge?.copyWith(
                    color: palette.textPlaceholder,
                  ),
                  style: textTheme.bodyLarge?.copyWith(
                    color: palette.textPrimary,
                  ),
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: BoxDecoration(
                    color: palette.inputBgEmpty,
                    borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  onChanged: (String v) =>
                      setState(() => _draft = _draft.copyWith(contents: v)),
                ),
                if (!editing) ...<Widget>[
                  const SizedBox(height: CyTokens.space3),
                  Wrap(
                    spacing: CyTokens.space2,
                    runSpacing: CyTokens.space2,
                    children: <Widget>[
                      ..._draft.pics.asMap().entries.map(
                        (MapEntry<int, String> entry) => SquareComposeThumb(
                          url: entry.value,
                          onRemove: () => setState(() {
                            final pics = <String>[..._draft.pics]
                              ..removeAt(entry.key);
                            final existingIds = <int>[
                              ..._draft.existingMediaIds,
                            ];
                            var existingPicCount = _draft.existingPicCount;
                            final sizes = <int>[..._draft.picByteSizes];
                            final mimes = <String>[..._draft.picMimeTypes];
                            final receipts = <String>[
                              ..._draft.picUploadReceipts,
                            ];
                            if (entry.key < existingPicCount) {
                              existingIds.removeAt(entry.key);
                              existingPicCount--;
                            } else {
                              final newIndex = entry.key - existingPicCount;
                              sizes.removeAt(newIndex);
                              mimes.removeAt(newIndex);
                              receipts.removeAt(newIndex);
                            }
                            _draft = _draft.copyWith(
                              pics: pics,
                              existingMediaIds: existingIds,
                              existingPicCount: existingPicCount,
                              picByteSizes: sizes,
                              picMimeTypes: mimes,
                              picUploadReceipts: receipts,
                            );
                          }),
                        ),
                      ),
                      CupertinoButton.tinted(
                        key: const Key('square-compose-photo'),
                        onPressed: _uploading ? null : _addPhoto,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              CupertinoIcons.photo_on_rectangle,
                              size: 18,
                            ),
                            const SizedBox(width: CyTokens.space1),
                            Text(_uploading ? '上传中…' : '照片'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (!editing) ...<Widget>[
                  const SizedBox(height: CyTokens.space4),
                  const CySectionTitle('地点'),
                  const SizedBox(height: CyTokens.space2),
                  if ((_draft.address ?? '').isEmpty)
                    CupertinoButton.tinted(
                      key: const Key('square-compose-location'),
                      minimumSize: const Size.fromHeight(44),
                      onPressed: _pickLocation,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(CupertinoIcons.location, size: 18),
                          SizedBox(width: CyTokens.space1),
                          Text('选择地点'),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: <Widget>[
                        const Icon(CupertinoIcons.location_fill, size: 18),
                        const SizedBox(width: CyTokens.space2),
                        Expanded(child: Text(_draft.address!)),
                        CupertinoButton(
                          key: const Key('square-compose-location-clear'),
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          onPressed: _clearLocation,
                          child: const Icon(CupertinoIcons.xmark_circle_fill),
                        ),
                      ],
                    ),
                ],
                if (!editing) ...<Widget>[
                  const SizedBox(height: CyTokens.space4),
                  const CySectionTitle('关联城市内容'),
                  const SizedBox(height: CyTokens.space2),
                  if (_linkName == null)
                    Wrap(
                      spacing: CyTokens.space2,
                      runSpacing: CyTokens.space2,
                      children: <Widget>[
                        CupertinoButton.tinted(
                          key: const Key('square-compose-activity'),
                          onPressed: _pickPlay,
                          child: const Text('活动 / 主题'),
                        ),
                        CupertinoButton.tinted(
                          key: const Key('square-compose-route'),
                          onPressed: () => _pickReferenceOption('ROUTE', '路线'),
                          child: const Text('路线'),
                        ),
                        CupertinoButton.tinted(
                          key: const Key('square-compose-poi'),
                          onPressed: () => _pickReferenceOption('POI', '地点'),
                          child: const Text('地点'),
                        ),
                        CupertinoButton.tinted(
                          key: const Key('square-compose-club'),
                          onPressed: _pickClub,
                          child: const Text('俱乐部'),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(_linkName!, style: textTheme.bodyMedium),
                        ),
                        CupertinoButton(
                          // ★ 取消关联要**同时**清 dataId 与 dataType,
                          //   只清一个会留下自相矛盾的状态 —— 所以用 withoutLink 而不是 copyWith。
                          onPressed: () => setState(() {
                            _draft = _draft.withoutLink();
                            _linkName = null;
                          }),
                          child: const Text('取消关联'),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: CyTokens.space4),
                const CySectionTitle('发布与对话'),
                const SizedBox(height: CyTokens.space2),
                _ComposePolicyRow(
                  key: const Key('square-compose-audience'),
                  title: '谁可以看到',
                  value: <String, String>{
                    'PUBLIC': '所有人',
                    'FOLLOWERS': '关注者',
                    if (_draft.communityId != null) 'COMMUNITY': '俱乐部成员',
                    'PRIVATE': '仅自己',
                  }[_draft.audience]!,
                  onPressed: () async {
                    final value = await _pickPolicy('谁可以看到', <String, String>{
                      'PUBLIC': '所有人',
                      'FOLLOWERS': '关注者',
                      if (_draft.communityId != null) 'COMMUNITY': '俱乐部成员',
                      'PRIVATE': '仅自己',
                    });
                    if (value != null && mounted) {
                      setState(() => _draft = _draft.copyWith(audience: value));
                    }
                  },
                ),
                _ComposePolicyRow(
                  key: const Key('square-compose-comment-policy'),
                  title: '谁可以回复',
                  value: <String, String>{
                    'EVERYONE': '所有人',
                    'FOLLOWERS': '关注者',
                    if (_draft.communityId != null) 'MEMBERS': '俱乐部成员',
                    'MENTIONED': '仅提及的人',
                    'OFF': '关闭回复',
                  }[_draft.commentPolicy]!,
                  onPressed: () async {
                    final value = await _pickPolicy('谁可以回复', <String, String>{
                      'EVERYONE': '所有人',
                      'FOLLOWERS': '关注者',
                      if (_draft.communityId != null) 'MEMBERS': '俱乐部成员',
                      'MENTIONED': '仅提及的人',
                      'OFF': '关闭回复',
                    });
                    if (value != null && mounted) {
                      setState(
                        () => _draft = _draft.copyWith(commentPolicy: value),
                      );
                    }
                  },
                ),
                if (_draft.commentPolicy == 'MENTIONED')
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CupertinoButton(
                          key: const Key('square-compose-mentions'),
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                          onPressed: _draft.mentionedMemberIds.length >= 10
                              ? null
                              : _pickMention,
                          child: Text(
                            _draft.mentionedMemberIds.isEmpty
                                ? '选择可以回复的人'
                                : '已选择 ${_draft.mentionedMemberIds.length} 人，继续添加',
                          ),
                        ),
                      ),
                      if (_draft.mentionedMemberIds.isNotEmpty)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(
                            () => _draft = _draft.copyWith(
                              mentionedMemberIds: const <int>[],
                            ),
                          ),
                          child: const Text('清空'),
                        ),
                    ],
                  ),
                _ComposePolicyRow(
                  key: const Key('square-compose-disclosure'),
                  title: '利益关系',
                  value: const <String, String>{
                    'NONE': '无',
                    'SPONSORED': '商业合作',
                    'GIFTED': '获赠体验',
                    'MERCHANT_OWNER': '商家主理人',
                    'MERCHANT_EMPLOYEE': '商家员工',
                  }[_draft.disclosureType]!,
                  onPressed: () async {
                    final value =
                        await _pickPolicy('利益关系披露', const <String, String>{
                          'NONE': '无',
                          'SPONSORED': '商业合作',
                          'GIFTED': '获赠体验',
                          'MERCHANT_OWNER': '商家主理人',
                          'MERCHANT_EMPLOYEE': '商家员工',
                        });
                    if (value != null && mounted) {
                      setState(
                        () => _draft = _draft.copyWith(disclosureType: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: CyTokens.space2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('内容与出行提示（可选）', style: textTheme.titleSmall),
                ),
                const SizedBox(height: CyTokens.space2),
                Wrap(
                  spacing: CyTokens.space2,
                  runSpacing: CyTokens.space2,
                  children: _safetyLabelOptions.entries
                      .map((entry) {
                        final selected = _draft.safetyLabels.contains(
                          entry.key,
                        );
                        return CupertinoButton.tinted(
                          key: Key('square-compose-safety-${entry.key}'),
                          // L9:表单里的贴片钮触达区同样 ≥44pt。
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onPressed: () => setState(() {
                            final labels = <String>[..._draft.safetyLabels];
                            if (selected) {
                              labels.remove(entry.key);
                            } else if (labels.length < 5) {
                              labels.add(entry.key);
                            }
                            _draft = _draft.copyWith(safetyLabels: labels);
                          }),
                          child: Text(
                            selected ? '✓ ${entry.value}' : entry.value,
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
                _ComposeSwitchRow(
                  key: const Key('square-compose-reply-approval'),
                  title: '回复先经我确认',
                  value: _draft.replyApprovalEnabled,
                  onChanged: (bool value) => setState(
                    () => _draft = _draft.copyWith(replyApprovalEnabled: value),
                  ),
                ),
                _ComposeSwitchRow(
                  key: const Key('square-compose-slow-mode'),
                  title: '慢速对话（每人 30 秒）',
                  value: _draft.slowModeSeconds > 0,
                  onChanged: (bool value) => setState(
                    () => _draft = _draft.copyWith(
                      slowModeSeconds: value ? 30 : 0,
                    ),
                  ),
                ),
                const SizedBox(height: CyTokens.space3),
                Text(
                  '发布即表示遵守《城市探索者公约》：真实、尊重在地、保护隐私、标注风险并如实披露利益关系。',
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                CyTokens.space3,
              ),
              child: Column(
                children: <Widget>[
                  if (blocker != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: Text(
                        blocker,
                        style: textTheme.bodySmall?.copyWith(
                          color: CyTokens.statusWarning,
                        ),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: CupertinoButton(
                          key: const Key('square-compose-save-draft'),
                          minimumSize: const Size.fromHeight(CyTokens.btnH),
                          color: palette.bgSubtle,
                          disabledColor: palette.bgSubtle,
                          foregroundColor: palette.textPrimary,
                          onPressed:
                              (!_draft.canSave ||
                                  !_draft.linkConsistent ||
                                  _busy)
                              ? null
                              : _saveDraft,
                          child: const Text('存草稿'),
                        ),
                      ),
                      const SizedBox(width: CyTokens.space2),
                      Expanded(
                        flex: 3,
                        child: CupertinoButton(
                          key: const Key('square-compose-submit'),
                          minimumSize: const Size.fromHeight(CyTokens.btnH),
                          color: palette.actionPrimaryBg,
                          disabledColor: palette.bgSubtle,
                          foregroundColor:
                              (!writeEnabled ||
                                  !_draft.canSubmit ||
                                  !_draft.linkConsistent ||
                                  _busy)
                              ? palette.textPlaceholder
                              : palette.actionPrimaryFg,
                          onPressed:
                              (!writeEnabled ||
                                  !_draft.canSubmit ||
                                  !_draft.linkConsistent ||
                                  _busy)
                              ? null
                              : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CupertinoActivityIndicator(),
                                )
                              : const Text('发布'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposePolicyRow extends StatelessWidget {
  const _ComposePolicyRow({
    super.key,
    required this.title,
    required this.value,
    required this.onPressed,
  });
  final String title;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    foregroundColor: CyPalette.of(context).textPrimary,
    onPressed: onPressed,
    child: Row(
      children: <Widget>[
        Expanded(child: Text(title)),
        Text(value),
        const SizedBox(width: CyTokens.space1),
        const Icon(CupertinoIcons.chevron_forward, size: 14),
      ],
    ),
  );
}

class _ComposeSwitchRow extends StatelessWidget {
  const _ComposeSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: <Widget>[
        Expanded(child: Text(title)),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

/// 已选图片的缩略图 + 删除钮。
///
/// ★★ 删除钮的**热区**与**视觉**是两回事:
///   视觉是右上角一个 18pt 的小圆叉(缩略图只有 80pt,画大了会盖住半张图);
///   热区必须 ≥44pt(iOS HIG / Material 的最小触达尺寸)。
///   用 [SizedBox] 撑热区 + [Alignment.topRight] 摆视觉,两者分开。
///
///   ⚠️ 原来只有 18pt 热区 —— 它压在图片角上、周围全是可滑动区域,
///     点不中就会连带触发滑动,用户会反复戳。
class SquareComposeThumb extends StatelessWidget {
  const SquareComposeThumb({
    super.key,
    required this.url,
    required this.onRemove,
  });

  /// 删除钮的 key,供测试量热区。
  static const Key removeKey = Key('square-compose-remove');

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          child: CyNetImage(url, width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Semantics(
            label: '删除图片',
            button: true,
            onTap: onRemove,
            excludeSemantics: true,
            child: CupertinoButton(
              key: SquareComposeThumb.removeKey,
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Align(
                  alignment: Alignment.topRight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CyTokens.overlay,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 选一局已完成的活动。数据复用「我走过的」。
class _PlayPicker extends ConsumerWidget {
  const _PlayPicker({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCompletedPlaysProvider);
    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('选择已完成的活动'),
        leading: CupertinoButton(
          key: const Key('square-play-picker-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (Object e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.space4),
              child: Text(
                '没能读到完成记录:'
                '${e.toString().replaceFirst('Exception: ', '')}',
              ),
            ),
          ),
          data: (List<CompletedPlay> rows) {
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(CyTokens.space4),
                  child: Text('还没有已通关的活动，去打卡通关后再来关联吧'),
                ),
              );
            }
            return ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space2,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: palette.borderSubtle),
              itemBuilder: (_, int i) {
                final CompletedPlay row = rows[i];
                return CupertinoButton(
                  key: Key('square-play-${row.activityId ?? row.topicId ?? i}'),
                  minimumSize: const Size.fromHeight(64),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  foregroundColor: palette.textPrimary,
                  onPressed: () => Navigator.of(context).pop(row),
                  child: Row(
                    children: <Widget>[
                      if ((row.cover ?? '').isNotEmpty) ...<Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusSm,
                          ),
                          child: CyNetImage(
                            row.cover!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: CyTokens.space3),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(row.name),
                            Text(
                              '完成 ${row.doneCount}/${row.total} · 已通关',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(CupertinoIcons.check_mark_circled_solid),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
