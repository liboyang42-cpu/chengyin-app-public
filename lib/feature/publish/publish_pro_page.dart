import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'collaborator_picker.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/publish_api.dart';
import '../../data/models/club.dart';
import '../../data/models/publish_draft.dart';
import '../../data/models/xp_budget.dart';
import '../auth/auth_controller.dart';
import '../publisher/publisher_identity.dart';
import '../publisher/publisher_identity_fields.dart';
import 'publish_draft_logic.dart';
import 'pro_editor_draft_store.dart';
import 'publish_pro_sheets.dart';
import 'publish_pro_story_editor.dart';
import 'publish_pro_ticket_tab.dart';
import 'publish_pro_utils.dart';

/// 专业发布编辑器:对齐小程序 pages/publish/fabu 主发布流程。
///
/// 两页平铺(创作 / 票务),底部导航条切页;右下药丸按页分工:
/// 创作页 =「预览 →」,票务页 =「检查并发布」。
///
/// ★ App 端口径简化(有意为之,见 worker_done 记录):
///   ① 待编排区未移植 —— 素材直接落进章节,节点保存时必须有地点;
///   ③ 招商/商家承接的章节级配置未移植(发布后在项目详情配置)。
///   (② 本地草稿自动保存已于 a1 线移植:pro_editor_draft_store.dart)
class PublishProPage extends ConsumerStatefulWidget {
  const PublishProPage({
    super.key,
    this.topicId,
    this.mode = kProductCity,
    this.initialDraft,
    this.initialClubId,
    this.merchantScope = false,
    this.resumeDraftUuid,
  });

  /// 编辑既有主题时传入;null = 新建草稿。
  final int? topicId;

  /// 新建时从发布 Sheet 带入的主题类型。编辑已有主题时以服务端回填为准。
  final int mode;

  /// 快速配置确认完点位后交接的可编辑草稿。
  final PublishDraft? initialDraft;

  /// 从俱乐部详情发起创建时预选归属俱乐部。
  final int? initialClubId;

  /// ?scope=MERCHANT(商家营销中心/AI洞察入口)。对齐真源 fabu onLoad 的
  /// `operationScope`:edit-detail、create/update 载荷、模板列表都带上它,
  /// 缺了会把商家发布记到个人名下。
  final bool merchantScope;

  /// ?draftUuid= 指定要续写的本地新草稿桶(真源 onLoad 同款;不带则按
  /// active 指针自动续最近一桶)。
  final String? resumeDraftUuid;

  @override
  ConsumerState<PublishProPage> createState() => _PublishProPageState();
}

class _PublishProPageState extends ConsumerState<PublishProPage> {
  final PublishDraft _draft = PublishDraft();
  final TextEditingController _nameCtrl = TextEditingController();
  int _localIdSeq = 0;
  int _editorPage = 1;
  bool _mapMode = false;

  // 编辑既有主题。
  bool _loadingEdit = false;
  String? _editError;
  PublishEditScope _editScope = PublishEditScope.full;
  bool _editLoaded = false;
  String? _lockedSnapshot;

  List<Club> _myClubs = <Club>[];
  String _role = 'player';

  bool _submitting = false;
  bool _prechecking = false;

  // RUN-52 发布者实名(挂进「发布前检查」弹层)。registered 只有真/假 ——
  // 接口不下发姓名与证件号;字段刻意不进 draft,免得混进主题提交 payload。
  final PublisherIdentityController _publisherIdentity =
      PublisherIdentityController(source: kIdentitySourceTopicPublish);
  // 本地草稿自动保存(真源 fabu _installDraftAutosave/_persistDraftEnvelope):
  // ready 前不写(回填未完成时写=把半成品落盘),写失败只提示一次。
  bool _autosaveReady = false;
  bool _saveWarned = false;
  String _draftMemberId = '';
  String _draftUuid = '';
  Timer? _autosaveTimer;

  // 退出守卫放行位:落盘成功后翻 true 再放行 pop(PopScope 的 canPop 以
  // 当帧 widget 为准,先 setState 再等一帧,pop 时守卫已撤)。
  bool _exitAllowed = false;

  // dispose 里的兜底落盘不能再碰 ref(riverpod 明令:卸载后读 ref 不安全),
  // 商店实例在 initState 就取好存字段。
  ProEditorDraftStore? _store;
  ProEditorDraftStore get _draftStore {
    final s = _store;
    if (s != null) return s;
    final fresh = ref.read(proEditorDraftStoreProvider);
    _store = fresh;
    return fresh;
  }

  String _localId() => 'local_${++_localIdSeq}';

