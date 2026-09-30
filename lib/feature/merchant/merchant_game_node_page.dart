import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/game_session_api.dart';
import '../../data/api/my_project_api.dart';
import '../../data/models/merchant_apply.dart';
import '../../data/models/merchant_dashboard.dart';
import '../../data/models/my_project.dart';
import '../auth/login_gate.dart';
import 'chapter_node_code_sheet.dart';
import 'merchant_game_pending_store.dart';

final gameSessionApiProvider = Provider<GameSessionGateway>((ref) {
  return GameSessionApi(ref.watch(dioClientProvider));
});

/// 工作台「我承接的」：真源是商家报名，不是我发布的项目。
final merchantJoinedProjectsProvider =
    FutureProvider.autoDispose<List<TopicRegistration>>((ref) {
      return ref.watch(merchantApiProvider).myTopicRegistrations();
    }, retry: (int retryCount, Object error) => null);

/// 工作台「我主办的」：必须显式带商家 scope，否则会混入个人/俱乐部项目。
final merchantHostedProjectsProvider =
    FutureProvider.autoDispose<List<MyProject>>((ref) {
      return ref
          .watch(myProjectApiProvider)
          .list(scope: 'MERCHANT', pageSize: 10);
    }, retry: (int retryCount, Object error) => null);

class MerchantGameNodePage extends ConsumerStatefulWidget {
  const MerchantGameNodePage({
    super.key,
    required this.activityId,
    required this.ownerMemberId,
    this.initialNodeId,
    this.gateway,
    this.pendingStore,
  });

  final int activityId;
  final int? initialNodeId;
  final GameSessionGateway? gateway;
  final MerchantGamePendingStore? pendingStore;
  final int ownerMemberId;

  @override
  ConsumerState<MerchantGameNodePage> createState() =>
      _MerchantGameNodePageState();
}

class _MerchantGameNodePageState extends ConsumerState<MerchantGameNodePage> {
  MerchantGameProjection? _projection;
  int? _selectedNodeId;
  Object? _error;
  bool _loading = true;
  bool _writing = false;
  bool _loadInFlight = false;
  bool _pendingUnknown = false;
  bool _identityUnavailable = false;
  bool _legacyPending = false;
  MerchantGamePendingWrite? _pendingWrite;
  final List<GameSessionReceipt> _recentReceipts = <GameSessionReceipt>[];
  late final MerchantGamePendingStore _pendingStore =
      widget.pendingStore ??
      MerchantGamePendingStore(const FlutterSecureStorage());

  GameSessionGateway get _gateway =>
      widget.gateway ?? ref.read(gameSessionApiProvider);
  bool get _writeBlocked => _writing || _pendingUnknown || _identityUnavailable;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.initialNodeId;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    try {
      if (widget.activityId <= 0) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = const GameSessionContractException('活动参数无效');
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
      final int ownerMemberId = widget.ownerMemberId;
      if (ownerMemberId <= 0) {
        _identityUnavailable = true;
        _pendingUnknown = false;
        _pendingWrite = null;
        _legacyPending = false;
        _error = const GameSessionContractException('登录身份无效，请重新登录');
      } else {
        _identityUnavailable = false;
      }
      final pending = ownerMemberId > 0
          ? await _pendingStore.read(
              widget.activityId,
              ownerMemberId: ownerMemberId,
            )
          : null;
      if (pending != null) {
        _pendingWrite = pending;
        _legacyPending = false;
        try {
          await _gateway.readReceipt(
            activityId: pending.activityId,
            requestId: pending.requestId,
            expectedAction: pending.action,
          );
          await _pendingStore.clear(
            widget.activityId,
            ownerMemberId: ownerMemberId,
          );
          _pendingUnknown = false;
          _pendingWrite = null;
        } on GameSessionRejectedException catch (error) {
          await _pendingStore.clear(
            widget.activityId,
            ownerMemberId: ownerMemberId,
          );
          _pendingUnknown = false;
          _pendingWrite = null;
          _error = error;
        } catch (_) {
          _pendingUnknown = true;
        }
      } else if (ownerMemberId > 0) {
        _pendingWrite = null;
        final legacy = await _pendingStore.readLegacy(widget.activityId);
        if (legacy == null) {
          _pendingUnknown = false;
          _legacyPending = false;
        } else {
          _legacyPending = true;
          try {
            await _gateway.readReceipt(
              activityId: legacy.activityId,
              requestId: legacy.requestId,
              expectedAction: legacy.action,
            );
            await _pendingStore.clearLegacy(widget.activityId);
            _pendingUnknown = false;
            _legacyPending = false;
          } on GameSessionRejectedException catch (error) {
            await _pendingStore.clearLegacy(widget.activityId);
            _pendingUnknown = false;
            _legacyPending = false;
            _error = error;
          } catch (_) {
            // v1 没有节点、版本和 payload，只能对账，绝不猜测重放。
            _pendingUnknown = true;
          }
        }
      }
      if (!mounted) return;
      final projection = await _gateway.loadMerchantView(
        activityId: widget.activityId,
      );
      if (!mounted) return;
      final hasRequested = projection.stations.any(
        (s) => s.nodeId == _selectedNodeId,
      );
      setState(() {
        _projection = projection;
        _selectedNodeId = hasRequested
            ? _selectedNodeId
            : projection.stations.firstOrNull?.nodeId;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    } finally {
      _loadInFlight = false;
    }
  }

  MerchantGameStation? get _station => _projection?.stations
      .where((item) => item.nodeId == _selectedNodeId)
      .firstOrNull;

  bool _allows(String action) {
    final MerchantGameProjection? projection = _projection;
    final MerchantGameStation? station = _station;
    return projection != null &&
        station != null &&
        projection.allowsStationAction(action, station);
  }

  String _requestId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'ios_${DateTime.now().microsecondsSinceEpoch}_$random';
  }

