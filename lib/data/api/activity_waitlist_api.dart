import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart' show dioClientProvider;
import '../models/activity_waitlist.dart';

final activityWaitlistApiProvider = Provider<ActivityWaitlistGateway>((ref) {
  return ActivityWaitlistApi(ref.watch(dioClientProvider));
});

abstract interface class ActivityWaitlistGateway {
  Future<ActivityWaitlistStatus> status({
    required int activityId,
    required int ticketId,
  });

  Future<ActivityWaitlistStatus> join({
    required int activityId,
    required int ticketId,
  });

  Future<ActivityWaitlistStatus> cancel({
    required int activityId,
    required int ticketId,
  });
}

class ActivityWaitlistException implements Exception {
  const ActivityWaitlistException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ActivityWaitlistApi implements ActivityWaitlistGateway {
  ActivityWaitlistApi(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DioClient _client;
  final DateTime Function() _now;

  @override
  Future<ActivityWaitlistStatus> status({
    required int activityId,
    required int ticketId,
  }) async {
    _validateScope(activityId, ticketId);
    final Map<String, dynamic> data = await _postData(
      '/api/club/event-ops/waitlist/status',
      activityId: activityId,
      ticketId: ticketId,
    );
    try {
      return ActivityWaitlistStatus.fromJson(
        data,
        expectedActivityId: activityId,
        expectedTicketId: ticketId,
        now: _now(),
      );
    } on FormatException {
      throw const ActivityWaitlistException('候补状态回执不完整');
    }
  }

  @override
  Future<ActivityWaitlistStatus> join({
    required int activityId,
    required int ticketId,
  }) => _writeThenRead(
    path: '/api/club/event-ops/waitlist/join',
    activityId: activityId,
    ticketId: ticketId,
    operation: '加入候补',
    validateReceipt: (Map<String, dynamic> body) {
      final Object? raw = body['data'];
      if (raw is! Map) throw const _WaitlistProtocolException();
      final Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(raw);
      } on TypeError {
        throw const _WaitlistProtocolException();
      }
      final int? id = _positiveInt(data['id']);
      if (id == null ||
          _positiveInt(data['activityId']) != activityId ||
          _positiveInt(data['ticketId']) != ticketId ||
          data['state'] != 'WAITING') {
        throw const _WaitlistProtocolException();
      }
      return _WriteReceipt(id: id);
    },
    accepted: (ActivityWaitlistStatus value) =>
        value.isQueueActive ||
        value.state == ActivityWaitlistState.claimed ||
        value.state == ActivityWaitlistState.converted,
  );

  @override
  Future<ActivityWaitlistStatus> cancel({
    required int activityId,
    required int ticketId,
  }) => _writeThenRead(
    path: '/api/club/event-ops/waitlist/cancel',
    activityId: activityId,
    ticketId: ticketId,
    operation: '退出候补',
    validateReceipt: (Map<String, dynamic> body) {
      if (body['data'] is! bool) throw const _WaitlistProtocolException();
      return const _WriteReceipt();
    },
    accepted: (ActivityWaitlistStatus value) =>
        value.state == ActivityWaitlistState.none ||
        value.state == ActivityWaitlistState.cancelled ||
        value.state == ActivityWaitlistState.expired,
  );

  Future<ActivityWaitlistStatus> _writeThenRead({
    required String path,
    required int activityId,
    required int ticketId,
    required String operation,
    required _WriteReceipt Function(Map<String, dynamic> body) validateReceipt,
    required bool Function(ActivityWaitlistStatus value) accepted,
  }) async {
    _validateScope(activityId, ticketId);
    Object? writeFailure;
    _WriteReceipt? receipt;
    try {
      final Map<String, dynamic> body = await _postRaw(
        path,
        activityId: activityId,
        ticketId: ticketId,
      );
      receipt = validateReceipt(body);
    } catch (error) {
      writeFailure = error;
    }

    ActivityWaitlistStatus readback;
    try {
      readback = await status(activityId: activityId, ticketId: ticketId);
    } catch (_) {
      if (writeFailure is ActivityWaitlistException) throw writeFailure;
      throw ActivityWaitlistException('$operation结果未知，请刷新候补状态');
    }
    if (writeFailure is _WaitlistProtocolException) throw writeFailure;
    if (writeFailure is ActivityWaitlistException) throw writeFailure;
    if (accepted(readback) &&
        (receipt?.id == null || receipt!.id == readback.id)) {
      return readback;
    }
    if (receipt?.id != null && receipt!.id != readback.id) {
      throw const _WaitlistProtocolException();
    }
    throw ActivityWaitlistException('$operation结果未知，请刷新候补状态');
  }

  Future<Map<String, dynamic>> _postData(
    String path, {
    required int activityId,
    required int ticketId,
  }) async {
    final Map<String, dynamic> body = await _postRaw(
      path,
      activityId: activityId,
      ticketId: ticketId,
    );
    final Object? data = body['data'];
    if (data is! Map) {
      throw const _WaitlistProtocolException('候补状态回执不完整');
    }
    try {
      return Map<String, dynamic>.from(data);
    } on TypeError {
      throw const _WaitlistProtocolException('候补状态回执不完整');
    }
  }

  Future<Map<String, dynamic>> _postRaw(
    String path, {
    required int activityId,
    required int ticketId,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: <String, dynamic>{'activityId': activityId, 'ticketId': ticketId},
    );
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    final int? code = _strictInteger(body['code']);
    if (code == null) {
      throw const _WaitlistProtocolException();
    }
    if (code != 200) {
      final Object? message = body['msg'];
      throw ActivityWaitlistException(
        message is String && message.trim().isNotEmpty
            ? message.trim()
            : '候补操作失败',
      );
    }
    return body;
  }

  void _validateScope(int activityId, int ticketId) {
    if (activityId <= 0 || ticketId <= 0) {
      throw const ActivityWaitlistException('候补范围不完整');
    }
  }
}

class _WaitlistProtocolException extends ActivityWaitlistException {
  const _WaitlistProtocolException([super.message = '候补服务回执不完整']);
}

class _WriteReceipt {
  const _WriteReceipt({this.id});

  final int? id;
}

int? _strictInteger(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.toInt()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value);
  return null;
}

int? _positiveInt(Object? value) {
  final int? parsed = _strictInteger(value);
  return parsed != null && parsed > 0 ? parsed : null;
}
