import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/club_ops_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_ops.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';
import 'club_ops_sections.dart';

/// 活动运营:系列场次编排 + 本场管理(取消 / 名册 / 出勤更正)。
/// 对齐小程序 `pages/club/event-ops`(@90e66d70),三类权限面:
/// - `club:activity:manage` → 日期清单与系列表单;
/// - `club:event:checkin` → 本场名册与出勤更正(带 activityId 才给);
/// - 两者都没有 → 无权限屏(重试一万次也没用)。
///
/// ★ 三条不可省的业务闸门(小程序注释逐字):
///   ①集合时刻是退款钟锚点,必填;②取消本场要原因(2–255 字)+ 二次确认 +
///   **独立回读确认**;③出勤更正 requestId 幂等,4xx 明确失败才丢弃意图。
class ClubEventOpsPage extends ConsumerStatefulWidget {
  const ClubEventOpsPage({
    super.key,
    required this.clubId,
    this.activityId,
    this.recurrence,
    this.topicId,
  });

  final int clubId;
  final int? activityId;
  final String? recurrence;

  /// 主题页「管理场次」带进来的预选主题(真源 E-07:`_focusTopicId`)。
  final int? topicId;

  @override
  ConsumerState<ClubEventOpsPage> createState() => _ClubEventOpsPageState();
}

enum _SeriesState { idle, loading, ready, empty, error }

enum _OccurrenceState { idle, loading, ready, empty, error }

enum _CancellationState {
  idle,
  loading,
  active,
  cancelled,
  submitting,
  error,
  readbackError,
}

enum _RosterState { idle, loading, ready, error }

class _ClubEventOpsPageState extends ConsumerState<ClubEventOpsPage> {
  static const List<({String key, String label})> _rosterTabs =
      <({String key, String label})>[
        (key: 'registered', label: '已报名'),
        (key: 'waitlist', label: '候补'),
        (key: 'arrived', label: '已到场'),
        (key: 'noShow', label: '未到场'),
      ];

  ClubOpsLoadState _state = ClubOpsLoadState.loading;
  String _error = '';

  /// 401(没登录)与 403(登录了但没权限)必须分开:前者可恢复,后者不是。
  bool _loginRequired = false;
  bool _canManage = false;
  bool _canCheckin = false;

  // ── 系列清单 ──
  _SeriesState _seriesState = _SeriesState.idle;
  String _seriesError = '';
  List<EventSeries> _seriesRows = <EventSeries>[];
  List<EventOpsTopic> _topics = <EventOpsTopic>[];
  int? _topicId;
  int? _expandedSeriesId;
  _OccurrenceState _occurrenceState = _OccurrenceState.idle;
  List<SeriesOccurrence> _occurrenceRows = <SeriesOccurrence>[];

  // ── 系列表单 ──
  int? _editingSeriesId;
  int? _editingTopicId;
  int? _expectedVersion;
  bool _seriesDetailLoading = false;
  String _recurrenceType = 'ONCE';
  String _startDate = '';
  String _startTime = '09:00';
  final TextEditingController _countCtrl = TextEditingController(text: '4');
  final TextEditingController _capacityCtrl = TextEditingController();
  final TextEditingController _offerCtrl = TextEditingController(text: '1440');
  List<String> _customDates = <String>[];
  List<ClubMember> _leadOptions = <ClubMember>[];
  int? _leadMemberId;
  String _leadLoadWarning = '';
  bool _waitlistEnabled = true;
  bool _submitting = false;

  // ── 本场管理 / 取消 ──
  _CancellationState _cancellationState = _CancellationState.idle;
  String _cancellationError = '';
  String _cancellationSummary = '';
  String _cancellationReason = '';
  bool _cancellationSubmitting = false;
  String _cancellationRequestId = '';
  String _cancellationRequestReason = '';
  CancellationOutcome? _pendingCancellationResult;

  // ── 名册 ──
  String _rosterTab = 'registered';
  _RosterState _rosterState = _RosterState.idle;
  String _rosterError = '';
  ClubRoster? _roster;
  int? _actingMemberId;
  final Map<String, String> _attendanceRequestIds = <String, String>{};

