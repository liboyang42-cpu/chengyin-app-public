import 'package:chengyin_app/data/api/merchant_aftercare_api.dart';
import 'package:chengyin_app/data/models/merchant_aftercare.dart';
import 'package:chengyin_app/feature/merchant/merchant_aftercare_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('详情并列显示平台处理、商家意见、款项结果与允许决策', (WidgetTester tester) async {
    final _DetailGateway api = _DetailGateway();
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: MerchantAftercareDetailPage(api: api, refundId: 81)),
    );
    await tester.pumpAndSettle();

    expect(find.text('平台处理'), findsOneWidget);
    expect(find.text('平台审核中'), findsOneWidget);
    expect(find.text('商家意见'), findsOneWidget);
    expect(find.text('等待商家意见'), findsOneWidget);
    expect(find.text('款项结果'), findsOneWidget);
    expect(find.text('尚未确认退回'), findsOneWidget);
    expect(find.byKey(const Key('aftercare-decision-AGREE')), findsOneWidget);
    expect(find.byKey(const Key('aftercare-decision-REJECT')), findsOneWidget);
    expect(
      find.byKey(const Key('aftercare-decision-EVIDENCE')),
      findsOneWidget,
    );
    expect(find.text('售后凭证'), findsOneWidget);
  });

  testWidgets('拒绝原因提交失败重试复用同一 requestId', (WidgetTester tester) async {
    final _DetailGateway api = _DetailGateway()..failFirstRespond = true;
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantAftercareDetailPage(
          api: api,
          refundId: 81,
          requestIdFactory: () => 'ma:fixed:1:test',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aftercare-decision-REJECT')));
    await tester.enterText(
      find.byKey(const Key('aftercare-content')),
      '未参加活动不属实',
    );
    await tester.tap(find.byKey(const Key('aftercare-submit')));
    await tester.pumpAndSettle();

    expect(find.text('网络连接失败，请重试'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aftercare-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.requestIds, <String>['ma:fixed:1:test', 'ma:fixed:1:test']);
    expect(api.respondedDecisions, <MerchantAftercareDecision>[
      MerchantAftercareDecision.reject,
      MerchantAftercareDecision.reject,
    ]);
  });

  testWidgets('补充凭证只提交上传后的 object key', (WidgetTester tester) async {
    final _DetailGateway api = _DetailGateway();
    const String objectKey =
        'upload/merchant-aftercare-evidence/'
        '0123456789abcdef0123456789abcdef.jpg';
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantAftercareDetailPage(
          api: api,
          refundId: 81,
          requestIdFactory: () => 'ma:evidence:1:test',
          confirmEvidencePurpose: (_) async => true,
          evidencePicker: (_, _) async => const MerchantAftercareEvidence(
            objectKey: objectKey,
            localPath: '/tmp/missing-aftercare-proof.jpg',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aftercare-decision-EVIDENCE')));
    await tester.tap(find.text('选择图片并上传'));
    await tester.pumpAndSettle();
    expect(find.text('凭证已上传'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aftercare-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.respondedEvidenceKeys, <String?>[objectKey]);
  });

  testWidgets('首次上传凭证先说明相机与照片用途，取消不请求系统权限', (WidgetTester tester) async {
    final _DetailGateway api = _DetailGateway();
    var pickerCalls = 0;
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantAftercareDetailPage(
          api: api,
          refundId: 81,
          evidencePicker: (_, _) async {
            pickerCalls += 1;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aftercare-decision-EVIDENCE')));
    await tester.tap(find.text('选择图片并上传'));
    await tester.pumpAndSettle();

    expect(find.text('添加售后凭证'), findsOneWidget);
    expect(find.textContaining('仅在你主动选择后访问相机或照片'), findsOneWidget);
    await tester.tap(find.text('暂不添加'));
    await tester.pumpAndSettle();

    expect(pickerCalls, 0);
  });

  testWidgets('凭证取图权限被拒后用原生 Alert 提供系统设置恢复路径', (WidgetTester tester) async {
    final _DetailGateway api = _DetailGateway();
    var settingsCalls = 0;
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantAftercareDetailPage(
          api: api,
          refundId: 81,
          confirmEvidencePurpose: (_) async => true,
          evidencePicker: (_, _) async =>
              throw PlatformException(code: 'photo_access_denied'),
          openSystemSettings: () async {
            settingsCalls += 1;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aftercare-decision-EVIDENCE')));
    await tester.tap(find.text('选择图片并上传'));
    await tester.pumpAndSettle();

    expect(find.text('无法访问相机或照片'), findsOneWidget);
    expect(find.textContaining('设置'), findsWidgets);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();

    expect(settingsCalls, 1);
  });
}

class _DetailGateway implements MerchantAftercareGateway {
  MerchantAftercareDetail detailValue = _detail();
  bool failFirstRespond = false;
  final List<String> requestIds = <String>[];
  final List<MerchantAftercareDecision> respondedDecisions =
      <MerchantAftercareDecision>[];
  final List<String?> respondedEvidenceKeys = <String?>[];

  @override
  Future<MerchantAftercareDetail> detail({required int refundId}) async =>
      detailValue;

  @override
  Future<MerchantAftercarePage> listPage({
    required MerchantAftercareBucket bucket,
    required int pageNum,
    required int pageSize,
  }) => throw UnimplementedError();

  @override
  Future<MerchantAftercareReceipt> respond({
    required int refundId,
    required MerchantAftercareResponseDraft draft,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    respondedDecisions.add(draft.decision);
    respondedEvidenceKeys.add(draft.evidenceKey);
    if (failFirstRespond && requestIds.length == 1) {
      throw const MerchantAftercareApiException('网络连接失败，请重试');
    }
    return MerchantAftercareReceipt(
      id: 11,
      refundId: refundId,
      decision: draft.decision,
      processing: MerchantAftercareProcessing.waitingPlatformReview,
      merchantOpinion: draft.decision == MerchantAftercareDecision.reject
          ? MerchantAftercareOpinion.reject
          : MerchantAftercareOpinion.agree,
      refunded: false,
    );
  }

  @override
  Future<MerchantAftercareEvidence> uploadEvidence(String filePath) =>
      throw UnimplementedError();
}

MerchantAftercareDetail _detail() => MerchantAftercareDetail(
  refundId: 81,
  refundNo: 'RF-81',
  sourceType: 'registration',
  sourceId: 9,
  refundAmount: 88,
  reason: '行程取消',
  processing: MerchantAftercareProcessing.waitingPlatformReview,
  merchantOpinion: MerchantAftercareOpinion.pending,
  canRespond: true,
  allowedDecisions: MerchantAftercareDecision.values,
  createTime: DateTime(2026, 8, 27, 12, 30),
  refundPolicyCode: 'EXPLORE_END_100_0',
  refundPolicyVersion: 2,
  refundDeadline: DateTime(2026, 8, 30, 18),
  responses: <MerchantAftercareResponse>[
    MerchantAftercareResponse(
      id: 7,
      refundId: 81,
      decision: MerchantAftercareDecision.evidence,
      content: '现场签到记录',
      evidenceUrl: Uri.parse('https://signed.example/evidence.jpg'),
      actorRoleCode: 'MERCHANT_MANAGER',
      createTime: DateTime(2026, 8, 27, 12, 35),
    ),
  ],
);
