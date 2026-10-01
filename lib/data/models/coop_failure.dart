/// Source of collaboration errors is explicit; wording never determines origin.
enum CoopFailureKind {
  operation, refundUnknown, refundRetry, templateId, conversation,
  missingSettlementId, settlementUnavailable, invalidSettlementSource,
}

class CoopFailure implements Exception {
  const CoopFailure.local(this.kind, this.message) : isLocalFallback = true;
  const CoopFailure.server(this.message) : kind = CoopFailureKind.operation,
      isLocalFallback = false;
  final CoopFailureKind kind;
  final String message;
  final bool isLocalFallback;
  @override
  String toString() => 'Exception: $message';
}
