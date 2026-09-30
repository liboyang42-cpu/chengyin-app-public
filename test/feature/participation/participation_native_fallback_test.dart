import 'package:chengyin_app/feature/participation/participation_detail_sheet.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

const ParticipationDetail _detail = ParticipationDetail(
  id: 77,
  topicName: '夜游苏河',
  dateText: '2026.09.10 - 2026.09.12',
  statusText: '未开始',
  modeText: '城市定向',
  ownerType: 1,
  ownerId: 11,
  isTopic: true,
  paymentStatus: 2,
  showOrderStats: true,
  showRemainingBadge: false,
  remainingDaysText: '',
  canCancel: true,
  showContactService: false,
  needModify: false,
  hasRuleInstructions: false,
  activityDescription: '沿河完成城市探索',
  nodeName: '苏河湾站',
  cooperateDate: '每日 10:00-22:00',
  templateId: 9,
  templateName: '经典定向模板',
  pendingVerification: 3,
  verifiedCount: 2,
  totalOrderCount: 5,
);

class _FailingDriver implements ParticipationDetailNativeDriver {
  const _FailingDriver(this.error);

  final Object error;

  @override
  Future<bool> show({
    required BuildContext context,
    required AppleLiquidSheetContent content,
  }) => Future<bool>.error(error);
}

void main() {
  for (final Object error in <Object>[
    MissingPluginException('sheet unavailable'),
    PlatformException(code: 'presentation_failed'),
  ]) {
    testWidgets('${error.runtimeType} 进入完整 Cupertino 详情降级', (
      WidgetTester tester,
    ) async {
      Future<ParticipationDetailResult?>? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => FilledButton(
              onPressed: () {
                opened = showParticipationDetail(
                  context,
                  _detail,
                  nativeDriver: _FailingDriver(error),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPopupSurface), findsOneWidget);
      expect(find.text('参与详情'), findsOneWidget);
      expect(find.text('夜游苏河'), findsOneWidget);
      expect(find.text('苏河湾站'), findsOneWidget);
      // 接待时间 = cooperateDate 真值,不再是恒定的假排期行。
      expect(find.text('每日 10:00-22:00'), findsOneWidget);
      expect(find.text('场次时间排期'), findsNothing);
      expect(find.textContaining('营业时间内自由接待'), findsNothing);
      expect(
        find.byKey(const Key('participation-detail-close')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CyNativeIconButton &&
              widget.key == const Key('participation-detail-close'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('关闭参与详情'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('participation-detail-close'))),
        const Size(44, 44),
      );

      // A3:降级路径同样补齐动作按钮。
      expect(
        find.byKey(const Key('participation-action-start-play')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('participation-action-cancel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('participation-action-scan')),
        findsOneWidget,
      );
      expect(find.text('联系客服'), findsNothing);
      // A9:模板行可点。
      expect(
        find.byKey(const Key('participation-action-template')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('participation-action-cancel')));
      await tester.pumpAndSettle();
      expect((await opened)!.kind, ParticipationDetailActionKind.cancel);
      expect((await opened)!.detail.id, 77);
    });
  }
}
