import 'package:chengyin_app/core/feature_flags.dart';
import 'package:chengyin_app/feature/square/community_post_feature_gate.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({required bool enabled, required CommunityPostAccess access}) {
    return ProviderScope(
      overrides: [featureFlagProvider.overrideWith((ref, name) => enabled)],
      child: CupertinoApp(
        home: CommunityPostFeatureGateView(
          access: access,
          child: const Text('真实社区页面', key: Key('community-content')),
        ),
      ),
    );
  }

  testWidgets('missing or disabled read flag fails closed', (tester) async {
    await tester.pumpWidget(
      app(enabled: false, access: CommunityPostAccess.read),
    );

    expect(find.byKey(const Key('community-post-closed')), findsOneWidget);
    expect(
      find.byKey(const Key('community-post-closed-drafts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('community-post-closed-governance')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('community-content')), findsNothing);
  });

  testWidgets('enabled write flag exposes the real route content', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(enabled: true, access: CommunityPostAccess.write),
    );

    expect(find.byKey(const Key('community-content')), findsOneWidget);
    expect(find.byKey(const Key('community-post-closed')), findsNothing);
  });
}