  Future<void> _submit(String action, Map<String, dynamic> payload) async {
    final projection = _projection;
    final station = _station;
    if (projection == null ||
        station == null ||
        _writeBlocked ||
        !projection.allowsStationAction(action, station)) {
      return;
    }
    final int ownerMemberId = widget.ownerMemberId;
    if (ownerMemberId <= 0) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      final command = GameSessionCommand(
        activityId: projection.activityId,
        nodeId: station.nodeId,
        requestId: _requestId(),
        expectedRevision: projection.revision,
        action: action,
        payload: payload,
      );
      final pending = MerchantGamePendingWrite.fromCommand(
        command,
        ownerMemberId: ownerMemberId,
      );
      try {
        await _pendingStore.write(pending);
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = const GameSessionContractException('无法安全保存本次操作，请重试'),
          );
        }
        return;
      }
      _pendingWrite = pending;
      final receipt = await _gateway.submitAndReadReceipt(command);
      if (!mounted) return;
      // APPLIED 回执只证明命令落地；界面仍以服务端最新投影为准。
      await _pendingStore.clear(
        command.activityId,
        ownerMemberId: ownerMemberId,
      );
      _pendingWrite = null;
      _pendingUnknown = false;
      await _load();
      if (mounted) {
        setState(() {
          _recentReceipts.insert(0, receipt);
          if (_recentReceipts.length > 5) _recentReceipts.removeLast();
        });
      }
      if (mounted) unawaited(HapticFeedback.mediumImpact());
    } catch (error) {
      if (error is GameSessionRejectedException) {
        await _pendingStore.clear(
          projection.activityId,
          ownerMemberId: ownerMemberId,
        );
        _pendingUnknown = false;
        _pendingWrite = null;
      } else {
        _pendingUnknown = true;
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _retryPending() async {
    final pending = _pendingWrite;
    if (pending == null || _writing) return;
    final int ownerMemberId = widget.ownerMemberId;
    if (ownerMemberId <= 0 || ownerMemberId != pending.ownerMemberId) {
      setState(() {
        _identityUnavailable = true;
        _error = const GameSessionContractException('登录身份已变更，请重新登录');
      });
      return;
    }
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      // 服务端以 requestId + payload hash 幂等；未落库与处理中都只能
      // 重放完整原命令，不能生成新请求或遗失拒绝原因等 payload。
      final receipt = await _gateway.submitAndReadReceipt(pending.toCommand());
      await _pendingStore.clear(
        pending.activityId,
        ownerMemberId: pending.ownerMemberId,
      );
      _pendingWrite = null;
      _pendingUnknown = false;
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() {
        _recentReceipts.insert(0, receipt);
        if (_recentReceipts.length > 5) _recentReceipts.removeLast();
      });
      unawaited(HapticFeedback.mediumImpact());
    } catch (error) {
      if (error is GameSessionRejectedException) {
        await _pendingStore.clear(
          pending.activityId,
          ownerMemberId: pending.ownerMemberId,
        );
        _pendingWrite = null;
        _pendingUnknown = false;
      } else {
        _pendingUnknown = true;
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _decline() async {
    final result = await showCupertinoModalPopup<({String code, String text})>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('拒绝站点邀请'),
        message: const Text('选择真实原因，提交后将由服务端记录。'),
        actions: <Widget>[
          for (final reason in const <(String, String)>[
            ('SCHEDULE_CONFLICT', '档期冲突'),
            ('RESOURCE_UNAVAILABLE', '现场资源不足'),
            ('LOCATION_UNSUITABLE', '本站暂不适合承接'),
          ])
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(context, (code: reason.$1, text: reason.$2)),
              isDestructiveAction: true,
              child: Text(reason.$2),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (result != null) {
      await _submit('STATION_DECLINE', <String, dynamic>{
        'reasonCode': result.code,
        'reason': result.text,
      });
    }
  }

  Future<void> _ready() async {
    final station = _station;
    if (station == null) return;
    final controller = TextEditingController(
      text: (station.capacity ?? 1).toString(),
    );
    final note = TextEditingController();
    var start = DateTime.now().add(const Duration(hours: 1));
    var end = start.add(const Duration(hours: 2));
    String? validationError;
    final checked = <String, bool>{
      for (final item in station.checklist) item.code: item.checked,
    };
    final submitted = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return CupertinoPopupSurface(
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: CyTokens.iosSheetExpandedHeight,
                child: Column(
                  children: <Widget>[
                    _SheetHeader(
                      title: '完成本站准备',
                      onCancel: () => Navigator.pop(sheetContext),
                      onDone: () {
                        final capacity = int.tryParse(controller.text) ?? 0;
                        final valid =
                            capacity > 0 &&
                            !start.isBefore(DateTime.now()) &&
                            start.isBefore(end) &&
                            checked.values.every((value) => value);
                        if (!valid) {
                          setSheetState(
                            () => validationError = '请完成全部清单，并检查接待人数和服务时间',
                          );
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                      },
                    ),
                    if (validationError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CyTokens.pageX,
                        ),
                        child: Text(
                          validationError!,
                          style: TextStyle(
                            color: CyPalette.of(context).statusDanger,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(CyTokens.pageX),
                        children: <Widget>[
                          for (final item in station.checklist)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: CyTokens.space2,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: ExcludeSemantics(
                                      child: Text(item.label),
                                    ),
                                  ),
                                  Semantics(
                                    container: true,
                                    label: item.label,
                                    toggled: checked[item.code] == true,
                                    onTap: () => setSheetState(
                                      () => checked[item.code] =
                                          !(checked[item.code] == true),
                                    ),
                                    child: ExcludeSemantics(
                                      child: CupertinoSwitch(
                                        value: checked[item.code] == true,
                                        onChanged: (value) => setSheetState(
                                          () => checked[item.code] = value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const _FieldLabel('接待容量'),
                          CupertinoTextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            placeholder: '每个时段最多接待人数',
                          ),
                          const SizedBox(height: CyTokens.space3),
                          _SystemDateTimeButton(
                            label: '服务开始',
                            value: _dateTime(start),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showCySystemDatePicker(
                                context: context,
                                mode: CupertinoDatePickerMode.dateAndTime,
                                initialDateTime: start,
                                minimumDate: now,
                                maximumDate: now.add(
                                  const Duration(days: 3650),
                                ),
                                title: '服务开始',
                              );
                              if (picked != null && context.mounted) {
                                setSheetState(() => start = picked);
                              }
                            },
                          ),
                          _SystemDateTimeButton(
                            label: '服务结束',
                            value: _dateTime(end),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showCySystemDatePicker(
                                context: context,
                                mode: CupertinoDatePickerMode.dateAndTime,
                                initialDateTime: end,
                                minimumDate: now,
                                maximumDate: now.add(
                                  const Duration(days: 3650),
                                ),
                                title: '服务结束',
                              );
                              if (picked != null && context.mounted) {
                                setSheetState(() => end = picked);
                              }
                            },
                          ),
                          const _FieldLabel('准备备注（选填）'),
                          CupertinoTextField(
                            controller: note,
                            maxLength: 200,
                            placeholder: '给主办方留一句现场说明',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (submitted == true) {
      final capacity = int.tryParse(controller.text) ?? 0;
      await _submit('STATION_READY', <String, dynamic>{
        'checklist': station.checklist
            .map(
              (e) => <String, dynamic>{
                'code': e.code,
                'checked': checked[e.code] == true,
              },
            )
            .toList(),
        'capacity': capacity,
        'serviceStartAt': _dateTime(start),
        'serviceEndAt': _dateTime(end),
        'note': note.text.trim(),
      });
    }
    controller.dispose();
    note.dispose();
  }

  Future<void> _pause() async {
    final result = await showCupertinoModalPopup<({String code, String text})>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('暂停本站'),
        actions: <Widget>[
          for (final reason in const <(String, String)>[
            ('CAPACITY', '现场满员'),
            ('STAFF', '人员暂时离岗'),
            ('EQUIPMENT', '设备或道具异常'),
            ('EMERGENCY', '现场突发情况'),
          ])
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () =>
                  Navigator.pop(context, (code: reason.$1, text: reason.$2)),
              child: Text(reason.$2),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (result != null) {
      final options =
          _projection?.fallbackOptions
              .where((item) => item.sourceNodeId == _station?.nodeId)
              .toList() ??
          const <MerchantGameFallback>[];
      if (options.isEmpty) {
        setState(
          () => _error = const GameSessionContractException('暂停需先在服务端配置备援预案'),
        );
        return;
      }
      var resumeAt = DateTime.now().add(const Duration(minutes: 30));
      var selected = 0;
      if (!mounted) return;
      final confirmed = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => CupertinoPopupSurface(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(CyTokens.pageX),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _SheetHeader(
                      title: '预计恢复与备援预案',
                      onCancel: () => Navigator.pop(sheetContext),
                      onDone: () => Navigator.pop(sheetContext, true),
                    ),
                    _SystemDateTimeButton(
                      label: '预计恢复时间',
                      value: _dateTime(resumeAt),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showCySystemDatePicker(
                          context: context,
                          mode: CupertinoDatePickerMode.dateAndTime,
                          initialDateTime: resumeAt,
                          minimumDate: now,
                          maximumDate: now.add(const Duration(days: 3650)),
                          title: '预计恢复时间',
                        );
                        if (picked != null && context.mounted) {
                          setSheetState(() => resumeAt = picked);
                        }
                      },
                    ),
                    CupertinoSlidingSegmentedControl<int>(
                      groupValue: selected,
                      children: <int, Widget>{
                        for (var i = 0; i < options.length; i++)
                          i: Text(options[i].nodeName),
                      },
                      onValueChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selected = value);
                        }
                      },
                    ),
                    const SizedBox(height: CyTokens.space3),
                    Text(options[selected].playerMessage),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (confirmed == true) {
        final fallback = options[selected];
        await _submit('STATION_PAUSE', <String, dynamic>{
          'reasonCode': result.code,
          'reason': result.text,
          'resumeEta': _dateTime(resumeAt),
          'fallbackPlanCode': fallback.planCode,
          'fallbackPlanVersion': fallback.planVersion,
        });
      }
    }
  }

  Future<void> _verify() async {
    final id = TextEditingController();
    var decision = 'APPROVE';
    var reason = 'ANSWER_MISMATCH';
    String? validationError;
    final submitted = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => CupertinoPopupSurface(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.pageX),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SheetHeader(
                    title: '核验玩家提交',
                    onCancel: () => Navigator.pop(sheetContext),
                    onDone: () {
                      if (!RegExp(
                        r'^[1-9]\d{0,18}$',
                      ).hasMatch(id.text.trim())) {
                        setSheetState(() => validationError = '请输入有效的提交 ID');
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                  ),
                  if (validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: Text(
                        validationError!,
                        style: TextStyle(
                          color: CyPalette.of(context).statusDanger,
                        ),
                      ),
                    ),
                  CupertinoTextField(
                    controller: id,
                    keyboardType: TextInputType.number,
                    placeholder: '提交 ID',
                  ),
                  const SizedBox(height: CyTokens.space3),
                  CupertinoSlidingSegmentedControl<String>(
                    groupValue: decision,
                    children: const <String, Widget>{
                      'APPROVE': Text('通过'),
                      'REJECT': Text('驳回'),
                    },
                    onValueChanged: (v) {
                      if (v != null) setSheetState(() => decision = v);
                    },
                  ),
                  if (decision == 'REJECT') ...<Widget>[
                    const SizedBox(height: CyTokens.space3),
                    CupertinoSlidingSegmentedControl<String>(
                      groupValue: reason,
                      children: const <String, Widget>{
                        'ANSWER_MISMATCH': Text('答案不匹配'),
                        'EVIDENCE_UNCLEAR': Text('凭证不清'),
                        'DUPLICATE_SUBMISSION': Text('重复提交'),
                      },
                      onValueChanged: (v) {
                        if (v != null) setSheetState(() => reason = v);
                      },
                    ),
                  ],
                  const SizedBox(height: CyTokens.space4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (submitted == true) {
      await _submit('VERIFY_SUBMISSION', <String, dynamic>{
        'submissionId': id.text.trim(),
        'decision': decision,
        if (decision == 'REJECT') 'reasonCode': reason,
      });
    }
    id.dispose();
  }

  static String _dateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _selectStation() async {
    final projection = _projection;
    if (projection == null || projection.stations.length < 2 || _writing) {
      return;
    }
    final int? selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (BuildContext sheetContext) => CupertinoActionSheet(
        title: const Text('切换本站'),
        actions: <Widget>[
          for (final MerchantGameStation station in projection.stations)
            CupertinoActionSheetAction(
              isDefaultAction: station.nodeId == _selectedNodeId,
              onPressed: () => Navigator.pop(sheetContext, station.nodeId),
              child: Text(
                station.nodeName.isEmpty ? '未命名站点' : station.nodeName,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedNodeId = selected);
      unawaited(HapticFeedback.selectionClick());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final bool canPop = navigator.canPop();
    void onBack() {
      if (canPop) {
        navigator.pop();
      } else {
        GoRouter.maybeOf(context)?.go('/merchant');
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('本站准备与运行'),
        leading: Semantics(
          container: true,
          button: true,
          label: canPop ? '返回上一页' : '返回商家中心',
          onTap: onBack,
          excludeSemantics: true,
          child: CupertinoNavigationBarBackButton(onPressed: onBack),
        ),
      ),
      child: SafeArea(
        child: _loading && _projection == null
            ? const LoadingView()
            : _error != null && _projection == null
            ? StatusView(
                message: _error.toString().replaceFirst('Exception: ', ''),
                icon: CupertinoIcons.exclamationmark_circle,
                onRetry: _load,
              )
            : _content(palette),
      ),
    );
  }

  Widget _content(CyPalette palette) {
    final projection = _projection!;
    final station = _station;
    if (station == null) {
      return const StatusView(
        message: '暂无本站任务',
        sub: '俱乐部或主办方发出站点邀请后，会显示在这里',
        icon: CupertinoIcons.map_pin_ellipse,
        large: true,
      );
    }
    // 现场打卡码只在「本站可接待」时才摆出来 —— 口径见
    // [MerchantGameProjection.allowsLiveCheckin]。
    final bool canLiveCheckin = projection.allowsLiveCheckin(station);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        if (projection.stations.length > 1) ...<Widget>[
          CupertinoButton(
            key: const Key('merchant-game-station-picker'),
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.space3,
              vertical: CyTokens.space2,
            ),
            color: palette.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            onPressed: _selectStation,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    station.nodeName.isEmpty ? '未命名站点' : station.nodeName,
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ),
                Text('切换', style: TextStyle(color: palette.textSecondary)),
                const SizedBox(width: CyTokens.space1),
                const Icon(CupertinoIcons.chevron_forward, size: 18),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space3),
        ],
        _GameCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      station.nodeName,
                      style: const TextStyle(
                        fontSize: CyTokens.typePageTitle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (station.stationCode.isNotEmpty)
                    Text(
                      station.stationCode,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                station.statusText,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (station.capacity != null)
                Text(
                  '接待人数 ${station.capacity}',
                  style: TextStyle(color: palette.textSecondary),
                ),
              if (station.pendingVerificationCount > 0)
                Text(
                  '待核验 ${station.pendingVerificationCount}',
                  style: TextStyle(color: palette.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        _GameCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SectionHeader(title: '本站执行卡', sub: '无需猜剧情，只按公开步骤接待玩家'),
              if (station.playerTaskPrompt.isEmpty)
                Text(
                  '主办方尚未配置本站任务，当前不要引导玩家开始。',
                  style: TextStyle(color: palette.textSecondary),
                )
              else ...<Widget>[
                _Info('玩家会做什么', station.playerTaskPrompt, palette),
                _Info(
                  '商家只需做什么',
                  station.merchantInstruction.isEmpty
                      ? '按核验编号确认玩家已完成公开任务；不代替玩家解题。'
                      : station.merchantInstruction,
                  palette,
                ),
                _Info(
                  '不能透露什么',
                  station.hiddenInfoReminder.isEmpty
                      ? '不要透露答案、其他角色线索或后台剧情条件。'
                      : station.hiddenInfoReminder,
                  palette,
                ),
              ],
            ],
          ),
        ),
        if (station.status == 'INVITED' &&
            (_allows('STATION_ACCEPT') ||
                _allows('STATION_DECLINE'))) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _GameCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(title: '站点邀请', sub: '接受后才能填写准备清单并开放本站'),
                Row(
                  children: <Widget>[
                    if (_allows('STATION_DECLINE'))
                      Expanded(
                        child: CupertinoButton.tinted(
                          onPressed: _writeBlocked ? null : _decline,
                          child: const Text('拒绝邀请'),
                        ),
                      ),
                    if (_allows('STATION_DECLINE') && _allows('STATION_ACCEPT'))
                      const SizedBox(width: CyTokens.space2),
                    if (_allows('STATION_ACCEPT'))
                      Expanded(
                        child: CupertinoButton.filled(
                          onPressed: _writeBlocked
                              ? null
                              : () => _submit(
                                  'STATION_ACCEPT',
                                  const <String, dynamic>{},
                                ),
                          child: Text(_writing ? '确认中…' : '接受邀请'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (station.status == 'ACCEPTED' &&
            _allows('STATION_READY')) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _GameCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(title: '准备清单', sub: '全部完成后，本站才可进入准备完成状态'),
                for (final GameChecklistItem item in station.checklist)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CyTokens.space2),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          item.checked
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 20,
                          color: item.checked
                              ? palette.textPrimary
                              : palette.textSecondary,
                        ),
                        const SizedBox(width: CyTokens.space2),
                        Expanded(child: Text(item.label)),
                      ],
                    ),
                  ),
                CupertinoButton.filled(
                  key: const Key('merchant-game-ready-action'),
                  onPressed: _writeBlocked ? null : _ready,
                  child: const Text('确认准备完成'),
                ),
              ],
            ),
          ),
        ],
        if (canLiveCheckin ||
            (_allows('STATION_PAUSE') ||
                (station.pendingVerificationCount > 0 &&
                    _allows('VERIFY_SUBMISSION')))) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _GameCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(title: '本站运行', sub: '只处理本站当前可执行的动作'),
                if (canLiveCheckin)
                  CyNativeButton(
                    key: const Key('merchant-game-live-code'),
                    label: '出示打卡码',
                    onPressed: _writeBlocked
                        ? null
                        : () => showChapterNodeCodeSheet(
                            context,
                            nodeId: station.nodeId,
                            kind: ChapterNodeCodeKind.liveCheckin,
                          ),
                  ),
                if (_allows('STATION_PAUSE'))
                  CupertinoButton.tinted(
                    onPressed: _writeBlocked ? null : _pause,
                    child: const Text('暂停接待'),
                  ),
                if (station.status == 'ACTIVE' &&
                    station.pendingVerificationCount > 0 &&
                    _allows('VERIFY_SUBMISSION'))
                  CupertinoButton.filled(
                    onPressed: _writeBlocked ? null : _verify,
                    child: const Text('核验玩家提交'),
                  ),
              ],
            ),
          ),
        ],
        if (station.status == 'PAUSED' &&
            _allows('STATION_RESUME')) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _GameCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(title: '暂停信息', sub: '玩家端不会把暂停站点显示为可接待'),
                CupertinoButton.filled(
                  onPressed: _writeBlocked
                      ? null
                      : () => _submit(
                          'STATION_RESUME',
                          const <String, dynamic>{},
                        ),
                  child: const Text('恢复接待'),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          Semantics(
            liveRegion: true,
            child: Text(
              _error.toString().replaceFirst('Exception: ', ''),
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        ],
        if (_pendingUnknown) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _GameCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '操作结果待确认',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _legacyPending
                      ? '旧版记录信息不完整，只会读取回执，不会重放操作。'
                      : '已保留完整原请求，确认前不会提交新操作。',
                  style: TextStyle(color: palette.textSecondary),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _writing || _loadInFlight ? null : _load,
                  child: const Text('确认操作结果'),
                ),
                CupertinoButton.filled(
                  onPressed: _writing || _pendingWrite == null
                      ? null
                      : _retryPending,
                  child: Text(_writing ? '重试中…' : '使用原请求重试'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space3),
        _GameCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('最近回执', style: TextStyle(fontWeight: FontWeight.w600)),
              if (_recentReceipts.isEmpty)
                Text(
                  '本次进入页面后还没有已确认操作',
                  style: TextStyle(color: palette.textSecondary),
                ),
              for (final receipt in _recentReceipts)
                Padding(
                  padding: const EdgeInsets.only(top: CyTokens.space2),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(_actionText(receipt.action))),
                      Text(
                        'revision ${receipt.revision} · 已确认',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        _GameCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('本站复盘', style: TextStyle(fontWeight: FontWeight.w600)),
              if (station.recap == null)
                Text('复盘数据待确认', style: TextStyle(color: palette.textSecondary))
              else ...<Widget>[
                _RecapRow('到站玩家', '${station.recap!.arrivedPlayers}'),
                _RecapRow('任务提交', '${station.recap!.submissionCount}'),
                _RecapRow(
                  '核验通过 / 驳回',
                  '${station.recap!.approvedCount} / ${station.recap!.rejectedCount}',
                ),
                _RecapRow('证据已记录', '${station.recap!.recordedCount}'),
                _RecapRow(
                  '正常完成 / 兜底完成',
                  '${station.recap!.normalCompletedCount} / ${station.recap!.fallbackCompletedCount}',
                ),
                _RecapRow('暂停事件', '${station.recap!.pauseEventCount}'),
                _RecapRow('公开授权内容', '${station.recap!.authorizedContentCount}'),
                const SizedBox(height: CyTokens.space1),
                Text(
                  '仅显示本站安全聚合，不公开玩家内容。',
                  style: TextStyle(color: palette.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        if (_writing)
          const Padding(
            padding: EdgeInsets.all(CyTokens.space3),
            child: SizedBox(height: 44, child: LoadingView()),
          ),
      ],
    );
  }

  static String _actionText(String action) =>
      const <String, String>{
        'STATION_ACCEPT': '接受邀请',
        'STATION_DECLINE': '拒绝邀请',
        'STATION_READY': '完成准备',
        'STATION_PAUSE': '暂停本站',
        'STATION_RESUME': '恢复本站',
        'VERIFY_SUBMISSION': '核验提交',
      }[action] ??
      action;
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.onCancel,
    required this.onDone,
  });
  final String title;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      CupertinoButton(onPressed: onCancel, child: const Text('取消')),
      Expanded(
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      CupertinoButton(onPressed: onDone, child: const Text('完成')),
    ],
  );
}

class _SystemDateTimeButton extends StatelessWidget {
  const _SystemDateTimeButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Semantics(
      button: true,
      label: '$label，当前 $value',
      excludeSemantics: true,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
        onPressed: onPressed,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: TextStyle(color: palette.textPrimary)),
                  const SizedBox(height: CyTokens.space1),
                  Text(value, style: TextStyle(color: palette.textSecondary)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: CyTokens.space3,
      bottom: CyTokens.space1,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          fontSize: CyTokens.typeCaption,
          color: CyPalette.of(context).textSecondary,
        ),
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value, this.palette);
  final String label;
  final String value;
  final CyPalette palette;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(value),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: CyTokens.space1),
          Text(sub, style: TextStyle(color: palette.textSecondary)),
        ],
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: CyTokens.space2),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.palette, required this.child});
  final CyPalette palette;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(CyTokens.space3),
    decoration: BoxDecoration(
      color: palette.bgSurface,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      border: Border.all(color: palette.cardBorder),
      boxShadow: palette.cardShadow,
    ),
    child: child,
  );
}

