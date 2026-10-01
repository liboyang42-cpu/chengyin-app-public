import 'package:flutter/cupertino.dart';

import '../../l10n/error_presentation.dart';
import '../../l10n/strings.dart';
import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';
import 'status_view.dart';

/// A shared error surface that keeps localized guidance and original detail apart.
class LocalizedErrorStatus extends StatelessWidget {
  const LocalizedErrorStatus({
    super.key,
    required this.error,
    required this.onRetry,
    this.fallback,
    this.hint,
    this.originalApiMessage,
    this.large = true,
  });
  final Object error;
  final VoidCallback onRetry;
  final String? fallback;
  final String? hint;
  final String? originalApiMessage;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final presentation = presentError(error, stringsOf(context),
        fallback: fallback, originalApiMessage: originalApiMessage);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusView(message: presentation.summary, sub: hint, large: large, onRetry: onRetry),
        if (presentation.detail != null)
          Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(presentation.detailLabel!, style: CyType.caption1.copyWith(
                    color: CyPalette.of(context).textSecondary)),
                Text(presentation.detail!, textAlign: TextAlign.center,
                    style: CyType.body.copyWith(color: CyPalette.of(context).textPrimary)),
              ],
            ),
          ),
      ],
    );
  }
}
