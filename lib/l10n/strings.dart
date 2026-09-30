import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_zh.dart';

/// Existing isolated widget hosts have no app delegate. Preserve their Chinese
/// fixture language; production ChengyinApp always installs generated delegates.
AppLocalizations stringsOf(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsZh();
