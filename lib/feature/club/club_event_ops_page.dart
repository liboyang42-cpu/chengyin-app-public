import 'club_customer_labels.dart';
import 'club_occurrence_labels.dart';
import '../../l10n/strings.dart';
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
  List<({String key, String label})> get _rosterTabs =>
      <({String key, String label})>[
        (key: 'registered', label: stringsOf(context).clubEventRegistered),
        (key: 'waitlist', label: stringsOf(context).clubEventWaitlist),
        (key: 'arrived', label: stringsOf(context).clubEventArrived),
        (key: 'noShow', label: stringsOf(context).clubEventNoShow),
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
        deniedMessage: stringsOf(context).clubEventDeniedReason,
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
        _error = clubOpsErrorMessage(error, stringsOf(context).clubEventAccessUnavailable);
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
      setState(() => _leadLoadWarning = stringsOf(context).clubEventLeadsUnavailable);
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
        _seriesError = clubOpsErrorMessage(error, stringsOf(context).clubEventSeriesFailed);
      });
    }
  }

  String _seriesTitle(EventSeries series) {
    for (final EventOpsTopic topic in _topics) {
      if (topic.id == series.topicId) return topic.name;
    }
    return stringsOf(context).clubEventTopicNumber(series.topicId);
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
        clubOpsErrorMessage(error, stringsOf(context).clubEventSeriesDetailsFailed),
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
      title: stringsOf(context).clubEventFirstDate,
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
      title: stringsOf(context).clubEventMeetingTime,
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
      title: stringsOf(context).clubEventDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _customDates[index] = _dateWire(picked));
  }

  Future<void> _submitSeries() async {
    if (!_canManage || _submitting) return;
    final int? editingId = _editingSeriesId;
    final int? topicId = editingId != null ? _editingTopicId : _topicId;
    if (topicId == null || topicId <= 0) {
      CyNativeNotice.show(context, stringsOf(context).clubEventNoTopics, isError: true);
      return;
    }
    final int? version = _expectedVersion;
    if (editingId != null && (version == null || version < 0)) {
      CyNativeNotice.show(context, stringsOf(context).clubEventMissingVersion, isError: true);
      return;
    }
    final int? count = int.tryParse(_countCtrl.text.trim());
    final int offerMinutes = int.tryParse(_offerCtrl.text.trim()) ?? -1;
    final int? capacity = _capacityCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_capacityCtrl.text.trim());
    if (_recurrenceType == 'WEEKLY' &&
        (count == null || count < 1 || count > 64)) {
      CyNativeNotice.show(context, stringsOf(context).clubEventCountInvalid, isError: true);
      return;
    }
    if (_capacityCtrl.text.trim().isNotEmpty &&
        (capacity == null || capacity < 1 || capacity > 10000)) {
      CyNativeNotice.show(context, stringsOf(context).clubEventCapacityInvalid, isError: true);
      return;
    }
    if (offerMinutes < 5 || offerMinutes > 1440) {
      CyNativeNotice.show(context, stringsOf(context).clubEventWindowInvalid, isError: true);
      return;
    }
    final List<String> customDates =
        _customDates.where((String d) => d.isNotEmpty).toSet().toList()..sort();
    if (_recurrenceType == 'CUSTOM_DATES' && customDates.isEmpty) {
      CyNativeNotice.show(context, stringsOf(context).clubEventDatesRequired, isError: true);
      return;
    }
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_startTime)) {
      CyNativeNotice.show(context, stringsOf(context).clubEventTimeRequired, isError: true);
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
      CyNativeNotice.show(context, editingId != null ? stringsOf(context).clubEventUpdated : stringsOf(context).clubEventCreated);
      _resetSeriesForm();
      await _loadSeries();
    } on ClubOpsConflictException {
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).clubEventVersionChanged, isError: true);
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
        clubOpsErrorMessage(error, editingId != null ? stringsOf(context).clubEventUpdateFailed : stringsOf(context).clubEventCreateFailed),
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
          _cancellationError = stringsOf(context).clubEventReadbackFailed;
        });
        return;
      }
      if (cancelResult != null && !status.cancelled) {
        setState(() {
          _cancellationState = _CancellationState.readbackError;
          _cancellationError = stringsOf(context).clubEventCancellationUnconfirmed;
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
        CyNativeNotice.show(context, stringsOf(context).clubEventCancelledConfirmed);
        await _loadSeries();
        if (_canCheckin) await _loadRoster();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancellationState = _CancellationState.readbackError;
        _cancellationError = clubOpsErrorMessage(error, stringsOf(context).clubEventReadbackFailed);
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
      title: stringsOf(context).clubEventCancelTitle,
      placeholder: stringsOf(context).clubEventCancelReasonHint,
      confirmText: stringsOf(context).clubEventConfirmCancel,
      keyboardKind: CySystemKeyboardKind.text,
    );
    if (raw == null || !mounted) return;
    final String reason = raw.trim();
    if (reason.length < 2 || reason.length > 255) {
      CyNativeNotice.show(context, stringsOf(context).clubEventCancelReasonInvalid, isError: true);
      return;
    }
    // 原因合法后不直接发请求:先过 T2 居中二次确认(只能点按钮)。
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).clubEventCancelConfirmation,
      content: stringsOf(context).clubEventCancelPolicy,
      confirmText: stringsOf(context).clubEventCancelSession,
      cancelText: stringsOf(context).clubEventReconsider,
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
          _cancellationError = stringsOf(context).clubEventCancelFailed;
        });
        return;
      }
      _pendingCancellationResult = result;
      await _readCancellationState(cancelResult: result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancellationState = _CancellationState.error;
        _cancellationError = clubOpsErrorMessage(error, stringsOf(context).clubEventCancelUnknown);
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
          _rosterError = stringsOf(context).clubEventRosterIncomplete;
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
        _rosterError = clubOpsErrorMessage(error, stringsOf(context).clubEventRosterFailed);
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
      title: arrived ? stringsOf(context).clubEventCorrectArrived : stringsOf(context).clubEventCorrectNoShow,
      placeholder: stringsOf(context).clubEventCorrectionReasonHint,
      confirmText: stringsOf(context).clubEventSubmit,
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
        CyNativeNotice.show(context, stringsOf(context).clubEventAttendanceCorrected);
        await _loadRoster();
        return;
      }
      CyNativeNotice.show(context, stringsOf(context).clubEventCorrectionFailed, isError: true);
    } catch (error) {
      if (!mounted) return;
      if (error is ClubOpsRejectedException) {
        _attendanceRequestIds.remove(intentKey);
      }
      CyNativeNotice.show(
        context,
        clubOpsErrorMessage(error, stringsOf(context).clubEventCorrectionFailed),
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
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).clubEventTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubEventTitle),
              Expanded(child: _body()),
              if (_state == ClubOpsLoadState.ready && _canManage)
                CyFooterBar(
                  primary: CyNativeButton(
                    key: const Key('event-ops-submit'),
                    label: _submitting
                        ? stringsOf(context).clubEventSubmitting
                        : (_editingSeriesId != null ? stringsOf(context).clubEventSaveFuture : stringsOf(context).clubEventCreateSeries),
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
      return ClubLoginGate(message: stringsOf(context).clubEventLogin, onSignedIn: _loadAccess);
    }
    switch (_state) {
      case ClubOpsLoadState.loading:
        return const CySkeleton(type: CySkeletonType.card, count: 4);
      case ClubOpsLoadState.noPermission:
        return StatusView(
          message: stringsOf(context).clubEventDenied,
          sub: _error.isEmpty ? stringsOf(context).clubEventDeniedBody : _error,
          icon: CupertinoIcons.lock,
          large: true,
        );
      case ClubOpsLoadState.networkError:
        return StatusView(
          message: stringsOf(context).clubEventNetworkFailed,
          sub: _error,
          icon: CupertinoIcons.exclamationmark_triangle,
          large: true,
          onRetry: _loadAccess,
        );
      case ClubOpsLoadState.error:
        return StatusView(
          message: stringsOf(context).clubEventUnavailable,
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
      title: stringsOf(context).clubEventDates,
      note: stringsOf(context).clubEventEditScope,
      children: <Widget>[
        if (_seriesState == _SeriesState.loading)
          const Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: CySkeleton(type: CySkeletonType.card, count: 2),
          )
        else if (_seriesState == _SeriesState.error)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: stringsOf(context).clubEventSeriesFailed,
              sub: _seriesError,
              onRetry: _loadSeries,
            ),
          )
        else if (_seriesState == _SeriesState.empty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: stringsOf(context).clubEventNoSeries,
              sub: stringsOf(context).clubEventNoSeriesBody,
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
                      '${_seriesTitle(series)} · ${_recurrenceLabel(context, series.recurrenceType)}',
                  meta:
                      stringsOf(context).clubEventSeriesSummary(series.version.toString(), series.waitlistEnabled ? stringsOf(context).clubEventWaitlistOn : stringsOf(context).clubEventWaitlistOff, series.futureDates.length),
                  value: _editingSeriesId == series.id ? stringsOf(context).clubEventEditing : stringsOf(context).clubEventEditFuture,
                  valueColor: _editingSeriesId == series.id
                      ? palette.brand
                      : palette.textTertiary,
                  enabled: !_submitting && !_seriesDetailLoading,
                  onTap: () => _beginEditSeries(series),
                ),
                ClubOpsRow(
                  key: Key('event-ops-series-dates-${series.id}'),
                  title: stringsOf(context).clubEventAllDates,
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
          stringsOf(context).clubEventDatesFailed,
          style: TextStyle(
            fontSize: CyTokens.typeCaption,
            color: palette.textTertiary,
          ),
        );
      case _OccurrenceState.empty:
        return Text(
          stringsOf(context).clubEventNoMaterializedSessions,
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
                              clubOccurrenceDate(context, occ),
                              style: TextStyle(
                                fontSize: CyTokens.typeLabel,
                                color: palette.textPrimary,
                              ),
                            ),
                            Text(
                              clubOccurrenceMeta(context, occ),
                              style: TextStyle(
                                fontSize: CyTokens.typeCaption,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        clubOccurrenceBadge(context, occ),
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
      title: editing ? stringsOf(context).clubEventEditFuture : stringsOf(context).clubEventCreateSeries,
      children: <Widget>[
        if (_topics.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space3),
            child: StatusView(
              message: stringsOf(context).clubEventNoTopics,
              sub: stringsOf(context).clubEventNoTopicsBody,
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
                      label: stringsOf(context).clubEventTopic,
                      child: editing
                          ? Text(
                              stringsOf(context).clubEventLockedTopic(_editingTopicId.toString()),
                              style: TextStyle(
                                fontSize: CyTokens.typeBody,
                                color: palette.textSecondary,
                              ),
                            )
                          : _topicPicker(palette),
                    ),
                    CyField(
                      label: stringsOf(context).clubEventRecurrence,
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
                                    label: _recurrenceLabel(context, item.value),
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
                        label: stringsOf(context).clubEventFirstDate,
                        child: _fieldPicker(
                          key: const Key('event-ops-start-date'),
                          text: _startDate,
                          onTap: _pickStartDate,
                        ),
                      ),
                    if (_recurrenceType == 'WEEKLY')
                      CyField(
                        label: stringsOf(context).clubEventSessionCount,
                        child: _numberField(
                          key: const Key('event-ops-count'),
                          controller: _countCtrl,
                          placeholder: '1–64',
                        ),
                      ),
                    if (_recurrenceType == 'CUSTOM_DATES') ...<Widget>[
                      CyField(
                        label: stringsOf(context).clubEventDates,
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
                                      label: stringsOf(context).clubEventRemove,
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
                      label: stringsOf(context).clubEventMeetingTime,
                      child: _fieldPicker(
                        key: const Key('event-ops-start-time'),
                        text: _startTime,
                        onTap: _pickStartTime,
                      ),
                    ),
                    Text(
                      stringsOf(context).clubEventRefundWindow,
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: palette.textTertiary,
                      ),
                    ),
                    if (!editing) ...<Widget>[
                      const SizedBox(height: CyTokens.space3),
                      CyField(label: stringsOf(context).clubEventDefaultLead, child: _leadPicker(palette)),
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
                      label: stringsOf(context).clubEventCapacity,
                      child: _numberField(
                        key: const Key('event-ops-capacity'),
                        controller: _capacityCtrl,
                        placeholder: stringsOf(context).clubEventUseTicketCapacity,
                      ),
                    ),
                    Text(
                      stringsOf(context).clubEventCapacityScope,
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
                                  stringsOf(context).clubEventEnableWaitlist,
                                  style: TextStyle(
                                    fontSize: CyTokens.typeBody,
                                    fontWeight: FontWeight.w600,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                Text(
                                  stringsOf(context).clubEventWaitlistOrder,
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
                        label: stringsOf(context).clubEventClaimWindow,
                        child: _numberField(
                          key: const Key('event-ops-offer'),
                          controller: _offerCtrl,
                          placeholder: '5–1440',
                        ),
                      ),
                      Text(
                        stringsOf(context).clubEventClaimWindowPolicy,
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
    String label = stringsOf(context).clubEventNoTopics;
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
              stringsOf(context).clubEventSelectTopic,
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
                  _topicId == topic.id ? stringsOf(context).clubEventSelected : stringsOf(context).clubEventSelect,
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
    String label = stringsOf(context).clubEventOwnerDefault;
    if (_leadMemberId != null) {
      for (final ClubMember member in _leadOptions) {
        if (member.memberId == _leadMemberId) {
          label = clubMemberDisplayName(context, member);
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
              stringsOf(context).clubEventDefaultLead,
              style: TextStyle(
                fontSize: CyTokens.typeSectionTitle,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            ClubOpsRow(
              key: const Key('event-ops-lead-default'),
              title: stringsOf(context).clubEventOwnerDefault,
              trailing: Text(
                _leadMemberId == null ? stringsOf(context).clubEventSelected : stringsOf(context).clubEventSelect,
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
                title: clubMemberDisplayName(context, member),
                trailing: Text(
                  _leadMemberId == member.memberId ? stringsOf(context).clubEventSelected : stringsOf(context).clubEventSelect,
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
      title: stringsOf(context).clubEventSessionManagement,
      children: <Widget>[
        ClubOpsCard(
          children: <Widget>[
            ClubOpsRow(
              title: stringsOf(context).clubEventSessionRoster,
              value: (_canCheckin && _rosterState == _RosterState.ready)
                  ? stringsOf(context).clubEventPeople(_roster?.registered.length ?? 0)
                  : stringsOf(context).clubEventRosterPermission,
            ),
            if (_cancellationState == _CancellationState.cancelled)
              ClubOpsRow(
                key: const Key('event-ops-cancelled'),
                title: stringsOf(context).clubEventSessionCancelled,
                meta: <String>[
                  if (_cancellationReason.isNotEmpty) stringsOf(context).clubEventReason(_cancellationReason),
                  if (_cancellationSummary.isNotEmpty) _cancellationSummary,
                ].join('\n'),
                metaLines: 2,
                value: stringsOf(context).clubEventSessionCancelled,
                valueColor: CyTokens.statusDanger,
              )
            else if (busy)
              ClubOpsRow(
                title: stringsOf(context).clubEventCancelSession,
                meta: _cancellationState == _CancellationState.submitting
                    ? stringsOf(context).clubEventCancelling
                    : stringsOf(context).clubEventCheckingCancellation,
              )
            else if (_cancellationState == _CancellationState.error ||
                _cancellationState == _CancellationState.readbackError)
              ClubOpsRow(
                key: const Key('event-ops-cancel-error'),
                title: stringsOf(context).clubEventCancelSession,
                meta: _cancellationError,
                metaLines: 3,
                enabled: false,
                trailing: _cancellationState == _CancellationState.readbackError
                    ? ClubOpsRowLink(
                        key: const Key('event-ops-cancel-readback'),
                        label: stringsOf(context).clubEventReadAgain,
                        enabled: !_cancellationSubmitting,
                        onTap: () => _readCancellationState(
                          cancelResult: _pendingCancellationResult,
                        ),
                      )
                    : ClubOpsRowLink(
                        key: const Key('event-ops-cancel-retry'),
                        label: stringsOf(context).clubEventRetryCancellation,
                        danger: true,
                        enabled: !_cancellationSubmitting,
                        onTap: _cancelCurrentOccurrence,
                      ),
              )
            else
              ClubOpsRow(
                key: const Key('event-ops-cancel'),
                title: stringsOf(context).clubEventCancelSession,
                meta: stringsOf(context).clubEventCancellationEffects,
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
      title: stringsOf(context).clubEventSessionRoster,
      note: stringsOf(context).clubEventRosterPrivacy,
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
              stringsOf(context).clubEventRosterSummary(roster.registered.length, roster.waitlist.length, roster.arrived.length, roster.noShow.length),
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
          StatusView(message: stringsOf(context).clubEventRosterFailed, sub: _rosterError, onRetry: _loadRoster)
        else if (_rosterState == _RosterState.ready) ...<Widget>[
          if (_activeRoster.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
              child: StatusView(
                message: stringsOf(context).clubEventRosterEmpty,
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
          stringsOf(context).clubEventMember(member.memberId)
          '${_rosterTab == 'waitlist' && member.state.isNotEmpty ? ' · ${member.state}' : ''}',
      trailing: _rosterTab == 'waitlist'
          ? null
          : ClubOpsRowLink(
              key: Key('event-ops-correct-${member.memberId}'),
              label: _rosterTab == 'arrived' ? stringsOf(context).clubEventMarkNoShow : stringsOf(context).clubEventMarkArrived,
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
              stringsOf(context).clubEventAddDate,
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

String _recurrenceLabel(BuildContext context, String value) => switch (value) {
  'ONCE' => stringsOf(context).clubEventOnce,
  'WEEKLY' => stringsOf(context).clubEventWeekly,
  'CUSTOM_DATES' => stringsOf(context).clubEventCustomDates,
  _ => value,
};