  int? get _activityId => widget.activityId;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _startDate = _dateWire(now);
    _customDates = <String>[_startDate];
    if (widget.recurrence == 'ONCE') _recurrenceType = 'ONCE';
    _loadAccess();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _capacityCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  String _dateWire(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  Future<void> _loadAccess() async {
    setState(() {
      _state = ClubOpsLoadState.loading;
      _error = '';
      _loginRequired = false;
    });
    try {
      final ClubOpsAccess access = await ref
          .read(clubOpsApiProvider)
          .access(clubId: widget.clubId, activityId: _activityId);
      if (!mounted) return;
      final bool canManage = access.has(kClubActivityManage);
      final bool canCheckin =
          _activityId != null && access.has(kClubEventCheckin);
      final String? denied = clubOpsDenyReason(
        access,
        clubId: widget.clubId,
        allowed: (ClubOpsAccess a) =>
            a.has(kClubActivityManage) ||
            (_activityId != null && a.has(kClubEventCheckin)),
        deniedMessage: '当前角色没有活动运营或本场核销权限',
      );
      if (denied != null) {
        setState(() {
          _state = ClubOpsLoadState.noPermission;
          _error = denied;
        });
        return;
      }
      setState(() {
        _state = ClubOpsLoadState.ready;
        _canManage = canManage;
        _canCheckin = canCheckin;
      });
      if (canManage) {
        await _loadTopics();
        await _loadLeads();
        await _loadSeries();
        if (_activityId != null) await _readCancellationState();
      }
      if (canCheckin) await _loadRoster();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loginRequired = clubLoginRequired(error);
        _state = clubOpsFailureState(error);
        _error = clubOpsErrorMessage(error, '活动权限暂时不可用');
      });
    }
  }

  // ── 主题 / 负责人 ──────────────────────────────────────────

  Future<void> _loadTopics() async {
    try {
      final List<EventOpsTopic> topics = await ref
          .read(clubOpsApiProvider)
          .eventTopics(clubId: widget.clubId);
      if (!mounted) return;
      setState(() {
        _topics = topics;
        // E-07:带 topicId 进来时把下拉预选到它(找不到就维持第一个,
        // 不静默改口径)。
        final int? focus = widget.topicId;
        _topicId ??= focus != null && topics.any((t) => t.id == focus)
            ? focus
            : (topics.isEmpty ? null : topics.first.id);
      });
    } catch (_) {
      // topics 拉不到不单独立错误屏 —— 系列表单里的主题选择会显示空态,
      // 与小程序「暂无可开场的主题」同一条路。
    }
  }

  Future<void> _loadLeads() async {
    setState(() => _leadLoadWarning = '');
    try {
      final List<ClubMember> rows = await ref
          .read(clubApiProvider)
          .members(widget.clubId);
      if (!mounted) return;
      final Set<int> seen = <int>{};
      final List<ClubMember> leads = <ClubMember>[];
      for (final ClubMember row in rows) {
        if (row.memberId <= 0 || seen.contains(row.memberId)) continue;
        seen.add(row.memberId);
        leads.add(row);
      }
      setState(() {
        _leadOptions = leads;
        _leadMemberId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _leadLoadWarning = '负责人名单暂时不可用，将沿用主理人默认值');
    }
  }

  // ── 系列清单 ──────────────────────────────────────────────

  Future<void> _loadSeries() async {
    if (!_canManage) return;
    setState(() {
      _seriesState = _SeriesState.loading;
      _seriesError = '';
    });
    try {
      final List<EventSeries> rows = await ref
          .read(clubOpsApiProvider)
          .seriesList(clubId: widget.clubId);
      if (!mounted) return;
      setState(() {
        _seriesRows = rows;
        _seriesState = rows.isEmpty ? _SeriesState.empty : _SeriesState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _seriesState = _SeriesState.error;
        _seriesError = clubOpsErrorMessage(error, '系列列表加载失败');
      });
    }
  }

  String _seriesTitle(EventSeries series) {
    for (final EventOpsTopic topic in _topics) {
      if (topic.id == series.topicId) return topic.name;
    }
    return '主题 #${series.topicId}';
  }

  Future<void> _toggleSeriesDates(EventSeries series) async {
    if (_expandedSeriesId == series.id) {
      setState(() {
        _expandedSeriesId = null;
        _occurrenceRows = <SeriesOccurrence>[];
        _occurrenceState = _OccurrenceState.idle;
      });
      return;
    }
    setState(() {
      _expandedSeriesId = series.id;
      _occurrenceRows = <SeriesOccurrence>[];
      _occurrenceState = _OccurrenceState.loading;
    });
    try {
      final List<SeriesOccurrence> rows = await ref
          .read(clubOpsApiProvider)
          .seriesOccurrences(clubId: widget.clubId, seriesId: series.id);
      if (!mounted || _expandedSeriesId != series.id) return;
      setState(() {
        _occurrenceRows = rows;
        _occurrenceState = rows.isEmpty
            ? _OccurrenceState.empty
            : _OccurrenceState.ready;
      });
    } catch (_) {
      if (!mounted || _expandedSeriesId != series.id) return;
      setState(() => _occurrenceState = _OccurrenceState.error);
    }
  }

  Future<void> _beginEditSeries(EventSeries series) async {
    if (_submitting || _seriesDetailLoading) return;
    setState(() => _seriesDetailLoading = true);
    try {
      final EventSeries detail = await ref
          .read(clubOpsApiProvider)
          .seriesDetail(clubId: widget.clubId, seriesId: series.id);
      if (!mounted) return;
      final List<String> dates = detail.futureDates.isEmpty
          ? <String>[_startDate]
          : detail.futureDates;
      setState(() {
        _editingSeriesId = detail.id;
        _editingTopicId = detail.topicId;
        _expectedVersion = detail.version;
        _recurrenceType = detail.recurrenceType;
        _startDate = dates.first;
        // 后端读模型只回日期不回每场时刻;编辑态默认 09:00,
        // 改后的时刻只作用于本次新增日期。
        _startTime = '09:00';
        _countCtrl.text = '${dates.length}';
        _customDates = List<String>.from(dates);
        _capacityCtrl.text = detail.capacity == null
            ? ''
            : '${detail.capacity}';
        _leadMemberId = detail.leadMemberId;
        _waitlistEnabled = detail.waitlistEnabled;
        _offerCtrl.text = '${detail.offerMinutes}';
      });
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '系列详情加载失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _seriesDetailLoading = false);
    }
  }

  void _resetSeriesForm() {
    setState(() {
      _editingSeriesId = null;
      _editingTopicId = null;
      _expectedVersion = null;
      _recurrenceType = 'ONCE';
      _startDate = _dateWire(DateTime.now());
      _startTime = '09:00';
      _countCtrl.text = '4';
      _customDates = <String>[_startDate];
      _capacityCtrl.text = '';
      _leadMemberId = null;
      _waitlistEnabled = true;
      _offerCtrl.text = '1440';
    });
  }

  Future<void> _pickStartDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: DateTime.tryParse(_startDate) ?? now,
      minimumDate: DateTime(now.year, now.month, now.day),
      maximumDate: now.add(const Duration(days: 365)),
      title: '首次日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = _dateWire(picked));
  }

  Future<void> _pickStartTime() async {
    final DateTime now = DateTime.now();
    final List<String> parts = _startTime.split(':');
    final DateTime initial = DateTime(
      now.year,
      now.month,
      now.day,
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.time,
      initialDateTime: initial,
      minimumDate: DateTime(now.year, now.month, now.day),
      maximumDate: DateTime(now.year, now.month, now.day, 23, 59),
      title: '集合时刻',
    );
    if (picked == null || !mounted) return;
    String two(int value) => value.toString().padLeft(2, '0');
    setState(() => _startTime = '${two(picked.hour)}:${two(picked.minute)}');
  }

  Future<void> _pickCustomDate(int index) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: DateTime.tryParse(_customDates[index]) ?? now,
      minimumDate: DateTime(now.year, now.month, now.day),
      maximumDate: now.add(const Duration(days: 365)),
      title: '日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _customDates[index] = _dateWire(picked));
  }

  Future<void> _submitSeries() async {
    if (!_canManage || _submitting) return;
    final int? editingId = _editingSeriesId;
    final int? topicId = editingId != null ? _editingTopicId : _topicId;
    if (topicId == null || topicId <= 0) {
      CyNativeNotice.show(context, '暂无可开场的主题', isError: true);
      return;
    }
    final int? version = _expectedVersion;
    if (editingId != null && (version == null || version < 0)) {
      CyNativeNotice.show(context, '系列版本缺失，请重新进入编辑', isError: true);
      return;
    }
    final int? count = int.tryParse(_countCtrl.text.trim());
    final int offerMinutes = int.tryParse(_offerCtrl.text.trim()) ?? -1;
    final int? capacity = _capacityCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_capacityCtrl.text.trim());
    if (_recurrenceType == 'WEEKLY' &&
        (count == null || count < 1 || count > 64)) {
      CyNativeNotice.show(context, '每周场次数需为 1–64', isError: true);
      return;
    }
    if (_capacityCtrl.text.trim().isNotEmpty &&
        (capacity == null || capacity < 1 || capacity > 10000)) {
      CyNativeNotice.show(context, '容量需为 1–10000', isError: true);
      return;
    }
    if (offerMinutes < 5 || offerMinutes > 1440) {
      CyNativeNotice.show(context, '候补窗口需为 5–1440 分钟', isError: true);
      return;
    }
    final List<String> customDates =
        _customDates.where((String d) => d.isNotEmpty).toSet().toList()..sort();
    if (_recurrenceType == 'CUSTOM_DATES' && customDates.isEmpty) {
      CyNativeNotice.show(context, '请至少选择一个日期', isError: true);
      return;
    }
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_startTime)) {
      CyNativeNotice.show(context, '请选择集合时刻', isError: true);
      return;
    }
    setState(() => _submitting = true);
    final Map<String, dynamic> payload = <String, dynamic>{
      'clubId': widget.clubId,
      'topicId': topicId,
      'recurrenceType': _recurrenceType,
      'startDate': _startDate,
      'startTime': _startTime,
      'occurrenceCount': _recurrenceType == 'ONCE' ? 1 : count,
      'customDates': _recurrenceType == 'CUSTOM_DATES' ? customDates : null,
      'capacity': capacity,
      'defaultLeadMemberId': _leadMemberId,
      'waitlistEnabled': _waitlistEnabled,
      'offerMinutes': offerMinutes,
    };
    if (editingId != null) {
      payload['seriesId'] = editingId;
      payload['expectedVersion'] = version;
    } else {
      payload['requestId'] = ClubOpsApi.newRequestId('series');
    }
    try {
      if (editingId != null) {
        await ref.read(clubOpsApiProvider).updateSeriesFuture(payload);
      } else {
        await ref.read(clubOpsApiProvider).createSeries(payload);
      }
      if (!mounted) return;
      CyNativeNotice.show(context, editingId != null ? '未来场次已更新' : '系列场次已创建');
      _resetSeriesForm();
      await _loadSeries();
    } on ClubOpsConflictException {
      if (!mounted) return;
      CyNativeNotice.show(context, '系列已被更新，正在刷新', isError: true);
      await _loadSeries();
      if (editingId != null) {
        EventSeries? row;
        for (final EventSeries candidate in _seriesRows) {
          if (candidate.id == editingId) {
            row = candidate;
            break;
          }
        }
        if (row != null) await _beginEditSeries(row);
      }
    } catch (error) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, editingId != null ? '更新失败' : '创建失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── 本场取消 ──────────────────────────────────────────────

  Future<void> _readCancellationState({
    CancellationOutcome? cancelResult,
  }) async {
    final int? activityId = _activityId;
    if (!_canManage || activityId == null) return;
    setState(() {
      _cancellationState = _CancellationState.loading;
      _cancellationError = '';
    });
    try {
      final OccurrenceStatus? status = await ref
          .read(clubOpsApiProvider)
          .occurrenceStatus(clubId: widget.clubId, activityId: activityId);
      if (!mounted) return;
      if (status == null) {
        setState(() {
          _cancellationState = _CancellationState.readbackError;
          _cancellationError = '取消状态回读失败，请重试';
        });
        return;
      }
      if (cancelResult != null && !status.cancelled) {
        setState(() {
          _cancellationState = _CancellationState.readbackError;
          _cancellationError = '取消请求已受理，但独立回读尚未确认取消，请重试回读';
        });
        return;
      }
      if (status.cancelled) _pendingCancellationResult = null;
      setState(() {
        _cancellationState = status.cancelled
            ? _CancellationState.cancelled
            : _CancellationState.active;
        _cancellationError = '';
        _cancellationReason = status.cancelReason;
        if (cancelResult != null) {
          _cancellationSummary = cancelResult.summary;
        }
      });
      if (cancelResult != null && status.cancelled) {
        _cancellationRequestId = '';
        _cancellationRequestReason = '';
        CyNativeNotice.show(context, '本场取消已确认');
        await _loadSeries();
        if (_canCheckin) await _loadRoster();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancellationState = _CancellationState.readbackError;
        _cancellationError = clubOpsErrorMessage(error, '取消状态回读失败，请重试');
      });
    }
  }

  Future<void> _cancelCurrentOccurrence() async {
    if (!_canManage ||
        _activityId == null ||
        _cancellationSubmitting ||
        _cancellationState == _CancellationState.cancelled) {
      return;
    }
    final String? raw = await showCySystemTextInputAlert(
      context: context,
      title: '取消本场活动',
      placeholder: '请输入取消原因（至少 2 个字）',
      confirmText: '确认取消',
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (raw == null || !mounted) return;
    final String reason = raw.trim();
    if (reason.length < 2 || reason.length > 255) {
      CyNativeNotice.show(context, '取消原因需为 2–255 个字', isError: true);
      return;
    }
    // 原因合法后不直接发请求:先过 T2 居中二次确认(只能点按钮)。
    final bool confirmed = await cyConfirm(
      context,
      title: '确认取消本场？',
      content: '会下架本场、处理退款并终止候补。已核销的部分不退。',
      confirmText: '取消本场',
      cancelText: '再想想',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _submitOccurrenceCancellation(reason);
  }

  Future<void> _submitOccurrenceCancellation(String reason) async {
    final int? activityId = _activityId;
    if (!_canManage || activityId == null || _cancellationSubmitting) return;
    final String normalized = reason.trim();
    if (normalized.length < 2 || normalized.length > 255) return;
    final bool sameAttempt =
        _cancellationRequestId.isNotEmpty &&
        _cancellationRequestReason == normalized;
    final String requestId = sameAttempt
        ? _cancellationRequestId
        : ClubOpsApi.newRequestId('event-cancel');
    _cancellationRequestId = requestId;
    _cancellationRequestReason = normalized;
    setState(() {
      _cancellationSubmitting = true;
      _cancellationState = _CancellationState.submitting;
      _cancellationError = '';
    });
    try {
      final CancellationOutcome? result = await ref
          .read(clubOpsApiProvider)
          .cancelOccurrence(
            clubId: widget.clubId,
            activityId: activityId,
            reason: normalized,
            requestId: requestId,
          );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _cancellationState = _CancellationState.error;
          _cancellationError = '取消失败，请稍后重试';
        });
        return;
      }
      _pendingCancellationResult = result;
      await _readCancellationState(cancelResult: result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancellationState = _CancellationState.error;
        _cancellationError = clubOpsErrorMessage(error, '网络结果未知，可用同一原因安全重试');
      });
    } finally {
      if (mounted) setState(() => _cancellationSubmitting = false);
    }
  }

  // ── 名册 ──────────────────────────────────────────────────

  Future<void> _loadRoster() async {
    final int? activityId = _activityId;
    if (!_canCheckin || activityId == null) return;
    setState(() {
      _rosterState = _RosterState.loading;
      _rosterError = '';
    });
    try {
      final ClubRoster? roster = await ref
          .read(clubOpsApiProvider)
          .roster(clubId: widget.clubId, activityId: activityId);
      if (!mounted) return;
      if (roster == null) {
        setState(() {
          _rosterState = _RosterState.error;
          _rosterError = '名册数据不完整';
        });
        return;
      }
      setState(() {
        _roster = roster;
        _rosterState = _RosterState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rosterState = _RosterState.error;
        _rosterError = clubOpsErrorMessage(error, '名册加载失败');
      });
    }
  }

  List<RosterMember> get _activeRoster {
    final ClubRoster? roster = _roster;
    if (roster == null) return <RosterMember>[];
    switch (_rosterTab) {
      case 'waitlist':
        return roster.waitlist;
      case 'arrived':
        return roster.arrived;
      case 'noShow':
        return roster.noShow;
      default:
        return roster.registered;
    }
  }

  Future<void> _correctAttendance(RosterMember member) async {
    if (_actingMemberId != null) return;
    final bool arrived = _rosterTab != 'arrived';
    final String? raw = await showCySystemTextInputAlert(
      context: context,
      title: arrived ? '更正为已到场' : '更正为未到场',
      placeholder: '请输入更正原因（至少 2 个字）',
      confirmText: '提交',
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (raw == null || !mounted) return;
    final String reason = raw.trim();
    if (reason.length < 2) return;
    await _submitCorrection(member, arrived: arrived, reason: reason);
  }

  Future<void> _submitCorrection(
    RosterMember member, {
    required bool arrived,
    required String reason,
  }) async {
    final int? activityId = _activityId;
    if (activityId == null) return;
    final String intentKey =
        '${widget.clubId}:$activityId:${member.memberId}:$arrived:${member.correctionVersion}';
    final String requestId =
        _attendanceRequestIds[intentKey] ??
        ClubOpsApi.newRequestId('attendance');
    _attendanceRequestIds[intentKey] = requestId;
    setState(() => _actingMemberId = member.memberId);
    try {
      final bool accepted = await ref
          .read(clubOpsApiProvider)
          .correctAttendance(
            clubId: widget.clubId,
            activityId: activityId,
            memberId: member.memberId,
            arrived: arrived,
            expectedVersion: member.correctionVersion,
            reason: reason,
            requestId: requestId,
          );
      if (!mounted) return;
      if (accepted) {
        _attendanceRequestIds.remove(intentKey);
        CyNativeNotice.show(context, '签到已更正');
        await _loadRoster();
        return;
      }
      CyNativeNotice.show(context, '更正失败', isError: true);
    } catch (error) {
      if (!mounted) return;
      if (error is ClubOpsRejectedException) {
        _attendanceRequestIds.remove(intentKey);
      }
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, '更正失败'),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _actingMemberId = null);
    }
  }

  // ── 构建 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('活动运营')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('活动运营'),
              Expanded(child: _body()),
              if (_state == ClubOpsLoadState.ready && _canManage)
                CyFooterBar(
                  primary: CyNativeButton(
                    key: const Key('event-ops-submit'),
                    label: _submitting
                        ? '正在提交…'
                        : (_editingSeriesId != null ? '保存未来场次' : '创建系列场次'),
                    width: double.infinity,
                    onPressed: _submitting ? null : _submitSeries,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // 游客先登录:401 说成「你没有活动运营的权限」会让人去查自己的角色,
    // 而真因只是没登录 —— 登录后原地重取,人留在这一页。
    if (_loginRequired) {
      return ClubLoginGate(message: '登录后查看活动运营', onSignedIn: _loadAccess);
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: '你没有活动运营的权限',
          sub: _error.isEmpty ? '场次编排、签到与出勤更正需要「活动运营」或「本场核销」权限。' : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: '网络连接失败',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: '活动运营暂时不可用',
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.ready:
        return ListView(
          padding: const EdgeInsets.only(bottom: CyTokens.space8),
          children: <Widget>[
            if (_canManage) ...<Widget>[
              _seriesSection(),
              _formSection(),
              if (_activityId != null) _occurrenceSection(),
            ],
            if (_canCheckin) _rosterSection(),
          ],
        );
    }
  }

  Widget _seriesSection() {
    final CyPalette palette = CyPalette.of(context);
    return ClubOpsSection(
      title: '日期清单',
      note: '编辑只影响未来且无报名、无结算事实的场次',
      children: <Widget>[
        if (_seriesState == _SeriesState.loading)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space3),
            child: CySkeleton(type: CySkeletonType.card, count: 2),
          )
        else if (_seriesState == _SeriesState.error)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: '系列列表加载失败',
              sub: _seriesError,
              onRetry: _loadSeries,
            ),
          )
        else if (_seriesState == _SeriesState.empty)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: '还没有系列场次',
              sub: '从下方创建第一组场次',
              icon: CupertinoIcons.calendar,
            ),
          )
        else
          ClubOpsCard(
            children: <Widget>[
              for (final EventSeries series in _seriesRows) ...<Widget>[
                ClubOpsRow(
                  key: Key('event-ops-series-${series.id}'),
                  title:
                      '${_seriesTitle(series)} · ${EventSeries.recurrenceLabel(series.recurrenceType)}',
                  meta:
                      '版本 ${series.version} · 候补${series.waitlistEnabled ? '开启' : '关闭'}'
                      ' · ${series.futureDates.length} 个可编辑日期',
                  value: _editingSeriesId == series.id ? '编辑中' : '编辑未来场次',
                  valueColor: _editingSeriesId == series.id
                      ? palette.brand
                      : palette.textTertiary,
                  enabled: !_submitting && !_seriesDetailLoading,
                  onTap: () => _beginEditSeries(series),
                ),
                ClubOpsRow(
                  key: Key('event-ops-series-dates-${series.id}'),
                  title: '日期清单（含已过去与已取消的场次）',
                  trailing: Icon(
                    _expandedSeriesId == series.id
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 16,
                    color: palette.textTertiary,
                  ),
                  onTap: () => _toggleSeriesDates(series),
                ),
                if (_expandedSeriesId == series.id)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.space4,
                      0,
                      CyTokens.space4,
                      CyTokens.space3,
                    ),
                    child: _occurrenceList(palette),
                  ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _occurrenceList(CyPalette palette) {
    switch (_occurrenceState) {
      case _OccurrenceState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 2);
      case _OccurrenceState.error:
        return Text(
          '日期清单没加载出来，稍后再试一次。',
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: palette.textTertiary,
          ),
        );
      case _OccurrenceState.empty:
        return Text(
          '这个系列还没有物化出场次。',
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: palette.textTertiary,
          ),
        );
      case _OccurrenceState.idle:
      case _OccurrenceState.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _occurrenceRows
              .map(
                (SeriesOccurrence occ) => Padding(
                  padding: const EdgeInsets.only(top: CyTokens.space2),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              occ.dateText,
                              style: TextStyle(
                                fontSize: CyTokens.typeLabel,
                                color: palette.textPrimary,
                              ),
                            ),
                            Text(
                              occ.meta,
                              style: TextStyle(
                                fontSize: CyTokens.typeCaption,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        occ.badge,
                        style: TextStyle(
                          fontSize: CyTokens.typeCaption,
                          color: occ.badgeKind == 'cancelled'
                              ? CyTokens.statusDanger
                              : (occ.badgeKind == 'editable'
                                    ? CyTokens.statusSuccess
                                    : palette.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
    }
  }

  Widget _formSection() {
    final CyPalette palette = CyPalette.of(context);
    final bool editing = _editingSeriesId != null;
    return ClubOpsSection(
      title: editing ? '编辑未来场次' : '创建系列场次',
      children: <Widget>[
        if (_topics.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: '暂无可开场的主题',
              sub: '先发布一个俱乐部主题，或完成商家合作后再开场。',
              icon: Icons.route_outlined,
            ),
          )
        else
          ClubOpsCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.space4,
                  CyTokens.space3,
                  CyTokens.space4,
                  CyTokens.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CyField(
                      label: '主题',
                      child: editing
                          ? Text(
                              '主题 #$_editingTopicId · 已锁定',
                              style: TextStyle(
                                fontSize: CyTokens.typeBody,
                                color: palette.textSecondary,
                              ),
                            )
                          : _topicPicker(palette),
                    ),
                    CyField(
                      label: '重复方式',
                      child: Row(
                        children: EventSeries.recurrences
                            .map(
                              (({String value, String label}) item) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: CyTokens.space1_5,
                                  ),
                                  child: _optionChip(
                                    key: Key(
                                      'event-ops-recurrence-${item.value}',
                                    ),
                                    label: item.label,
                                    active: _recurrenceType == item.value,
                                    onTap: _submitting
                                        ? null
                                        : () => setState(
                                            () => _recurrenceType = item.value,
                                          ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    if (_recurrenceType != 'CUSTOM_DATES')
                      CyField(
                        label: '首次日期',
                        child: _fieldPicker(
                          key: const Key('event-ops-start-date'),
                          text: _startDate,
                          onTap: _pickStartDate,
                        ),
                      ),
                    if (_recurrenceType == 'WEEKLY')
                      CyField(
                        label: '场次数',
                        child: _numberField(
                          key: const Key('event-ops-count'),
                          controller: _countCtrl,
                          placeholder: '1–64',
                        ),
                      ),
                    if (_recurrenceType == 'CUSTOM_DATES') ...<Widget>[
                      CyField(
                        label: '日期清单',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (
                              int index = 0;
                              index < _customDates.length;
                              index += 1
                            )
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: CyTokens.space1_5,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _fieldPicker(
                                        key: Key('event-ops-date-$index'),
                                        text: _customDates[index],
                                        onTap: () => _pickCustomDate(index),
                                      ),
                                    ),
                                    const SizedBox(width: CyTokens.space1_5),
                                    ClubOpsRowLink(
                                      label: '移除',
                                      enabled:
                                          !_submitting &&
                                          _customDates.length > 1,
                                      onTap: () => setState(
                                        () => _customDates.removeAt(index),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            _AddDateRow(
                              enabled: !_submitting && _customDates.length < 64,
                              onTap: () =>
                                  setState(() => _customDates.add(_startDate)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    CyField(
                      label: '集合时刻',
                      child: _fieldPicker(
                        key: const Key('event-ops-start-time'),
                        text: _startTime,
                        onTap: _pickStartTime,
                      ),
                    ),
                    Text(
                      '退款窗口按「集合时刻前 24 小时」计算。',
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: palette.textTertiary,
                      ),
                    ),
                    if (!editing) ...<Widget>[
                      const SizedBox(height: CyTokens.space3),
                      CyField(label: '默认负责人', child: _leadPicker(palette)),
                      if (_leadLoadWarning.isNotEmpty)
                        Text(
                          _leadLoadWarning,
                          style: TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: CyTokens.statusWarning,
                          ),
                        ),
                    ],
                    const SizedBox(height: CyTokens.space3),
                    CyField(
                      label: '容量（可选）',
                      child: _numberField(
                        key: const Key('event-ops-capacity'),
                        controller: _capacityCtrl,
                        placeholder: '沿用票种',
                      ),
                    ),
                    Text(
                      '自定义容量只适用于恰有一个票种的合作主题；多票种继续沿用原票种容量。',
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        height: 1.5,
                        color: palette.textTertiary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space2),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '满员后开启候补',
                                  style: TextStyle(
                                    fontSize: CyTokens.typeBody,
                                    fontWeight: FontWeight.w600,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                Text(
                                  '按活动 + 票种先进先出',
                                  style: TextStyle(
                                    fontSize: CyTokens.typeCaption,
                                    color: palette.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            key: const Key('event-ops-waitlist'),
                            value: _waitlistEnabled,
                            activeTrackColor: palette.brand,
                            onChanged: _submitting
                                ? null
                                : (bool value) =>
                                      setState(() => _waitlistEnabled = value),
                          ),
                        ],
                      ),
                    ),
                    if (_waitlistEnabled) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      CyField(
                        label: '候补认领窗口（分钟，默认 1440 = 一天）',
                        child: _numberField(
                          key: const Key('event-ops-offer'),
                          controller: _offerCtrl,
                          placeholder: '5–1440',
                        ),
                      ),
                      Text(
                        '名额空出来后为队首保留这么久，逾期顺延给下一位。'
                        '窗口再长也不会超过这张票的报名截止时间。',
                        style: TextStyle(
                          fontSize: CyTokens.typeCaption,
                          height: 1.5,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _topicPicker(CyPalette palette) {
    String label = '暂无可开场的主题';
    for (final EventOpsTopic topic in _topics) {
      if (topic.id == _topicId) {
        label = topic.name;
        break;
      }
    }
    return GestureDetector(
      onTap: _submitting ? null : _showTopicPicker,
      child: _pickerShell(text: label, palette: palette),
    );
  }

  Future<void> _showTopicPicker() async {
    final EventOpsTopic? picked = await showCupertinoSheet<EventOpsTopic>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) {
        final CyPalette palette = CyPalette.of(context);
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space6,
          ),
          children: <Widget>[
            Text(
              '选择主题',
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            ..._topics.map(
              (EventOpsTopic topic) => ClubOpsRow(
                key: Key('event-ops-topic-${topic.id}'),
                title: topic.name,
                trailing: Text(
                  _topicId == topic.id ? '已选' : '选择',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: _topicId == topic.id
                        ? palette.brand
                        : palette.textTertiary,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(topic),
              ),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _topicId = picked.id);
  }

  Widget _leadPicker(CyPalette palette) {
    String label = '主理人（默认）';
    if (_leadMemberId != null) {
      for (final ClubMember member in _leadOptions) {
        if (member.memberId == _leadMemberId) {
          label = member.displayName;
          break;
        }
      }
    }
    return GestureDetector(
      onTap: _submitting ? null : _showLeadPicker,
      child: _pickerShell(text: label, palette: palette),
    );
  }

  Future<void> _showLeadPicker() async {
    final int? picked = await showCupertinoSheet<int>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) {
        final CyPalette palette = CyPalette.of(context);
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space6,
          ),
          children: <Widget>[
            Text(
              '默认负责人',
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            ClubOpsRow(
              key: const Key('event-ops-lead-default'),
              title: '主理人（默认）',
              trailing: Text(
                _leadMemberId == null ? '已选' : '选择',
                style: TextStyle(
                  fontSize: CyTokens.typeLabel,
                  color: _leadMemberId == null
                      ? palette.brand
                      : palette.textTertiary,
                ),
              ),
              onTap: () => Navigator.of(context).pop(-1),
            ),
            ..._leadOptions.map(
              (ClubMember member) => ClubOpsRow(
                key: Key('event-ops-lead-${member.memberId}'),
                title: member.displayName,
                trailing: Text(
                  _leadMemberId == member.memberId ? '已选' : '选择',
                  style: TextStyle(
                    fontSize: CyTokens.typeLabel,
                    color: _leadMemberId == member.memberId
                        ? palette.brand
                        : palette.textTertiary,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(member.memberId),
              ),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _leadMemberId = picked == -1 ? null : picked);
  }

  Widget _occurrenceSection() {
    final CyPalette palette = CyPalette.of(context);
    final bool busy =
        _cancellationState == _CancellationState.loading ||
        _cancellationState == _CancellationState.submitting;
    return ClubOpsSection(
      title: '本场管理',
      children: <Widget>[
        ClubOpsCard(
          children: <Widget>[
            ClubOpsRow(
              title: '本场名册',
              value: (_canCheckin && _rosterState == _RosterState.ready)
                  ? '${_roster?.registered.length ?? 0} 人'
                  : '仅核销权限可见',
            ),
            if (_cancellationState == _CancellationState.cancelled)
              ClubOpsRow(
                key: const Key('event-ops-cancelled'),
                title: '本场已取消',
                meta: <String>[
                  if (_cancellationReason.isNotEmpty) '原因：$_cancellationReason',
                  if (_cancellationSummary.isNotEmpty) _cancellationSummary,
                ].join('\n'),
                metaLines: 2,
                value: '本场已取消',
                valueColor: CyTokens.statusDanger,
              )
            else if (busy)
              ClubOpsRow(
                title: '取消本场',
                meta: _cancellationState == _CancellationState.submitting
                    ? '正在提交取消…'
                    : '正在回读本场状态…',
              )
            else if (_cancellationState == _CancellationState.error ||
                _cancellationState == _CancellationState.readbackError)
              ClubOpsRow(
                key: const Key('event-ops-cancel-error'),
                title: '取消本场',
                meta: _cancellationError,
                metaLines: 3,
                enabled: false,
                trailing: _cancellationState == _CancellationState.readbackError
                    ? ClubOpsRowLink(
                        key: const Key('event-ops-cancel-readback'),
                        label: '重新回读',
                        enabled: !_cancellationSubmitting,
                        onTap: () => _readCancellationState(
                          cancelResult: _pendingCancellationResult,
                        ),
                      )
                    : ClubOpsRowLink(
                        key: const Key('event-ops-cancel-retry'),
                        label: '重试取消本场',
                        danger: true,
                        enabled: !_cancellationSubmitting,
                        onTap: _cancelCurrentOccurrence,
                      ),
              )
            else
              ClubOpsRow(
                key: const Key('event-ops-cancel'),
                title: '取消本场',
                meta: '会下架本场、处理退款并终止候补',
                valueColor: palette.textTertiary,
                onTap: _cancelCurrentOccurrence,
              ),
          ],
        ),
      ],
    );
  }

  Widget _rosterSection() {
    final CyPalette palette = CyPalette.of(context);
    final ClubRoster? roster = _roster;
    return ClubOpsSection(
      title: '本场名册',
      note: '不展示手机号或财务信息',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: CyTokens.space3),
          child: CyTabs(
            variant: CyTabsVariant.chip,
            tabs: _rosterTabs
                .map(
                  (({String key, String label}) tab) => CyTab(
                    key: tab.key,
                    label: tab.label,
                    badge: roster == null
                        ? null
                        : switch (tab.key) {
                            'waitlist' => roster.waitlist.length,
                            'arrived' => roster.arrived.length,
                            'noShow' => roster.noShow.length,
                            _ => roster.registered.length,
                          },
                  ),
                )
                .toList(),
            active: _rosterTab,
            onChanged: (String key) => setState(() => _rosterTab = key),
          ),
        ),
        if (_rosterState == _RosterState.ready && roster != null)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space2),
            child: Text(
              '已报名 ${roster.registered.length} · 候补 ${roster.waitlist.length}'
              ' · 已到场 ${roster.arrived.length} · 未到场 ${roster.noShow.length}',
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: palette.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: CyTokens.space2),
        if (_rosterState == _RosterState.loading)
          const CySkeleton(type: CySkeletonType.card, count: 3)
        else if (_rosterState == _RosterState.error)
          StatusView(message: '名册加载失败', sub: _rosterError, onRetry: _loadRoster)
        else if (_rosterState == _RosterState.ready) ...<Widget>[
          if (_activeRoster.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
              child: StatusView(
                message: '这一段暂时没有成员',
                icon: CupertinoIcons.person_2,
              ),
            )
          else
            ClubOpsCard(
              children: _activeRoster
                  .map((RosterMember member) => _rosterRow(member, palette))
                  .toList(),
            ),
        ],
      ],
    );
  }

  Widget _rosterRow(RosterMember member, CyPalette palette) {
    final String initial = member.nickname.isEmpty
        ? '?'
        : member.nickname.substring(0, 1);
    return ClubOpsRow(
      key: Key('event-ops-roster-${member.memberId}'),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.bgSubtle,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            color: palette.textPrimary,
          ),
        ),
      ),
      title: member.nickname,
      meta:
          '成员 #${member.memberId}'
          '${_rosterTab == 'waitlist' && member.state.isNotEmpty ? ' · ${member.state}' : ''}',
      trailing: _rosterTab == 'waitlist'
          ? null
          : ClubOpsRowLink(
              key: Key('event-ops-correct-${member.memberId}'),
              label: _rosterTab == 'arrived' ? '更正未到' : '标记到场',
              enabled: _actingMemberId == null,
              onTap: () => _correctAttendance(member),
            ),
    );
  }

  Widget _optionChip({
    required Key key,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? palette.brandSoft : palette.inputBgEmpty,
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          border: Border.all(
            color: active ? palette.brand : palette.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: CyTokens.typeLabel,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? palette.brand : palette.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _pickerShell({required String text, required CyPalette palette}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: CyTokens.typeBody,
                color: palette.textPrimary,
              ),
            ),
          ),
          Icon(
            CupertinoIcons.chevron_down,
            size: 16,
            color: palette.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _fieldPicker({
    required Key key,
    required String text,
    required VoidCallback onTap,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: _pickerShell(text: text, palette: palette),
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String placeholder,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: placeholder,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: CyTokens.typeBody, color: palette.textPrimary),
      placeholderStyle: TextStyle(
        fontSize: CyTokens.typeBody,
        color: palette.textPlaceholder,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2_5,
        vertical: CyTokens.space2,
      ),
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: palette.borderSubtle),
      ),
    );
  }
}

class _AddDateRow extends StatelessWidget {
  const _AddDateRow({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return GestureDetector(
      key: const Key('event-ops-add-date'),
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CyTokens.radiusSm),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              CupertinoIcons.add,
              size: 16,
              color: enabled ? palette.brand : palette.textDisabled,
            ),
            const SizedBox(width: CyTokens.space1),
            Text(
              '添加日期',
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: enabled ? palette.brand : palette.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
