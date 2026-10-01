/// Published cancel-by-owner feedback. Cancellation is not proof of payout.
class RegistrationCancellationOutcome {
  const RegistrationCancellationOutcome({
    this.message = '',
    this.registrationId,
    this.cancellationStatus = 'UNCONFIRMED',
    this.cashRefundStatus = 'UNCONFIRMED',
    this.pointsRefundStatus = 'UNCONFIRMED',
  });

  final String message;
  final int? registrationId;
  final String cancellationStatus;
  final String cashRefundStatus;
  final String pointsRefundStatus;

  factory RegistrationCancellationOutcome.fromResponse(Map<String, dynamic> body) {
    final raw = body['data'];
    final data = raw is Map ? raw : const <String, dynamic>{};
    String status(String key) => data[key] is String && (data[key] as String).isNotEmpty
        ? data[key] as String : 'UNCONFIRMED';
    return RegistrationCancellationOutcome(
      message: body['msg'] is String ? body['msg'] as String : '',
      registrationId: int.tryParse('${data['registrationId'] ?? ''}'),
      cancellationStatus: status('cancellationStatus'),
      cashRefundStatus: status('cashRefundStatus'),
      pointsRefundStatus: status('pointsRefundStatus'),
    );
  }
}
