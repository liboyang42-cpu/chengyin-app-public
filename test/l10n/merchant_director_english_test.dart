import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_pending_store.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Gateway implements GameSessionGateway {
  final commands = <GameSessionCommand>[];
  int reads = 0;
  Object? error;
  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async => [];
  @override
  Future<MerchantGameProjection> loadMerchantView({required int activityId}) async {
    reads++;
    if (error != null) throw error!;
    return MerchantGameProjection(
      sessionId: 2, activityId: 7, status: 'PREPARING', revision: reads,
      availableActions: commands.isEmpty ? {'STATION_DECLINE'} : {},
      stations: [MerchantGameStation(
        stationId: 8, nodeId: 9, nodeName: '原始站点', stationCode: 'A1',
        status: commands.isEmpty ? 'INVITED' : 'CLOSED', revision: reads,
        checklist: [], pendingVerificationCount: 0,
        playerTaskPrompt: '原始玩家任务', merchantInstruction: '原始接待说明',
      )],
    );
  }
  @override
  Future<GameSessionReceipt> submitAndReadReceipt(GameSessionCommand command) async {
    commands.add(command);
    return GameSessionReceipt(activityId: command.activityId, requestId: command.requestId,
      action: command.action, outcome: GameReceiptOutcome.applied, receiptId: '原始回执', revision: 2);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _host(Widget child) => CupertinoApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
Widget _page(_Gateway api, {int activityId = 7}) => ProviderScope(child: _host(
  MerchantGameNodePage(activityId: activityId, ownerMemberId: 41, gateway: api,
    pendingStore: MerchantGamePendingStore.memory()),
));
void main() {
  testWidgets('English decline action keeps original request payload and rereads server state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Gateway();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('Invitation pending'), findsOneWidget);
    expect(find.text('原始玩家任务'), findsOneWidget);
    expect(find.text('原始接待说明'), findsOneWidget);
    await tester.tap(find.text('Decline invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule conflict'));
    await tester.pumpAndSettle();
    expect(api.commands.single.action, 'STATION_DECLINE');
    expect(api.commands.single.payload, {'reasonCode': 'SCHEDULE_CONFLICT', 'reason': '档期冲突'});
    expect(api.reads, 2);
    expect(find.text('Ended'), findsOneWidget);
    expect(find.text('revision 2 · Confirmed'), findsOneWidget);
  });

  testWidgets('only local contract errors translate; identical server text remains unchanged', (tester) async {
    await tester.pumpWidget(_page(_Gateway(), activityId: 0));
    await tester.pumpAndSettle();
    expect(find.text('Invalid activity parameters'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final api = _Gateway()..error = const GameSessionContractException('活动参数无效');
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('活动参数无效'), findsOneWidget);
    expect(find.text('Invalid activity parameters'), findsNothing);
  });

  testWidgets('English workbench still excludes ended projects', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        merchantJoinedProjectsProvider.overrideWith((ref) async => []),
        merchantHostedProjectsProvider.overrideWith((ref) async => const [
          MyProject(id: 1, bizType: 'activity', title: '已结束项目原名', startTime: '2000-01-01', endTime: '2000-01-02'),
          MyProject(id: 2, bizType: 'activity', title: '未来项目原名', startTime: '2999-01-01', endTime: '2999-01-02'),
        ]),
        gameSessionApiProvider.overrideWithValue(_Gateway()),
      ],
      child: _host(const CupertinoPageScaffold(child: SingleChildScrollView(child: MerchantGameEntriesSection()))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('已结束项目原名'), findsNothing);
    expect(find.text('未来项目原名'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
  });
}
