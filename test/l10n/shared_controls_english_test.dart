import 'package:chengyin_app/core/router/route_error_page.dart';
import 'package:chengyin_app/core/widgets/cy_image_source_sheet.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImageDriver implements CyNativeImageSourceDriver {
  @override
  bool get supportsLiquidGlass => true;
  List<CyNativeImageSourceAction> actions = [];

  @override
  Future<String?> showActionSheet({
    required BuildContext context,
    required List<CyNativeImageSourceAction> actions,
    Rect? sourceRect,
  }) async {
    this.actions = actions;
    return 'gallery';
  }
}

Widget _app(Widget child) => CupertinoApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: MediaQuery(
    data: const MediaQueryData(textScaler: TextScaler.linear(2)),
    child: child,
  ),
);

void main() {
  test('unread announcements use singular and plural without changing label', () {
    final strings = AppLocalizationsEn();
    expect(strings.sharedUnreadTabLabel('活动', 1), '活动, 1 unread item');
    expect(strings.sharedUnreadTabLabel('Inbox', 3), 'Inbox, 3 unread items');
  });

  testWidgets('native photo driver receives selected app language', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(_app(Builder(builder: (value) {
      context = value;
      return const SizedBox.shrink();
    })));
    final driver = _ImageDriver();
    expect(await cyChooseImageSource(context, nativeDriver: driver), CyImagePickSource.gallery);
    expect(driver.actions.map((action) => action.title), ['Take photo', 'Choose from library', 'Cancel']);
    expect(driver.actions.map((action) => action.id), ['camera', 'gallery', 'cancel']);
  });

  testWidgets('unknown route has English recovery at large text size', (tester) async {
    await tester.pumpWidget(_app(const RouteErrorPage(error: null)));
    expect(find.text('This page could not be found'), findsOneWidget);
    expect(find.text('The link may have expired or contain a typo. Continue from Home.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared progress has one localized announcement and visible label', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(const LoadingView(message: 'Planning route…')));
      expect(find.text('Planning route…'), findsOneWidget);
      expect(find.bySemanticsLabel('Planning route…'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('shared status preserves detail and localizes retry', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(StatusView(message: 'Not available', sub: '服务器原文', onRetry: () {})));
      expect(find.text('服务器原文'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.bySemanticsLabel('Not available. 服务器原文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
