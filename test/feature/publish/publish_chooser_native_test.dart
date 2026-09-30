import 'package:chengyin_app/feature/publish/publish_capability.dart';
import 'package:chengyin_app/feature/publish/publish_chooser_sheet.dart';
import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cupertino Sheet 内仍是四张源大卡，不降级成 Form rows', (
    WidgetTester tester,
  ) async {
    await _pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(PublishChooserView), findsOneWidget);
    expect(find.byKey(const Key('publish-chooser-cards')), findsOneWidget);
    expect(find.byKey(const Key('publish-card-art-一条城市路线')), findsOneWidget);
    expect(find.byKey(const Key('publish-chooser-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('publish-chooser-dot-3')), findsOneWidget);
    expect(find.text('一条城市路线'), findsOneWidget);
    expect(find.text('从灵感到可玩，只差一次发布'), findsOneWidget);
  });

  testWidgets('四卡继承小程序 340:215 插画比例和 44pt CTA', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpHost(tester, textScaler: const TextScaler.linear(1.4));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final AspectRatio art = tester.widget<AspectRatio>(
      find.byKey(const Key('publish-card-art-一条城市路线')),
    );
    expect(art.aspectRatio, closeTo(340 / 215, 0.0001));
    expect(
      tester.getSize(find.byKey(const Key('publish-card-cta-一条城市路线'))).height,
      greaterThanOrEqualTo(44),
    );
    final node = tester.getSemantics(
      find.byKey(const Key('publish-card-cta-一条城市路线')),
    );
    expect(node.label, contains('发布主题，一条城市路线，开始创建'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('并发点击只呈现一层发布 Sheet', (WidgetTester tester) async {
    late BuildContext hostContext;
    await _pumpHost(
      tester,
      onContext: (BuildContext context) => hostContext = context,
    );

    final Future<void> first = showPublishChooser(hostContext);
    final Future<void> second = showPublishChooser(hostContext);
    await tester.pumpAndSettle();

    expect(find.byType(PublishChooserView), findsOneWidget);
    await tester.tap(find.byKey(const Key('publish-chooser-close')));
    await tester.pumpAndSettle();
    await Future.wait(<Future<void>>[first, second]);
  });

  testWidgets('320x568、200% 字号与减少动态下发布 Sheet 仍可操作', (
    WidgetTester tester,
  ) async {
    const Size viewport = Size(320, 568);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHost(
      tester,
      viewport: viewport,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('发布主题'), findsOneWidget);
    expect(find.text('一条城市路线'), findsOneWidget);
    expect(find.byKey(const Key('publish-card-cta-一条城市路线')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('publish-card-cta-一条城市路线'))).height,
      greaterThanOrEqualTo(44),
    );
    final Iterable<AnimatedContainer> dots = tester.widgetList(
      find.descendant(
        of: find.byType(PublishChooserView),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(dots, isNotEmpty);
    expect(
      dots.every((AnimatedContainer dot) => dot.duration == Duration.zero),
      isTrue,
    );
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  PublishCapability capability = const PublishCapability(),
  ValueChanged<BuildContext>? onContext,
  TextScaler textScaler = TextScaler.noScaling,
  Size? viewport,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        publishCapabilityProvider.overrideWith((Ref ref) async => capability),
      ].cast(),
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: viewport,
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) {
            onContext?.call(context);
            return Scaffold(
              body: FilledButton(
                onPressed: () => showPublishChooser(context),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
