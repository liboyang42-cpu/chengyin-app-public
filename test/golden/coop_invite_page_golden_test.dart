import 'package:chengyin_app/data/models/coop_invite.dart';
import 'package:chengyin_app/feature/coop/coop_invite_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

void main() {
  testWidgets('协作邀请保持主题、条款、对象的小程序顺序', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 1000));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: const CoopInvitePage(
            topicId: 9,
            topicName: '静安夜行',
            type: CoopInviteType.club,
            toId: 7,
            toName: '城市漫步俱乐部',
            originApplyId: 66,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_coop_invite.png'),
    );
  });
}