  /// 真源口径:`operationScope` 只有 'MERCHANT' 与 ''(玩家)两值。
  String get operationScope => widget.merchantScope ? 'MERCHANT' : '';

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // 真源在 setData 缝上挂钩,没有「哪次改动算草稿改动」的显式清单 ——
    // 这里同款:每次重渲染合并成一次延迟落盘(密钥链写不能按击键打)。
    _scheduleAutosave();
  }

  @override
  void initState() {
    super.initState();
    _applyInitialDraft(widget.initialDraft);
    _draft.clubId ??= widget.initialClubId;
    final user = ref.read(authControllerProvider).user;
    _role = user?.effectiveRole ?? 'player';
    _store = ref.read(proEditorDraftStoreProvider);
    if (user != null && user.id > 0) {
      _draft.collaboratorIds = <int>[user.id];
    }
    _loadClubs();
    // 实名状态开页查一次:已登记的人不该在发布确认里再看到那三格
    // (值也永不下发,只有真/假)。查询失败按「未登记」处理 —— 宁可多问一次。
    _loadIdentityStatus();
    if (widget.topicId != null) {
      _loadEditDetail();
    } else {
      _bootstrapNewLocalDraft();
    }
  }

  Future<void> _loadIdentityStatus() async {
    if (await ref.read(publisherIdentityApiProvider).status()) {
      if (!mounted) return;
      _publisherIdentity.markRegistered();
    }
  }

  void _applyInitialDraft(PublishDraft? initial) {
    if (initial == null) {
      _draft.productType = widget.mode == kProductFreeExplore
          ? kProductFreeExplore
          : kProductCity;
      _draft.tickets = [defaultTicket(_draft.productType)];
      return;
    }
    final PublishDraft seed = initial.copy();
    // 真源 applyAiDraft 是整包回填;这里以前逐字段拷时漏了大半 ——
    // clubId(盘点 1350)/日期/封面/类别全掉,AI 方案进编辑器就变残草稿。
    _draft.name = seed.name;
    _draft.subtitle = seed.subtitle;
    _draft.description = seed.description;
    _draft.startDate = seed.startDate;
    _draft.endDate = seed.endDate;
    _draft.recruitDeadline = seed.recruitDeadline;
    _draft.imgUrl = seed.imgUrl;
    _draft.imgArr = seed.imgArr;
    _draft.categoryIds = List<int>.of(seed.categoryIds);
    _draft.categoryNames = List<String>.of(seed.categoryNames);
    _draft.productType = seed.productType;
    _draft.publishMode = seed.publishMode;
    _draft.chapters = seed.chapters;
    _draft.tickets = seed.tickets.isEmpty
        ? <PublishTicket>[defaultTicket(seed.productType)]
        : seed.tickets;
    _draft.selfPlay = seed.selfPlay;
    _draft.selfPlayPrice = seed.selfPlayPrice;
    _draft.selfPlayQuota = seed.selfPlayQuota;
    _draft.finishMedalName = seed.finishMedalName;
    _draft.finishMedalImg = seed.finishMedalImg;
    _draft.completeRewardCouponId = seed.completeRewardCouponId;
    _draft.publishToCreative = seed.publishToCreative;
    _draft.clubName = seed.clubName;
    _draft.openMerchantPool = seed.openMerchantPool;
    _draft.audioUrl = seed.audioUrl;
    _draft.audioDuration = seed.audioDuration;
    if (seed.collaboratorIds.isNotEmpty) {
      _draft.collaboratorIds = List<int>.of(seed.collaboratorIds);
    }
    _nameCtrl.text = seed.name;
    // AI 方案/简易版交接的草稿带着 clubId,之前这里逐字段拷贝时把它漏了 ——
    // 编辑器落回「无归属」,发布记到个人名下(盘点 1350 的丢 clubId)。
    _draft.clubId = seed.clubId;
  }

  @override
  void dispose() {
    _publisherIdentity.dispose();
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    // 离页兜底落盘(不等回调):goBack 守卫走的是 await 版,这里是最后一道。
    if (_autosaveReady) {
      _autosaveReady = false;
      unawaited(_persistDraftEnvelope());
    }
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 真源 goBack 的语义:能存下就安静离场;存不下要明说「现在走会丢」。
  /// iOS 侧返回手势/返回键统一被这个守卫接住。
  Future<void> _guardExit() async {
    if (_submitting || _exitAllowed) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!_autosaveReady || await _persistDraftEnvelope()) {
      await _leave();
      return;
    }
    if (!mounted) return;
    final force = await cyConfirm(
      context,
      title: '草稿还没有保存',
      content: '本机存储空间可能不足，直接返回会丢失本次修改。',
      confirmText: '仍要返回',
      cancelText: '继续编辑',
    );
    if (force) await _leave();
  }

  /// go_router 的 pop 走 maybePop,会再次撞守卫 —— 先放行 canPop,下一帧再退。
  Future<void> _leave() async {
    if (!mounted || _exitAllowed) return;
    setState(() => _exitAllowed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.pop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// 除我之外的合作者人数。
  int get _collaboratorCount {
    final int? me = ref.read(authControllerProvider).user?.id;
    return _draft.collaboratorIds.where((int id) => id != me).length;
  }

  Future<void> _pickCollaborator() async {
    final CollaboratorCandidate? picked = await showCollaboratorPicker(
      context,
      alreadyPicked: _draft.collaboratorIds,
    );
    if (picked == null || !mounted) return;
    // 去重:选择器已经把已选的置灰了,这里再挡一次 ——
    // 重复 id 传到后端会变成同一个人被邀两次。
    if (_draft.collaboratorIds.contains(picked.id)) return;
    setState(() => _draft.collaboratorIds.add(picked.id));
  }

  Future<void> _loadClubs() async {
    try {
      final clubs = await ref.read(clubApiProvider).my();
      if (!mounted) return;
      setState(() => _myClubs = clubs);
    } catch (_) {
      // 俱乐部列表拿不到不阻塞编辑器;需要俱乐部的校验按「无俱乐部」走。
    }
  }

  Future<void> _loadEditDetail() async {
    setState(() {
      _loadingEdit = true;
      _editError = null;
    });
    try {
      final (draft, scope) = await ref
          .read(publishApiProvider)
          .editDetail(widget.topicId!, scope: operationScope);
      if (!mounted) return;
      final user = ref.read(authControllerProvider).user;
      if (user != null &&
          user.id > 0 &&
          !draft.collaboratorIds.contains(user.id)) {
        draft.collaboratorIds.insert(0, user.id);
      }
      setState(() {
        _draft.name = draft.name;
        _draft.subtitle = draft.subtitle;
        _draft.description = draft.description;
        _draft.startDate = draft.startDate;
        _draft.endDate = draft.endDate;
        _draft.recruitDeadline = draft.recruitDeadline;
        _draft.imgUrl = draft.imgUrl;
        _draft.imgArr = draft.imgArr;
        _draft.categoryIds = List<int>.of(draft.categoryIds);
        _draft.productType = draft.productType;
        _draft.chapters = draft.chapters.map((c) => c.copy()).toList();
        _draft.tickets = draft.tickets.map((t) => t.copy()).toList();
        _draft.selfPlay = draft.selfPlay;
        _draft.selfPlayPrice = draft.selfPlayPrice;
        _draft.selfPlayQuota = draft.selfPlayQuota;
        _draft.finishMedalName = draft.finishMedalName;
        _draft.finishMedalImg = draft.finishMedalImg;
        _draft.completeRewardCouponId = draft.completeRewardCouponId;
        _draft.openMerchantPool = draft.openMerchantPool;
        _draft.publishMode = draft.publishMode;
        _draft.clubId = draft.clubId;
        // 冲突判定基准:真源 baseRevision = topic.updateTime||createTime,
        // 不拷过来,编辑态本地草稿永远判不出冲突。
        _draft.baseRevision = draft.baseRevision;
        // 真源 fabu/index.js:1956:编辑不重复往创意广场发帖 —— 编辑态强制关,
        // 与新建草稿的默认开(publish_draft.dart)相对。
        _draft.publishToCreative = false;
        _nameCtrl.text = draft.name;
        _editScope = scope;
        _editLoaded = true;
        _loadingEdit = false;
        _lockedSnapshot = _lockedFingerprint();
      });
      // 回填完成后才轮到本地草稿(真源 applyEditingTopic 末尾同款顺序)。
      await _finishEditDraftBootstrap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEdit = false;
        _editError = publishMessage(e, '这份主题没有加载出来');
      });
    }
  }

  // ------------------------------------------------------- 本地草稿自动保存

  String get _memberId {
    final id = ref.read(authControllerProvider).user?.id ?? 0;
    return id > 0 ? '$id' : '';
  }

  /// 真源 _draftIdentity:编辑态按 topicId 分桶,新草稿按 draftUuid 分桶。
  ProEditorDraftIdentity? get _draftIdentity {
    if (widget.topicId != null) {
      return ProEditorDraftIdentity(topicId: '${widget.topicId}');
    }
    if (_draftUuid.isNotEmpty) {
      return ProEditorDraftIdentity(draftUuid: _draftUuid);
    }
    return null;
  }

  void _scheduleAutosave() {
    if (!_autosaveReady || _autosaveTimer != null) return;
    _autosaveTimer = Timer(const Duration(milliseconds: 400), () {
      _autosaveTimer = null;
      // 触发时再核一遍 ready:提交成功后 ready 已撤,迟到的定时器不许
      // 把刚清掉的桶再建回来。
      if (mounted && _autosaveReady) _persistDraftEnvelope();
    });
  }

  Future<bool> _persistDraftEnvelope() async {
    final identity = _draftIdentity;
    // memberId 在 bootstrap 时已定稿;落盘入口(含 dispose 兜底)一律用字段,
    // 不再回读 ref。空串 = 没登录,直接不写。
    final memberId = _draftMemberId;
    if (identity == null || memberId.isEmpty) return false;
    final ok = await _draftStore.save(
      identity: identity,
      memberId: memberId,
      state: _draft.toDraftState(),
      baseRevision: _draft.baseRevision,
    );
    if (ok) {
      _saveWarned = false;
    } else if (!_saveWarned) {
      _saveWarned = true;
      if (mounted) _toast('本地草稿保存失败，请检查存储空间', isError: true);
    }
    return ok;
  }

  Future<void> _clearDraftEnvelope() async {
    final identity = _draftIdentity;
    if (identity == null) return;
    final memberId = _draftMemberId;
    if (memberId.isEmpty) return;
    await _draftStore.remove(identity: identity, memberId: memberId);
  }

  /// 真源 _newDraftUuid:显式 ?draftUuid= > 有新草稿要消费(AI 交接)则开新桶 >
  /// 续写该账号最近一桶 > 再起一桶。
  Future<String> _newDraftUuid() async {
    final explicit = (widget.resumeDraftUuid ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final memberId = _memberId;
    if (widget.initialDraft != null || memberId.isEmpty) {
      return ProEditorDraftStore.createDraftUuid();
    }
    final active = await _draftStore.activeNewDraftUuid(memberId);
    return active.isNotEmpty ? active : ProEditorDraftStore.createDraftUuid();
  }

  /// 真源 _bootstrapNewLocalDraft:新建入口进来先找本地桶,能恢复就恢复,
  /// 恢复成功时不再灌 AI/模板交接初值(谁先跑谁赢,顺序同真源注释)。
  Future<void> _bootstrapNewLocalDraft() async {
    final memberId = _memberId;
    _draftUuid = await _newDraftUuid();
    _draftMemberId = memberId;
    if (memberId.isEmpty) {
      _autosaveReady = true;
      return;
    }
    final result = await _draftStore.load(
      identity: ProEditorDraftIdentity(draftUuid: _draftUuid),
      memberId: memberId,
    );
    if (!mounted) return;
    if (result.status == kProEditorDraftStatusMemberMismatch) {
      _draftUuid = ProEditorDraftStore.createDraftUuid();
      _toast('草稿属于其他账号，已新建草稿');
      _finishNewDraftBootstrap();
      return;
    }
    final envelope = result.envelope;
    if (result.status != kProEditorDraftStatusReady || envelope == null) {
      _finishNewDraftBootstrap();
      return;
    }
    final restoredMode =
        (envelope.state['productType'] as num?)?.toInt() ?? kProductCity;
    final entryMode = widget.mode == kProductFreeExplore
        ? kProductFreeExplore
        : kProductCity;
    final modeMismatch =
        (widget.resumeDraftUuid ?? '').isEmpty && restoredMode != entryMode;
    final clubMismatch =
        widget.initialClubId != null &&
        '${envelope.state['clubId'] ?? ''}' != '${widget.initialClubId}';
    if (modeMismatch || clubMismatch) {
      _draftUuid = ProEditorDraftStore.createDraftUuid();
      _finishNewDraftBootstrap();
      return;
    }
    setState(() {
      _applyEnvelope(envelope);
      _autosaveReady = true;
    });
    await _persistDraftEnvelope();
  }

  void _finishNewDraftBootstrap() {
    // 没有可恢复的桶 → 消费交接初值(真源 applyAiDraft 的位)。
    if (widget.initialDraft != null && _draft.name.isEmpty) {
      setState(() => _applyInitialDraft(widget.initialDraft));
    }
    _autosaveReady = true;
    _persistDraftEnvelope();
  }

  /// 真源 _finishEditingDraftBootstrap:服务端回填落定后,若本地有更深的草稿
  /// 恢复它;版本冲突时问一句「用本地草稿覆盖吗」。
  Future<void> _finishEditDraftBootstrap() async {
    final memberId = _memberId;
    _draftMemberId = memberId;
    if (memberId.isEmpty) {
      _autosaveReady = true;
      return;
    }
    final result = await _draftStore.load(
      identity: ProEditorDraftIdentity(topicId: '${widget.topicId}'),
      memberId: memberId,
      currentBaseRevision: _draft.baseRevision,
    );
    if (!mounted) return;
    final envelope = result.envelope;
    if (result.status == kProEditorDraftStatusConflict && envelope != null) {
      final useLocal = await cyConfirm(
        context,
        title: '服务端草稿已更新',
        content: '服务端已更新，是否用本地草稿覆盖？',
        confirmText: '使用本地草稿',
        cancelText: '使用服务端版本',
      );
      if (!mounted) return;
      if (useLocal) {
        setState(() => _applyEnvelope(envelope));
      } else {
        // 选服务端 = 本地这份作废(真源 removeDraft 同款)。
        await _clearDraftEnvelope();
      }
    } else if (result.status == kProEditorDraftStatusReady &&
        envelope != null) {
      setState(() => _applyEnvelope(envelope));
    }
    // 真源 finish() 只放 ready 门,不再落盘 —— 选完「使用服务端版本」
    // 再写一次等于把刚删的桶原样建回来。
    _autosaveReady = true;
  }

  void _applyEnvelope(ProEditorDraftEnvelope envelope) {
    final PublishDraft restored = PublishDraft.fromDraftState(envelope.state);
    _draft.name = restored.name;
    _draft.subtitle = restored.subtitle;
    _draft.description = restored.description;
    _draft.startDate = restored.startDate;
    _draft.endDate = restored.endDate;
    _draft.recruitDeadline = restored.recruitDeadline;
    _draft.imgUrl = restored.imgUrl;
    _draft.imgArr = restored.imgArr;
    _draft.categoryIds = restored.categoryIds;
    _draft.categoryNames = restored.categoryNames;
    _draft.productType = restored.productType;
    _draft.chapters = restored.chapters;
    _draft.tickets = restored.tickets;
    _draft.selfPlay = restored.selfPlay;
    _draft.selfPlayPrice = restored.selfPlayPrice;
    _draft.selfPlayQuota = restored.selfPlayQuota;
    _draft.finishMedalName = restored.finishMedalName;
    _draft.finishMedalImg = restored.finishMedalImg;
    _draft.completeRewardCouponId = restored.completeRewardCouponId;
    _draft.publishToCreative = restored.publishToCreative;
    _draft.clubId = restored.clubId;
    _draft.clubName = restored.clubName;
    _draft.collaboratorIds = restored.collaboratorIds;
    _draft.openMerchantPool = restored.openMerchantPool;
    _draft.audioUrl = restored.audioUrl;
    _draft.audioDuration = restored.audioDuration;
    _draft.publishMode = restored.publishMode;
    if (envelope.draftUuid != null && envelope.draftUuid!.isNotEmpty) {
      _draftUuid = envelope.draftUuid!;
    }
    _nameCtrl.text = _draft.name;
    _toast('已恢复上次本地草稿');
  }

  // ------------------------------------------------------- WHITELIST 锁字段

  String _lockedFingerprint() => jsonEncode(<String, dynamic>{
    'startDate': _draft.startDate,
    'endDate': _draft.endDate,
    'chapters': _draft.chapters.map((c) => c.toJson()).toList(),
    'tickets': _draft.tickets.map((t) => t.toJson()).toList(),
  });

  // ------------------------------------------------------- 模式

  void _applyEntryMode(int mode) {
    final nextMode = mode == 2 ? 2 : 1;
    final tickets = _draft.tickets;
    if (tickets.isEmpty) {
      tickets.add(defaultTicket(nextMode));
    }
    for (final t in tickets) {
      t.mode = nextMode;
    }
    _draft.productType = nextMode;
  }

  // ------------------------------------------------------- 章节/节点

  Future<void> _openChapterModal(int index) async {
    final chapter = index >= 0 ? _draft.chapters[index] : null;
    final result = await showChapterSheet(
      context,
      name: chapter?.name ?? '',
      description: chapter?.description ?? '',
      isEdit: chapter != null,
      isCity: _draft.productType == kProductCity,
      audioUrl: chapter?.audioUrl ?? '',
      atmospherePreset: chapter?.atmospherePreset ?? 'DEFAULT',
      // 商家承接只有俱乐部主理人配得了 —— 和小程序 merchantPoolEditable、
      // 后端 resolveMerchantPoolFlag 是同一条闸。
      merchantPoolEditable: _role == 'club',
      recruitEnabled: chapter?.recruitEnabled ?? 0,
      termsMode: chapter?.termsMode ?? 'PERK',
      categoryId: chapter?.categoryId,
      categoryName: chapter?.category ?? '',
      maxMerchant: chapter?.maxMerchant,
      perkMinValue: chapter?.perkMinValue,
    );
    if (result == null || !mounted) return;
    if (result.deleted) {
      if (chapter != null && index < _draft.chapters.length) {
        _draft.chapters.removeAt(index);
      }
      setState(() {});
      return;
    }
    if (textOf(result.name).isEmpty) {
      _toast('请填写章节名称', isError: true);
      return;
    }
    if (chapter == null) {
      final newChapter = PublishChapter()
        ..localId = _localId()
        ..name = result.name.trim()
        ..description = result.description
        ..audioUrl = result.audioUrl
        ..atmospherePreset = result.atmospherePreset
        ..recruitEnabled = result.recruitEnabled
        ..termsMode = result.termsMode
        ..categoryId = result.categoryId
        ..category = result.categoryName
        ..maxMerchant = result.maxMerchant
        ..perkMinValue = result.perkMinValue;
      _draft.chapters.add(newChapter);
      setState(() {});
      // 城市定向:创建后直接进全屏故事流(小程序同一路径,省一次点击)。
      if (_draft.productType == kProductCity) {
        final chapterIndex = _draft.chapters.length - 1;
        // 等章节原生 Sheet 完成退场后再推入故事流，避免两个
        // CupertinoSheetRoute 在同一帧竞争，导致新 Sheet 没有出现。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openStoryEditor(chapterIndex);
        });
      }
    } else {
      chapter
        ..name = result.name.trim()
        ..description = result.description
        ..audioUrl = result.audioUrl
        ..atmospherePreset = result.atmospherePreset
        ..recruitEnabled = result.recruitEnabled
        ..termsMode = result.termsMode
        ..categoryId = result.categoryId
        ..category = result.categoryName
        ..maxMerchant = result.maxMerchant
        ..perkMinValue = result.perkMinValue;
      setState(() {});
    }
  }

  void _openStoryEditor(int index) {
    if (index < 0 || index >= _draft.chapters.length) return;
    final chapter = _draft.chapters[index];
    try {
      materializeChapter(chapter, _localId);
    } catch (e) {
      _toast(e.toString().replaceFirst('Bad state: ', ''), isError: true);
      return;
    }
    showStoryEditorSheet(
      context,
      draft: _draft,
      chapterIndex: index,
      onChapterNameChanged: (name) {
        chapter.name = name;
        setState(() {});
      },
      onStoryChanged: (newChapter) {
        _draft.chapters[index] = newChapter;
        setState(() {});
      },
      onInsertNodeAt: (insertAt) => _openNodeSheet(
        chapterIndex: index,
        nodeIndex: -1,
        storyInsertAt: insertAt,
      ),
      onEditNode: (nodeLocalId) {
        final nodes = chapter.nodes;
        final ni = nodes.indexWhere((n) => n.localId == nodeLocalId);
        if (ni < 0) return;
        _openNodeSheet(chapterIndex: index, nodeIndex: ni);
      },
    );
  }

  Future<void> _openNodeSheet({
    required int chapterIndex,
    int nodeIndex = -1,
    int storyInsertAt = -1,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= _draft.chapters.length) return;
    final chapter = _draft.chapters[chapterIndex];
    final node = nodeIndex >= 0 && nodeIndex < chapter.nodes.length
        ? chapter.nodes[nodeIndex]
        : null;
    final result = await showNodeSheet(
      context,
      ref: ref,
      draft: _draft,
      node: node,
      scope: operationScope,
    );
    if (result == null || !mounted) return;
    if (result.deleted) {
      if (node != null) {
        final ni = chapter.nodes.indexWhere((n) => n.localId == node.localId);
        if (ni >= 0) {
          final removed = chapter.nodes.removeAt(ni);
          setState(() {});
          CyNativeNotice.show(
            context,
            '已删除节点「${textOf(removed.name).isEmpty ? '未命名' : removed.name}」',
            actionLabel: '撤销',
            onAction: () {
              chapter.nodes.insert(ni, removed);
              setState(() {});
            },
          );
        }
      }
      return;
    }

    final saved = result.node;
    if (_draft.productType == kProductCity && storyInsertAt >= 0) {
      try {
        final cmdResult = applyStoryCommand(
          chapter,
          InsertNodeAtCommand(
            index: storyInsertAt,
            node: saved.copy()..localId = _localId(),
            blockKey: _localId(),
          ),
        );
        _draft.chapters[chapterIndex] = cmdResult.chapter;
      } catch (e) {
        _toast(e.toString().replaceFirst('Bad state: ', ''), isError: true);
        return;
      }
    } else if (node != null) {
      final ni = chapter.nodes.indexWhere((n) => n.localId == node.localId);
      if (ni >= 0) {
        chapter.nodes[ni] = saved;
      }
    } else {
      saved.localId = _localId();
      chapter.nodes.add(saved);
    }
    setState(() {});
  }

  /// 城市定向「＋ 创建节点」:跳到故事流并提示在目标缝添加。
  void _onTapAddNode(int chapterIndex) {
    if (_draft.productType == kProductCity) {
      _openStoryEditor(chapterIndex);
      _toast('请点击目标缝添加节点');
      return;
    }
    final issue = formalNodeCreationIssue(_draft, chapterIndex);
    if (issue != null) {
      _toast(issue, isError: true);
      return;
    }
    _openNodeSheet(chapterIndex: chapterIndex);
  }

  // ------------------------------------------------------- 弹层

  Future<void> _openTopicDetail() async {
    final draft = _draft;
    await showTopicDetailSheet(
      context,
      ref: ref,
      draft: draft,
      myClubs: _myClubs,
      onChanged: () => setState(() {}),
      onCategoryTap: () => _openCategorySheet(draft),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCategorySheet(PublishDraft draft) async {
    await showCategorySheet(
      context,
      ref: ref,
      draft: draft,
      onChanged: () => setState(() {}),
    );
  }

  Future<void> _openModePicker() async {
    final mode = await showModePickerSheet(
      context,
      current: _draft.productType,
    );
    if (mode == null || !mounted) return;
    setState(() => _applyEntryMode(mode));
  }

  // ------------------------------------------------------- 发布

  bool get _canPublish {
    final needsClub = _draft.productType == kProductCity && _myClubs.isNotEmpty;
    final bag = buildPublishValidationBag(_draft);
    return bag.isValid() &&
        (!needsClub || _draft.clubId != null) &&
        (!(widget.topicId != null) || _editLoaded);
  }

  Map<String, dynamic> _precheckReq() {
    final nodes = <Map<String, dynamic>>[];
    for (final chapter in _draft.chapters) {
      for (final node in chapter.nodes) {
        final ti = node.templateInfo;
        Object? task;
        if (textOf(ti['rule_instructions'] ?? ti['question_name']).isNotEmpty) {
          task = ti['rule_instructions'] ?? ti['question_name'];
        } else if (textOf(ti['description']).isNotEmpty) {
          task = ti['description'];
        } else {
          task = node.description;
        }
        nodes.add(<String, dynamic>{
          'name': node.name,
          'task': task ?? '',
          'hint1': ti['hint1'] ?? '',
          'hint2': ti['hint2'] ?? '',
        });
      }
    }
    return <String, dynamic>{
      'title': _draft.name,
      'subtitle': _draft.subtitle,
      'description': _draft.description,
      'nodes': nodes,
    };
  }

  void _onSubmitPressed() {
    if (_submitting || _prechecking) return;
    if (!_canPublish) {
      final bag = buildPublishValidationBag(_draft);
      _toast(bag.firstMessage() ?? '还有必填项没填完', isError: true);
      return;
    }
    if (widget.topicId != null &&
        _editScope == PublishEditScope.whitelist &&
        _lockedSnapshot != null &&
        _lockedSnapshot != _lockedFingerprint()) {
      cyConfirm(
        context,
        title: '这些改动存不下来',
        content:
            '主题已过审开卖，开始/结束日期、章节站点结构、票种与价格都不能再改了。'
            '要改这些只能先下架 → 退款 → 重发。其余文案与图片的修改可以正常保存。',
        confirmText: '知道了',
        showCancel: false,
      );
      return;
    }
    _runPrecheck();
  }

  Future<void> _runPrecheck() async {
    setState(() => _prechecking = true);
    List<AiPrecheckIssue> issues = <AiPrecheckIssue>[];
    String? skipLabel;
    try {
      issues = await ref
          .read(publishApiProvider)
          .safetyPrecheck(_precheckReq());
    } on AiPrecheckUnavailable catch (e) {
      final msg = e.msg;
      skipLabel = msg.contains('次数')
          ? 'AI 次数已用完，本次跳过安全预检（不影响发布）'
          : '安全预检暂不可用，本次跳过（不影响发布）';
    } catch (_) {
      skipLabel = '安全预检暂不可用，本次跳过（不影响发布）';
    }
    if (!mounted) return;
    setState(() => _prechecking = false);

    final local = buildPublishCheck(_draft);
    final blocking = <PublishCheckItem>[...local.blocking];
    final advisory = <PublishCheckItem>[...local.advisory];
    for (final issue in issues) {
      final item = PublishCheckItem(label: issue.message, tab: 2);
      if (issue.level == 'error' && issue.type != 'parse_error') {
        blocking.add(item);
      } else {
        advisory.add(item);
      }
    }
    if (skipLabel != null) {
      advisory.add(PublishCheckItem(label: skipLabel, tab: 2));
    }
    // 实名闸未落时**不**直接提交:弹层要开,那三格就在弹层里补(真源同口径)。
    if (blocking.isEmpty && advisory.isEmpty && _publisherIdentity.registered) {
      await _doSubmit();
      return;
    }
    // XP 预算总览(`POST /api/topic/xp-budget`):发布前的 budget-bar。
    // 只读、best-effort:读不回来就少一栏,不挡住发布检查本身。
    XpBudget? xpBudget;
    final int? editingTopicId = widget.topicId;
    if (editingTopicId != null && editingTopicId > 0) {
      try {
        xpBudget = await ref.read(topicApiProvider).xpBudget(editingTopicId);
      } catch (_) {
        // 没有预算事实比编一个 0 好 —— 界面整栏不显示。
      }
    }
    if (!mounted) return;
    final proceed = await showPublishCheckSheet(
      context,
      blocking: blocking,
      advisory: advisory,
      xpBudget: xpBudget,
      identity: _publisherIdentity,
      registerIdentity: (PublisherIdentityController form) =>
          registerPublisherIdentity(
            ref.read(publisherIdentityApiProvider),
            form.form,
          ),
    );
    if (proceed == true && mounted) {
      await _doSubmit();
    }
  }

  Future<void> _doSubmit() async {
    setState(() => _submitting = true);
    try {
      final full = buildTopicPayload(_draft, scope: operationScope);
      if (widget.topicId != null) {
        final payload = _editScope == PublishEditScope.whitelist
            ? whitelistPayload(full)
            : full;
        await ref
            .read(publishApiProvider)
            .updateTopic(widget.topicId!, payload);
        // 存上了,本地草稿就没有未保存内容了(真源成功回调里清信封)。
        _autosaveReady = false;
        _autosaveTimer?.cancel();
        _autosaveTimer = null;
        await _clearDraftEnvelope();
        if (!mounted) return;
        _toast('已保存');
        await _leave();
        return;
      }
      final tid = await ref.read(publishApiProvider).createTopicPro(full);
      // 先于成功面板清桶:面板上任何去向都不该把已发布内容留在草稿里。
      _autosaveReady = false;
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      await _clearDraftEnvelope();
      if (!mounted) return;
      setState(() => _submitting = false);
      final action = await showPublishSuccessSheet(
        context,
        name: _draft.name,
        topicId: tid,
        chapterCount: _draft.chapters.length,
        nodeCount: _draft.chapters.fold<int>(
          0,
          (int sum, PublishChapter c) => sum + c.nodes.length,
        ),
        isCity: _draft.productType == kProductCity,
      );
      if (!mounted) return;
      // 先取 router 再离场 —— pop 之后本页的 context 就不能再拿来导航了。
      final GoRouter router = GoRouter.of(context);
      await _leave();
      if (action == 'preview' && tid > 0) {
        router.push('/topic/$tid');
      } else if (action == 'projects') {
        router.push('/my-projects');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(publishMessage(e, '发布失败，请重试'), isError: true);
    }
  }

  void _toast(String text, {bool isError = false}) {
    CyNativeNotice.show(context, text, isError: isError);
  }

  /// 预览读的是服务端已保存的那一版;新建未发布的主题没有 id,只能提示。
  void _onPreviewPressed() {
    if (widget.topicId != null) {
      context.push('/topic/${widget.topicId}');
      return;
    }
    _toast('发布后可在项目里预览玩家视角');
  }

  // ------------------------------------------------------- 地图

  MapScene get _mapScene {
    final points = <MapPoint>[];
    var seq = 0;
    for (final chapter in _draft.chapters) {
      for (final node in chapter.nodes) {
        if (!hasUsableCoords(node)) continue;
        points.add(
          MapPoint(
            id: '${seq++}',
            latitude: double.parse(node.latitude),
            longitude: double.parse(node.longitude),
            title: node.name.isEmpty ? '未命名' : node.name,
          ),
        );
      }
    }
    final lat = points.isEmpty
        ? 31.2304
        : points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lng = points.isEmpty
        ? 121.4737
        : points.map((p) => p.longitude).reduce((a, b) => a + b) /
              points.length;
    return MapScene(
      points: points,
      routePoints: points,
      center: MapCoordinate(latitude: lat, longitude: lng),
    );
  }

  // ------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exitAllowed,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || _exitAllowed) return;
        unawaited(_guardExit());
      },
      child: CupertinoPageScaffold(
        backgroundColor: CyPalette.of(context).bgPage,
        navigationBar: CupertinoNavigationBar(
          middle: Text(widget.topicId == null ? '发布主题' : '编辑主题'),
        ),
        child: Material(color: Colors.transparent, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingEdit) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const LoadingView(),
          SizedBox(height: CyTokens.space3),
          Text(
            '正在加载已保存的主题…',
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      );
    }
    if (_editError != null) {
      return StatusView(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _editError!,
        onRetry: _loadEditDetail,
      );
    }

    final policy = evaluateProfessionalDraft(_draft);
    final missing = policy.blockingIssues.length;

    return Column(
      children: <Widget>[
        Expanded(
          child: _mapMode && _editorPage == 1
              ? Stack(
                  children: <Widget>[
                    Positioned.fill(child: AppleSceneView(scene: _mapScene)),
                    if (_mapScene.points.isEmpty)
                      const Positioned.fill(
                        child: Center(child: Text('还没有可展示的地点')),
                      ),
                  ],
                )
              : ListView(
                  padding: EdgeInsets.only(
                    left: CyTokens.pageX,
                    right: CyTokens.pageX,
                    bottom: CyTokens.space8,
                  ),
                  children: _editorPage == 1
                      ? _buildCreationTab(policy, missing)
                      : <Widget>[
                          PublishTicketTab(
                            draft: _draft,
                            merchantPoolEditable: _role == 'club',
                            myClubs: _myClubs,
                            onChanged: () => setState(() {}),
                          ),
                        ],
                ),
        ),
        _buildTabBar(),
      ],
    );
  }

  List<Widget> _buildCreationTab(DraftPolicy policy, int missing) {
    return <Widget>[
      SizedBox(height: CyTokens.space2),
      // 命名放第一屏第一位:名称是必填,不能埋到第三屏。
      CupertinoTextField(
        key: const Key('publish-pro-name'),
        controller: _nameCtrl,
        onChanged: (v) => setState(() => _draft.name = v),
        maxLength: 30,
        textInputAction: TextInputAction.done,
        autocorrect: true,
        enableSuggestions: true,
        placeholder: '未命名主题',
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).inputBgEmpty,
          border: Border.all(color: CyPalette.of(context).borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
      ),
      SizedBox(height: CyTokens.space3),
      _entryCard(
        icon: Icons.description_outlined,
        title: '主题详情',
        subtitle: missing > 0 ? '还差 $missing 项' : '已填完',
        onTap: _openTopicDetail,
        semanticsLabel: '打开主题详情',
      ),
      SizedBox(height: CyTokens.space3),
      Row(
        children: <Widget>[
          Expanded(
            child: _entryCard(
              icon: Icons.route_outlined,
              title: _draft.productType == kProductCity ? '城市定向' : '自由探索',
              subtitle: '切换模式',
              onTap: _openModePicker,
            ),
          ),
          SizedBox(width: CyTokens.space3),
          Expanded(
            child: _entryCard(
              icon: Icons.confirmation_number_outlined,
              title: '票务设置',
              subtitle: '编辑',
              onTap: () => setState(() => _editorPage = 2),
              semanticsLabel: '编辑票务设置',
            ),
          ),
        ],
      ),
      SizedBox(height: CyTokens.space3),
      // ★ 合作者。App 此前把 collaboratorIds 恒设成 [我自己],
      //   没有任何添加别人的入口 —— 这个功能等于不存在。
      _entryCard(
        icon: Icons.group_add_outlined,
        title: '合作者',
        // ★ 减掉自己再报数:「1 位」指的是"除我之外还有谁",
        //   把自己算进去会让一个人独自发布时显示「已邀请 1 位」。
        subtitle: _collaboratorCount == 0
            ? '还没有邀请别人'
            : '已邀请 $_collaboratorCount 位',
        onTap: _pickCollaborator,
      ),
      SizedBox(height: CyTokens.space4),
      const CySectionTitle('章节'),
      SizedBox(height: CyTokens.space3),
      if (_draft.chapters.isEmpty)
        _emptyChaptersCard(policy)
      else ...<Widget>[
        for (var i = 0; i < _draft.chapters.length; i++)
          _chapterCard(i, policy.chapterStates[i]),
        _addChapterRow(),
      ],
    ];
  }

  Widget _entryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? semanticsLabel,
  }) {
    final Widget card = CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          border: Border.all(color: CyPalette.of(context).borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  SizedBox(height: CyTokens.space1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: CyTokens.typeLabel,
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: CyPalette.of(context).textTertiary,
            ),
          ],
        ),
      ),
    );
    if (semanticsLabel == null) return card;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticsLabel,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(child: card),
    );
  }

  Widget _emptyChaptersCard(DraftPolicy policy) {
    final starter = policy.starterAction;
    return Container(
      padding: EdgeInsets.all(CyTokens.space5),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.flag_outlined,
            size: 48,
            color: CyPalette.of(context).textDisabled,
          ),
          SizedBox(height: CyTokens.space3),
          Text(
            '还没有章节',
            style: TextStyle(color: CyPalette.of(context).textPrimary),
          ),
          SizedBox(height: CyTokens.space1_5),
          Text(
            '先写一章的故事，再往里放地点',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          SizedBox(height: CyTokens.space4),
          // 三种起点(App 无待编排区)统一收敛到「建章」这条最终同构的路。
          CupertinoButton(
            minimumSize: const Size.fromHeight(44),
            color: CyPalette.of(context).actionPrimaryBg,
            onPressed: starter == null ? null : () => _openChapterModal(-1),
            child: Text(
              starter?.label ?? '添加章节',
              style: TextStyle(
                color: starter == null
                    ? CyPalette.of(context).textPlaceholder
                    : CyPalette.of(context).actionPrimaryFg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterCard(int index, ChapterState state) {
    final chapter = _draft.chapters[index];
    final isCity = _draft.productType == kProductCity;
    return Container(
      margin: EdgeInsets.only(bottom: CyTokens.space3),
      padding: EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        border: Border.all(color: CyPalette.of(context).borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CupertinoButton(
            minimumSize: const Size.fromHeight(44),
            padding: EdgeInsets.zero,
            onPressed: isCity ? () => _openStoryEditor(index) : null,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '第${index + 1}章 ${chapter.name}',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      fontWeight: FontWeight.w700,
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                ),
                if (isCity)
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 18,
                    color: CyPalette.of(context).textTertiary,
                  ),
              ],
            ),
          ),
          SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space2,
            runSpacing: CyTokens.space1_5,
            children: <Widget>[
              if (state.storyRequired || state.storyDone)
                _stateTag(
                  state.storyDone ? '剧情已写' : '缺剧情',
                  // 创建域恒浅(D10⑥):状态色取当前外观的语义值,不取暗色常量。
                  state.storyDone
                      ? CyPalette.of(context).statusSuccess
                      : CyPalette.of(context).statusDanger,
                  icon: state.storyDone
                      ? CupertinoIcons.checkmark_alt
                      : CupertinoIcons.exclamationmark_triangle,
                ),
              CyTag(label: '${state.nodeCount} 节点'),
              if (state.nodesMissingCoords > 0)
                _stateTag(
                  '${state.nodesMissingCoords} 个待选地点',
                  CyPalette.of(context).statusWarning,
                  icon: CupertinoIcons.exclamationmark_triangle,
                ),
              if (state.gameplayPending)
                CyTag(
                  label: '玩法 ${state.gameplayConfigured}/${state.nodeCount}',
                ),
            ],
          ),
          if (!isCity) ...<Widget>[
            SizedBox(height: CyTokens.space3),
            for (var ni = 0; ni < chapter.nodes.length; ni++)
              _nodeRow(index, ni),
          ],
          SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              Expanded(
                child: CupertinoButton(
                  minimumSize: const Size.fromHeight(44),
                  color: CyPalette.of(context).actionSecondaryBg,
                  onPressed: () => _openChapterModal(index),
                  child: const Text('编辑章节'),
                ),
              ),
              SizedBox(width: CyTokens.space2),
              Expanded(
                child: CupertinoButton(
                  minimumSize: const Size.fromHeight(44),
                  color: CyPalette.of(context).actionPrimaryBg,
                  disabledColor: CyPalette.of(context).actionSecondaryBg,
                  onPressed: state.canAddNode
                      ? () => _onTapAddNode(index)
                      : null,
                  child: Text(
                    isCity && state.storyDone ? '把这段剧情落到地点' : '＋ 创建节点',
                    style: TextStyle(
                      color: state.canAddNode
                          ? CyPalette.of(context).actionPrimaryFg
                          : CyPalette.of(context).textDisabled,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isCity)
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                minimumSize: const Size.fromHeight(44),
                onPressed: () => _openStoryEditor(index),
                child: const Text('编辑故事流'),
              ),
            ),
        ],
      ),
    );
  }

  /// 状态 chip。带图标的那两档(已写 / 缺)光靠颜色区分不了 ——
  /// 色弱看不出红绿,图标才是第二条线索。
  Widget _stateTag(String label, Color color, {IconData? icon}) {
    return Container(
      height: 22,
      padding: EdgeInsets.symmetric(horizontal: CyTokens.space2_5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontSize: CyTokens.typeCaption, color: color),
          ),
        ],
      ),
    );
  }

  Widget _nodeRow(int chapterIndex, int nodeIndex) {
    final node = _draft.chapters[chapterIndex].nodes[nodeIndex];
    final photos = node.imgList;
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: () =>
          _openNodeSheet(chapterIndex: chapterIndex, nodeIndex: nodeIndex),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CyPalette.of(context).bgSurfaceSubtle,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${nodeIndex + 1}',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: CyPalette.of(context).textPrimary,
                ),
              ),
            ),
            SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    node.name.isEmpty ? '添加地点' : node.name,
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: hasUsableCoords(node) || node.name.isNotEmpty
                          ? CyPalette.of(context).textPrimary
                          : CyPalette.of(context).textSecondary,
                    ),
                  ),
                  if (node.address.isNotEmpty) ...<Widget>[
                    SizedBox(height: 2),
                    Text(
                      node.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textTertiary,
                      ),
                    ),
                  ],
                  if (photos.isNotEmpty || hasGameplay(node)) ...<Widget>[
                    SizedBox(height: 2),
                    Text(
                      <String>[
                        if (photos.isNotEmpty) '${photos.length} 张照片',
                        if (hasGameplay(node)) '玩法已配',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: CyTokens.typeLabel,
                        color: CyPalette.of(context).textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (photos.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(right: CyTokens.space2),
                child: Image.network(
                  photos.first,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: 40, height: 40),
                ),
              ),
            Icon(
              Icons.more_horiz,
              size: 18,
              color: CyPalette.of(context).textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _addChapterRow() {
    return CupertinoButton(
      minimumSize: const Size.fromHeight(44),
      padding: EdgeInsets.zero,
      onPressed: () => _openChapterModal(-1),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space3),
        child: Row(
          children: <Widget>[
            Icon(Icons.add, size: 18, color: CyPalette.of(context).textPrimary),
            SizedBox(width: CyTokens.space2),
            Text(
              '添加章节',
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: CyPalette.of(context).textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        border: Border(
          top: BorderSide(color: CyPalette.of(context).borderSubtle),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: _editorPage == 1
                  ? Row(
                      children: <Widget>[
                        _tabButton(
                          Icons.edit_note,
                          '内容',
                          !_mapMode,
                          () => setState(() => _mapMode = false),
                        ),
                        SizedBox(width: CyTokens.space4),
                        _tabButton(
                          Icons.place_outlined,
                          '地图',
                          _mapMode,
                          () => setState(() => _mapMode = true),
                        ),
                      ],
                    )
                  : Semantics(
                      container: true,
                      excludeSemantics: true,
                      label: '完成票务设置，回到创作',
                      button: true,
                      onTap: () => setState(() => _editorPage = 1),
                      child: CupertinoButton(
                        minimumSize: const Size.fromHeight(44),
                        onPressed: () => setState(() => _editorPage = 1),
                        child: const Text('完成'),
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
              child: _editorPage == 1
                  ? CupertinoButton(
                      minimumSize: const Size.fromHeight(44),
                      color: CyPalette.of(context).actionPrimaryBg,
                      onPressed: _onPreviewPressed,
                      child: Text(
                        '预览 →',
                        style: TextStyle(
                          color: CyPalette.of(context).actionPrimaryFg,
                        ),
                      ),
                    )
                  : CupertinoButton(
                      minimumSize: const Size.fromHeight(44),
                      color: CyPalette.of(context).actionPrimaryBg,
                      disabledColor: CyPalette.of(context).actionSecondaryBg,
                      onPressed: _submitting || !_canPublish
                          ? null
                          : _onSubmitPressed,
                      child: _submitting
                          ? const CupertinoActivityIndicator()
                          : Text(
                              _prechecking ? '安全预检中...' : '检查并发布',
                              style: TextStyle(
                                color: _canPublish
                                    ? CyPalette.of(context).actionPrimaryFg
                                    : CyPalette.of(context).textDisabled,
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(IconData icon, String label, bool on, VoidCallback onTap) {
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 24,
            color: on
                ? CyPalette.of(context).textPrimary
                : CyPalette.of(context).textTertiary,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: on
                  ? CyPalette.of(context).textPrimary
                  : CyPalette.of(context).textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
