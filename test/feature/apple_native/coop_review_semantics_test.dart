import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 评价 sheet 的语义与这两个列表无关,给空数据即可;
/// 但不 stub 的话 `CoopListPage` 里新接的两路带队申请会走真 HTTP,
/// 一直停在加载态 → `pumpAndSettle` 超时。
class _EmptyCoopApi implements CoopApi {
  const _EmptyCoopApi();

  @override
  Future<Map<String, dynamic>> inviteList() async => <String, dynamic>{
    'received': <dynamic>[],
    'sent': <dynamic>[],
  };

  @override
  Future<List<Map<String, dynamic>>> poolReceived() async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> poolMine() async =>
      const <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('合作评价星级可独立读取并播报选中值', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopApiProvider.overrideWithValue(const _EmptyCoopApi()),
          coopInviteListProvider.overrideWith(
            (ref) async => const CoopInviteList(
              received: <CoopInviteRow>[
                CoopInviteRow(
                  id: 1,
                  inviteType: 0,
                  fromId: 5,
                  toType: 'merchant',
                  toId: 9,
                  topicId: 12,
                  status: 1,
                  partnerName: '合作方',
                ),
              ],
            ),
          ),
          // 「收到的」这一档并了官方邀约那一路(本分支把 merchantInvites 接进
          // CoopListPage),不 stub 会发真的商家请求,停在加载态 → 永不 settle。
          merchantInvitesProvider.overrideWith(
            (ref) async => const <MerchantInvite>[],
          ),
        ].cast(),
        child: const MaterialApp(home: CoopListPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('评价'));
    await tester.pumpAndSettle();

    for (int star = 1; star <= 5; star += 1) {
      final node = tester.getSemantics(find.bySemanticsLabel('$star 星'));
      expect(node.rect.size.width, greaterThanOrEqualTo(44));
      expect(node.rect.size.height, greaterThanOrEqualTo(44));
      expect(node.value, star == 5 ? '已选择' : '未选择');
    }

    final threeStars = tester.getSemantics(find.bySemanticsLabel('3 星'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: threeStars.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(tester.getSemantics(find.bySemanticsLabel('3 星')).value, '已选择');
    handle.dispose();
  });
}
