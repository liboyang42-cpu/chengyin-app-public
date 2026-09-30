import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_history_page.dart';
import 'package:chengyin_app/feature/roam/roam_live_controller.dart';
import 'package:chengyin_app/feature/roam/roam_team_markers.dart';
import 'package:chengyin_app/feature/roam/roam_live_page.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('仅漫游 intro 保留玩家五项底栏', () {
    expect(roamPhaseShowsPlayerTabBar(RoamLivePhase.idle), isTrue);
    for (final RoamLivePhase phase in <RoamLivePhase>[
      RoamLivePhase.starting,
      RoamLivePhase.roaming,
      RoamLivePhase.finishing,
      RoamLivePhase.finished,
    ]) {
      expect(
        roamPhaseShowsPlayerTabBar(phase),
        isFalse,
        reason: '$phase 不应让顶级底栏覆盖沉浸式漫游',
      );
    }
  });

  testWidgets('结束漫游按钮避开 iPhone 底部安全区', (WidgetTester tester) async {
    const double screenHeight = 844;
    const double safeBottom = 34;
    const RoamLiveState roamingState = RoamLiveState(
      phase: RoamLivePhase.roaming,
      location: RoamLivePosition(latitude: 31.2304, longitude: 121.4737),
    );
    await tester.binding.setSurfaceSize(const Size(390, screenHeight));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roamLiveControllerProvider.overrideWith(
            () => _PresetRoamLiveController(roamingState),
          ),
          roamNearbyLayerProvider.overrideWith(_StubNearbyLayer.new),
          roamHistoryProvider.overrideWith((_) async => const <RoamSession>[]),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(390, screenHeight),
              padding: EdgeInsets.only(bottom: safeBottom),
              viewPadding: EdgeInsets.only(bottom: safeBottom),
            ),
            child: child!,
          ),
          home: const RoamLivePage(),
        ),
      ),
    );
    await tester.pump();

    final Finder finishButton = find.widgetWithText(CyNativeButton, '结束漫游');
    expect(finishButton, findsOneWidget);
    expect(
      tester.getBottomRight(finishButton).dy,
      lessThanOrEqualTo(screenHeight - safeBottom - 16),
    );
  });
}

class _PresetRoamLiveController extends RoamLiveController {
  _PresetRoamLiveController(this.initialState);

  final RoamLiveState initialState;

  @override
  RoamLiveState build() => initialState;
}

/// 漫游地图上的队伍层会去拉 `/api/team/nearby` —— 这几条用例只看版式,
/// 用空图层顶掉网络(2026-09-18 A3 地图组队 marker 层接入后新增)。
class _StubNearbyLayer extends RoamNearbyLayerController {
  @override
  Future<RoamNearbyLayer> build() async => const RoamNearbyLayer();
}
