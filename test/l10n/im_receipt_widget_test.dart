import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements ImApi {
  _Api(this.serverText);
  final String? serverText;
  int calls = 0;
  @override
  Future<ImReceipt> muteReceipt(int conversationId, {required bool muted}) async {
    calls++;
    return ImReceipt(ImReceiptKind.muted, serverMessage: serverText);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Presenter implements ImConversationActionPresenter {
  @override
  Future<String?> showActionSheet({required BuildContext context,
    required List<ImConversationActionItem> items}) async => 'mute';
}
void main() {
  for (final original in <String?>[null, '已开启免打扰']) {
    testWidgets('English mute receipt preserves provenance: $original', (tester) async {
      final api = _Api(original);
      await tester.pumpWidget(ProviderScope(overrides: [
        imApiProvider.overrideWithValue(api),
        imConversationsProvider.overrideWith((ref) async => [Conversation(
          conversationId: 7, type: kImTypeSingle, muted: false,
          counterparty: ImCounterparty(id: 8, nickname: '原始姓名', avatar: ''),
        )]),
      ], child: MaterialApp(locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImListPage(actionPresenter: _Presenter()))));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('原始姓名'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(find.text(original ?? 'Notifications muted'), findsOneWidget);
      expect(find.text('原始姓名'), findsOneWidget);
      expect(tester.takeException(), isNull);
      CyNativeNotice.hide();
      await tester.pump();
    });
  }
}
