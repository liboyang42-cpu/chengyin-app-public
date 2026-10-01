import 'package:chengyin_app/data/models/coop_invite.dart';
import 'package:chengyin_app/data/models/coop_pool.dart';
import 'package:chengyin_app/feature/coop/coop_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English application copy preserves supplied names, messages and invitation wire data', (tester) async {
    const target = CoopInviteTarget(toId: 9, name: '未命名主题');
    const form = CoopInviteForm(topicId: 4, targets: [target], message: '用户原文');
    final before = form.toJson(target);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        expect(coopPoolName(context, CoopPoolItem.fromJson({'topicId': 4})), 'Unnamed theme');
        expect(coopPoolName(context, CoopPoolItem.fromJson({'topicId': 4, 'name': '未命名主题'})), '未命名主题');
        const missing = CoopPoolApply(applyId: 2, topicId: 4, status: 0);
        const supplied = CoopPoolApply(applyId: 2, topicId: 4, status: 0,
          topicName: '主题 #4', clubName: '中文俱乐部', message: '申请只表意向,条款随商家回的邀约走');
        expect(coopApplyTitle(context, missing), 'Theme #4');
        expect(coopApplyTitle(context, supplied), '主题 #4');
        expect(coopApplyPeer(context, supplied, received: true), 'From 中文俱乐部');
        expect(coopApplyTerms(context, supplied), 'Message: 申请只表意向,条款随商家回的邀约走');
        expect(coopApplyTerms(context, missing), 'The application expresses interest only. Terms are set in the invitation returned by the business.');
        expect(coopInviteBlocker(context, const CoopInviteForm()), 'Select a theme for the collaboration first');
        expect(coopInviteBlocker(context, form), isNull);
        expect(coopTargetName(context, const CoopInviteTarget(toId: 9, name: '该商家'), CoopInviteType.merchant), '该商家');
        expect(coopTargetName(context, const CoopInviteTarget(toId: 9, name: '该商家', isLocalDefaultName: true), CoopInviteType.merchant), 'This business');
        expect(form.toJson(target), before);
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
