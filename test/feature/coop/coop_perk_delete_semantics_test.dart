import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/models/coop_perk_template.dart';
import 'package:chengyin_app/feature/coop/coop_perk_template_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 常备权益的删除动作必须**报得出条目名** —— VoiceOver 只念「删除」不知道
/// 删的是哪一条。旧版这是行内纯图标钮(44pt + 语义名);左滑 rollout 后
/// 钮收进 `CySwipeActionsRow`,判据换两条等价物:
///   ① 收起态也挂 accessibility custom action(组件对齐 iOS 的暴露方式),
///      名字逐字沿用旧钮「删除 {名称}」;
///   ② 展开后动作钮触达区 ≥ 44pt(§9.3 L9 不回归)。
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopPerkTemplatesProvider.overrideWith(
            (ref) async => <CoopPerkTemplate>[
              CoopPerkTemplate.fromJson(<String, dynamic>{
                'id': 1,
                'perkType': 0,
                'name': '手冲咖啡一杯',
                'retailValue': 28.0,
                'quota': 20,
              }),
            ],
          ),
        ].cast(),
        child: MaterialApp(
          theme: AppTheme.merchantLight(),
          home: const CoopPerkTemplatePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('收起态:删除动作挂成 custom action,名字带条目名', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpPage(tester);

    final Semantics row = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const Key('coop-perk-row-1')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    final Map<CustomSemanticsAction, VoidCallback> acts =
        row.properties.customSemanticsActions ??
        const <CustomSemanticsAction, VoidCallback>{};
    expect(
      acts.keys.map((CustomSemanticsAction a) => a.label),
      contains('删除 手冲咖啡一杯'),
    );
    handle.dispose();
  });

  testWidgets('左滑展开后动作钮触达区 ≥ 44pt', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.drag(find.text('手冲咖啡一杯'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    final Size size = tester.getSize(
      find.byKey(const Key('swipe-action-coop-perk-delete-1')),
    );
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
