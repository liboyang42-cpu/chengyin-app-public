import '../data/api/my_project_api.dart';
import 'app_localizations.dart';

String? myProjectErrorCopy(AppLocalizations strings, Object error) {
  if (error is! MyProjectApiException) return null;
  return switch (error.localCode) {
    'load' => strings.myProjectApiLoad,
    'action' => strings.myProjectApiAction,
    'removeUnsupported' => strings.myProjectApiRemoveUnsupported,
    'statusUnsupported' => strings.myProjectApiStatusUnsupported,
    _ => error.message,
  };
}