/// 小程序工作台的「项目」区：`gameEntries` 只能附着在项目卡内，不能另起一级卡。
/// 入口仍只用服务端按当前商家授权的清单，不从项目 id 猜 activityId。
class MerchantGameEntriesSection extends ConsumerStatefulWidget {
  const MerchantGameEntriesSection({
    super.key,
    this.gateway,
    this.onOpen,
    this.todo,
    this.events,
  });

  final GameSessionGateway? gateway;
  final ValueChanged<int>? onOpen;
  final MerchantTodo? todo;
  final List<Map<String, dynamic>>? events;

  @override
  ConsumerState<MerchantGameEntriesSection> createState() =>
      _MerchantGameEntriesSectionState();
}

class _MerchantGameEntriesSectionState
    extends ConsumerState<MerchantGameEntriesSection> {
  List<MerchantGameEntry>? _entries;
  Object? _entriesError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final GameSessionGateway gateway =
          widget.gateway ?? ref.read(gameSessionApiProvider);
      final values = await gateway.loadMerchantEntries();
      if (mounted) {
        setState(() {
          _entries = values;
          _entriesError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _entries = const <MerchantGameEntry>[];
          _entriesError = error;
        });
      }
    }
  }

  void _retryProjects() {
    ref.invalidate(merchantJoinedProjectsProvider);
    ref.invalidate(merchantHostedProjectsProvider);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final joinedAsync = ref.watch(merchantJoinedProjectsProvider);
    final hostedAsync = ref.watch(merchantHostedProjectsProvider);
    final joinedAll = joinedAsync.asData?.value ?? const <TopicRegistration>[];
    final hostedAll = (hostedAsync.asData?.value ?? const <MyProject>[])
        .where(
          (project) =>
              project.bizType == 'topic' || project.bizType == 'activity',
        )
        .toList(growable: false);
    final joinedVisible = joinedAll
        .where(
          (TopicRegistration r) =>
              _scheduleStatus(r.startDate, r.endDate) != '已结束',
        )
        .toList(growable: false);
    final hostedVisible = hostedAll
        .where(
          (MyProject p) => _scheduleStatus(p.startTime, p.endTime) != '已结束',
        )
        .toList(growable: false);
    final joined = joinedVisible.take(2).toList(growable: false);
    final hosted = hostedVisible.take(2).toList(growable: false);
    final List<MyProject> rawHosted =
        hostedAsync.asData?.value ?? const <MyProject>[];
    final int hostProjectTotal = rawHosted is MyProjectPage
        ? rawHosted.total
        : hostedVisible.length;
    final int projectTotal = joinedVisible.length + hostProjectTotal;
    final entries = _entries ?? const <MerchantGameEntry>[];

    final projectLoading = joinedAsync.isLoading || hostedAsync.isLoading;
    final projectError = joinedAsync.hasError || hostedAsync.hasError;
    final gameLoading = _entries == null && _entriesError == null;
    if (joined.isEmpty && hosted.isEmpty && entries.isEmpty && projectLoading) {
      return const _MerchantProjectsState(
        icon: CupertinoIcons.hourglass,
        title: '项目加载中…',
      );
    }
    if (joined.isEmpty && hosted.isEmpty && entries.isEmpty && projectError) {
      return _MerchantProjectsState(
        icon: CupertinoIcons.wifi_slash,
        title: '项目没取到',
        actionLabel: '重试',
        onAction: _retryProjects,
      );
    }
    if (joined.isEmpty && hosted.isEmpty && entries.isEmpty && gameLoading) {
      return const _MerchantProjectsState(
        icon: CupertinoIcons.hourglass,
        title: '项目加载中…',
      );
    }
    if (joined.isEmpty &&
        hosted.isEmpty &&
        entries.isEmpty &&
        !projectLoading) {
      return _MerchantProjectsState(
        icon: CupertinoIcons.tray,
        title: '还没有项目',
        actionLabel: '去发起',
        onAction: () => context.push('/publish/pro?scope=MERCHANT'),
      );
    }

    final exactActivityIds = hosted
        .where((project) => project.bizType == 'activity')
        .map((project) => project.id)
        .toSet();
    final attached = <int>{};
    final cards = <Widget>[];
    for (final registration in joined) {
      final projectEntries = entries
          .where((entry) {
            final matched =
                entry.topicId == registration.topicId &&
                !exactActivityIds.contains(entry.activityId);
            if (matched) attached.add(entry.activityId);
            return matched;
          })
          .toList(growable: false);
      cards.add(
        _MerchantProjectCard(
          registration: registration,
          entries: projectEntries,
          onOpen: widget.onOpen,
          todo: widget.todo?.project(1, registration.topicId),
          todoAvailable: widget.todo?.hasProjectBreakdown == true,
          messageCount: _messageCount(widget.events, 1, registration.topicId),
        ),
      );
    }
    for (final project in hosted) {
      final projectEntries = project.bizType == 'activity'
          ? entries
                .where((entry) {
                  final matched = entry.activityId == project.id;
                  if (matched) attached.add(entry.activityId);
                  return matched;
                })
                .toList(growable: false)
          : const <MerchantGameEntry>[];
      cards.add(
        _MerchantProjectCard(
          project: project,
          entries: projectEntries,
          onOpen: widget.onOpen,
          todo: widget.todo?.project(
            project.bizType == 'activity' ? 2 : 1,
            project.id,
          ),
          todoAvailable: widget.todo?.hasProjectBreakdown == true,
          messageCount: _messageCount(
            widget.events,
            project.bizType == 'activity' ? 2 : 1,
            project.id,
          ),
        ),
      );
    }
    for (final entry in entries.where(
      (entry) => !attached.contains(entry.activityId),
    )) {
      cards.add(
        _MerchantProjectCard(
          entryOnly: entry,
          entries: <MerchantGameEntry>[entry],
          onOpen: widget.onOpen,
          todo: widget.todo?.project(2, entry.activityId),
          todoAvailable: widget.todo?.hasProjectBreakdown == true,
          messageCount: _messageCount(widget.events, 2, entry.activityId),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space1),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '项目',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (projectTotal > 0)
                  CupertinoButton(
                    key: const Key('merchant-project-all'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    foregroundColor: CyPalette.of(context).textPrimary,
                    onPressed: () =>
                        context.push('/my-projects?scope=MERCHANT'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('全部 $projectTotal'),
                        const SizedBox(width: CyTokens.space1),
                        const Icon(CupertinoIcons.chevron_forward, size: 16),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          if (projectLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Text(
                '正在更新项目…',
                style: TextStyle(
                  color: CyPalette.of(context).textSecondary,
                  fontSize: CyTokens.typeCaption,
                ),
              ),
            ),
          if (projectError)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '部分项目没取到',
                      style: TextStyle(
                        color: CyPalette.of(context).textSecondary,
                        fontSize: CyTokens.typeCaption,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: _retryProjects,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          for (var index = 0; index < cards.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: CyTokens.space2),
            cards[index],
          ],
        ],
      ),
    );
  }
}

class _MerchantProjectsState extends StatelessWidget {
  const _MerchantProjectsState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CyTokens.space1),
            child: Text('项目', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: CyTokens.space2),
          _GameCard(
            palette: palette,
            child: Row(
              children: <Widget>[
                Icon(icon, color: palette.textSecondary),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
                if (actionLabel != null)
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantProjectCard extends StatelessWidget {
  const _MerchantProjectCard({
    this.project,
    this.registration,
    this.entryOnly,
    required this.entries,
    this.onOpen,
    this.todo,
    required this.todoAvailable,
    required this.messageCount,
  }) : assert(project != null || registration != null || entryOnly != null);

  final MyProject? project;
  final TopicRegistration? registration;
  final MerchantGameEntry? entryOnly;
  final List<MerchantGameEntry> entries;
  final ValueChanged<int>? onOpen;
  final MerchantProjectTodo? todo;
  final bool todoAvailable;
  final int messageCount;

  String get _bizType =>
      registration != null ? 'join' : project?.bizType ?? 'activity';
  int get _id => registration?.id ?? project?.id ?? entryOnly!.activityId;
  String get _title =>
      registration?.topicName ??
      registration?.addressName ??
      project?.title ??
      entryOnly!.activityName;

  String get _roleLabel =>
      registration != null || entryOnly != null ? '我承接的' : '我主办的';

  String? get _projectRoute {
    final joined = registration;
    if (joined != null) {
      return Uri(
        path: '/merchant/registration/${joined.id}/edit',
        queryParameters: <String, String>{
          if (joined.topicId > 0) 'topicId': '${joined.topicId}',
          'scope': 'MERCHANT',
        },
      ).toString();
    }
    final hosted = project;
    if (hosted == null) return null;
    final String? path = switch (hosted.bizType) {
      'topic' => '/project/home/${hosted.id}',
      'activity' => '/activity/${hosted.id}',
      _ => hosted.detailRoute,
    };
    if (path == null) return null;
    return Uri(
      path: path,
      queryParameters: const <String, String>{'scope': 'MERCHANT'},
    ).toString();
  }

  String? get _cover =>
      _firstImage(registration?.topicImgUrl ?? project?.cover);

  String? get _statusLabel => _scheduleStatus(
    registration?.startDate ?? project?.startTime,
    registration?.endDate ?? project?.endTime,
  );

  String? get _categoryLabel {
    final TopicRegistration? joined = registration;
    if (joined != null) {
      return switch (joined.mode) {
        1 => '城市定向',
        2 => '自由探索',
        _ => null,
      };
    }
    return project?.bizType == 'activity' || entryOnly != null ? '活动' : null;
  }

  String? get _meta {
    final String? joined = registration?.assignmentText;
    if (joined != null && joined.isNotEmpty) return joined;
    final String hostedDate = _workbenchDate(project?.startTime);
    return hostedDate.isEmpty ? null : hostedDate;
  }

  /// 卡底动作(真源 `index.wxml:218-232` + `merchant-workbench.js:130-138`)。
  ///
  /// ★ 只有**承接卡**有这一行 —— 主办卡的底行在稿上只有「N 报名 · N 浏览」。
  /// ★ 待办没取到时给「承接进度」而不是「去核销」:不知道有没有待核销,
  ///   就不宣称有。真源 `todoError` 分支同一判据。
  ({String label, String key})? get _cardAction {
    if (registration == null) return null;
    final int pendingVerify = todoAvailable ? (todo?.pendingVerify ?? 0) : 0;
    return pendingVerify > 0
        ? (label: '去核销', key: 'verify')
        : (label: '承接进度', key: 'progress');
  }

  VoidCallback? _onCardAction(BuildContext context) {
    final action = _cardAction;
    if (action == null) return null;
    if (action.key == 'verify') {
      // 「去核销」必须真的进扫码流程。真源 #814 删过一个文案说核销、
      // 实际跳台账的假入口,不许再加回来。
      return () => context.push('/merchant/scan');
    }
    final String? route = _projectRoute;
    return route == null ? null : () => context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    final projectRoute = _projectRoute;
    final String? statusLabel = _statusLabel;
    final String? categoryLabel = _categoryLabel;
    final String? meta = _meta;
    final cardAction = _cardAction;
    return KeyedSubtree(
      key: Key('merchant-project-$_bizType-$_id'),
      child: _GameCard(
        palette: palette,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: '打开$_roleLabel项目$_title',
              button: projectRoute != null,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: projectRoute == null
                    ? null
                    : () => context.push(projectRoute),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      key: Key('merchant-project-cover-$_bizType-$_id'),
                      width: 91,
                      height: 99,
                      child: CyNetImage(
                        _cover,
                        width: 91,
                        height: 99,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      ),
                    ),
                    const SizedBox(width: CyTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Wrap(
                                  spacing: CyTokens.space1,
                                  runSpacing: CyTokens.space1,
                                  children: <Widget>[
                                    if (statusLabel != null)
                                      _ProjectTag(
                                        text: statusLabel,
                                        foreground: palette.brand,
                                        background: palette.bgSurface,
                                        border: palette.borderSubtle,
                                      ),
                                    if (categoryLabel != null)
                                      _ProjectTag(
                                        text: categoryLabel,
                                        foreground: palette.actionPrimaryFg,
                                        background: palette.actionPrimaryBg,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: CyTokens.space1),
                              _ProjectMessageBadge(
                                key: Key(
                                  'merchant-project-message-$_bizType-$_id',
                                ),
                                count: messageCount,
                              ),
                            ],
                          ),
                          const SizedBox(height: CyTokens.space1_5),
                          Text(
                            _title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: CyTokens.typeBody,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (meta != null) ...<Widget>[
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              meta,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: CyTokens.typeCaption,
                              ),
                            ),
                          ],
                          if (todoAvailable) ...<Widget>[
                            const SizedBox(height: CyTokens.space1),
                            _ProjectTodoLine(
                              projectKey: '$_bizType-$_id',
                              todo: todo,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final entry in entries)
              CupertinoButton(
                key: Key('merchant-game-entry-${entry.activityId}'),
                padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
                onPressed: () {
                  if (onOpen != null) {
                    onOpen!(entry.activityId);
                  } else {
                    context.push('/merchant/game-node/${entry.activityId}');
                  }
                },
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.game_controller),
                    const SizedBox(width: CyTokens.space2),
                    Expanded(
                      child: Text(
                        '${entry.activityName} · ${entry.stationCount} 个站点',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textPrimary),
                      ),
                    ),
                    const Icon(CupertinoIcons.chevron_forward, size: 16),
                  ],
                ),
              ),
            if (cardAction != null)
              Container(
                // 卡底一行:动作单独可点,不被整卡的落点吃掉
                // (真源用 catchtap 截住冒泡,这里是另一个按钮,天然分开)。
                key: Key('merchant-project-foot-$_bizType-$_id'),
                margin: const EdgeInsets.only(top: CyTokens.space2),
                padding: const EdgeInsets.only(top: CyTokens.space2),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.borderSubtle)),
                ),
                child: Row(
                  children: <Widget>[
                    const Spacer(),
                    CupertinoButton(
                      key: Key(
                        'merchant-project-action-${cardAction.key}-$_bizType-$_id',
                      ),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: _onCardAction(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            cardAction.label,
                            style: CyType.caption2.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Icon(
                            CupertinoIcons.chevron_forward,
                            size: 14,
                            color: palette.textSecondary,
                          ),
                        ],
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
}

class _ProjectTag extends StatelessWidget {
  const _ProjectTag({
    required this.text,
    required this.foreground,
    required this.background,
    this.border,
  });

  final String text;
  final Color foreground;
  final Color background;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
      border: border == null ? null : Border.all(color: border!),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: foreground,
        fontSize: CyTokens.typeMicro,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ProjectMessageBadge extends ConsumerWidget {
  const _ProjectMessageBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CyPalette palette = CyPalette.of(context);
    final bool hasMessages = count > 0;
    final Widget content = Semantics(
      label: hasMessages ? '本项目$count条消息' : '暂无项目消息',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            hasMessages ? CupertinoIcons.bell_fill : CupertinoIcons.bell,
            size: 15,
            color: hasMessages ? palette.statusDanger : palette.textTertiary,
          ),
          if (hasMessages) ...<Widget>[
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                color: palette.statusDanger,
                fontSize: CyTokens.typeCaption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
    if (!hasMessages) return content;
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: () async {
        if (!await requireLogin(context, ref) || !context.mounted) return;
        context.push('/im');
      },
      child: content,
    );
  }
}

class _ProjectTodoLine extends StatelessWidget {
  const _ProjectTodoLine({required this.projectKey, required this.todo});

  final String projectKey;
  final MerchantProjectTodo? todo;

  @override
  Widget build(BuildContext context) {
    final MerchantProjectTodo? row = todo;
    if (row == null || row.actionableTotal <= 0) {
      return Text(
        '今日无待办',
        style: TextStyle(
          color: CyPalette.of(context).textTertiary,
          fontSize: CyTokens.typeCaption,
        ),
      );
    }
    return Wrap(
      spacing: CyTokens.space2,
      runSpacing: CyTokens.space1,
      children: <Widget>[
        if (row.pendingVerify > 0)
          Text(
            '待核销 ${row.pendingVerify}',
            key: Key('merchant-project-todo-verify-$projectKey'),
            style: TextStyle(
              color: CyPalette.of(context).statusSuccess,
              fontSize: CyTokens.typeCaption,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (row.pendingScanConfirm > 0)
          Text(
            '待扫码 ${row.pendingScanConfirm}',
            key: Key('merchant-project-todo-scan-$projectKey'),
            style: TextStyle(
              color: CyPalette.of(context).statusWarning,
              fontSize: CyTokens.typeCaption,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

int _messageCount(
  List<Map<String, dynamic>>? events,
  int ownerType,
  int ownerId,
) {
  if (events == null) return 0;
  return events.where((Map<String, dynamic> event) {
    return (event['ownerType'] as num?)?.toInt() == ownerType &&
        (event['ownerId'] as num?)?.toInt() == ownerId;
  }).length;
}

String? _firstImage(String? value) {
  final String first = (value ?? '').split(',').first.trim();
  return first.isEmpty ? null : first;
}

String? _scheduleStatus(String? startValue, String? endValue) {
  final String start = _day(startValue);
  if (start.isEmpty) return null;
  final String rawEnd = _day(endValue);
  final String end = rawEnd.isEmpty || rawEnd.compareTo(start) < 0
      ? start
      : rawEnd;
  final DateTime now = DateTime.now();
  final String today =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  if (today.compareTo(start) < 0) return '未开始';
  if (today.compareTo(end) > 0) return '已结束';
  return '进行中';
}

String _day(String? value) {
  final RegExpMatch? match = RegExp(
    r'^\d{4}-\d{2}-\d{2}',
  ).firstMatch((value ?? '').trim());
  return match?.group(0) ?? '';
}

String _workbenchDate(String? value) {
  final String raw = (value ?? '').trim();
  if (raw.isEmpty) return '';
  final DateTime? date = DateTime.tryParse(raw);
  if (date == null) return raw.length <= 10 ? raw : raw.substring(0, 10);
  const List<String> weekdays = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];
  return '${weekdays[date.weekday - 1]} ${date.month}月${date.day}日';
}
