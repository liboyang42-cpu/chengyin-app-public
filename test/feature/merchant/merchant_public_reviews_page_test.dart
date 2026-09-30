import 'package:chengyin_app/core/widgets/cy_image_source_sheet.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/widgets/cy_native_notice.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/data/models/merchant_review.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_reviews_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _signedReviewImage =
    'https://chengyin-review.oss-cn-hangzhou.aliyuncs.com/upload/'
    '0123456789abcdef0123456789abcdef.jpg?'
    'OSSAccessKeyId=test&Expires=2000000000&Signature=test';

void main() {
  testWidgets('公开页先显示真实核销资格、发布器和公开评价', (WidgetTester tester) async {
    final _PublicGateway api = _PublicGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: api,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          confirmImagePurpose: (_) async => true,
          uploadImage: (String path) async => _signedReviewImage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实到店评价'), findsOneWidget);
    expect(find.text('真实到店体验'), findsOneWidget);
    expect(find.text('写下这次体验'), findsOneWidget);
    expect(find.text('核销已验证 · 提交后平台复核，过审后公开；原评不可编辑'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('public-review-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-review-101')), findsOneWidget);
    expect(api.publicRequests.single, (merchantRowId: 31, pageNum: 1));
  });

  testWidgets('图片走原生来源选择，发布失败原地重试复用 requestId', (WidgetTester tester) async {
    final _PublicGateway api = _PublicGateway()..failFirstCreate = true;
    final List<CyImagePickSource> pickedSources = <CyImagePickSource>[];
    final List<String> uploadedPaths = <String>[];
    int purposeConfirmations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: api,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          requestIdFactory: (_) => 'mr-create-fixed',
          confirmImagePurpose: (_) async {
            purposeConfirmations += 1;
            return true;
          },
          chooseImageSource: (_) async => CyImagePickSource.gallery,
          pickImages: (CyImagePickSource source, int limit) async {
            pickedSources.add(source);
            return <String>['/tmp/review.jpg'];
          },
          uploadImage: (String path) async {
            uploadedPaths.add(path);
            return _signedReviewImage;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('public-review-star-5')));
    await tester.enterText(
      find.byKey(const Key('public-review-content')),
      '真实到店体验很好',
    );
    await tester.tap(find.byKey(const Key('public-review-add-image')));
    await tester.pumpAndSettle();
    expect(pickedSources, <CyImagePickSource>[CyImagePickSource.gallery]);
    expect(purposeConfirmations, 1);
    expect(uploadedPaths, <String>['/tmp/review.jpg']);
    expect(find.byKey(const Key('public-review-uploaded-0')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('public-review-submit')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CyNativeButton>(find.byKey(const Key('public-review-submit')))
          .onPressed,
      isNotNull,
    );
    final Finder submit = find.descendant(
      of: find.byKey(const Key('public-review-submit')),
      matching: find.byType(CupertinoButton),
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.createRequestIds, <String>['mr-create-fixed']);
    expect(find.text('网络中断'), findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(api.createRequestIds, <String>[
      'mr-create-fixed',
      'mr-create-fixed',
    ]);
    expect(api.createDrafts.last.registrationId, 902);
    expect(api.createDrafts.last.rating, 5);
    expect(api.createDrafts.last.imageUrls, <String>[_signedReviewImage]);
    expect(find.text('评价已提交，等待平台复核'), findsOneWidget);
  });

  testWidgets('无资格不伪装发布器，普通举报失败可安全重试', (WidgetTester tester) async {
    final _PublicGateway noEligibility = _PublicGateway()
      ..eligibility = const MerchantReviewEligibility(
        canCreate: false,
        reasonCode: 'LOGIN_REQUIRED',
        registrationId: null,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: noEligibility,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          requestIdFactory: (_) => 'mr-report-fixed',
          confirmImagePurpose: (_) async => true,
          uploadImage: (String path) async => '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看评价资格'), findsOneWidget);
    expect(find.byKey(const Key('public-review-content')), findsNothing);

    noEligibility.failFirstReport = true;
    await tester.tap(find.byKey(const Key('public-review-report-101')));
    await tester.pumpAndSettle();
    expect(find.text('提交平台复核'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('举报只会进入统一审核队列，不代表内容已经下架。'), findsOneWidget);
    expect(find.text('请说明不实、攻击、广告或其他违规事实'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('public-review-report-input')),
      '评价含有与到店体验无关的广告',
    );
    await tester.tap(find.byKey(const Key('public-review-report-submit')));
    await tester.pumpAndSettle();
    expect(find.text('网络中断'), findsOneWidget);
    await tester.tap(find.byKey(const Key('public-review-report-submit')));
    await tester.pumpAndSettle();

    expect(noEligibility.reportOwnerIds, <int>[41, 41]);
    expect(noEligibility.reportRequestIds, <String>[
      'mr-report-fixed',
      'mr-report-fixed',
    ]);
    expect(find.byKey(const Key('public-review-report-input')), findsNothing);
  });

  testWidgets('公开评价图片使用 Apple 弹层完整预览', (WidgetTester tester) async {
    final _PublicGateway api = _PublicGateway()..withImages = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: api,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          confirmImagePurpose: (_) async => true,
          uploadImage: (String path) async => '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('public-review-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('public-review-image-101-0')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('public-review-image-preview')),
      findsOneWidget,
    );
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.byKey(const Key('public-review-image-close')), findsOneWidget);
  });

  testWidgets('公开空列表保持 ready 结构，不插入管理空态', (WidgetTester tester) async {
    final _PublicGateway api = _PublicGateway()..empty = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: api,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          confirmImagePurpose: (_) async => true,
          uploadImage: (String path) async => _signedReviewImage,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('public-review-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('public-review-list')), findsOneWidget);
    expect(find.text('暂无真实到店评价'), findsNothing);
    expect(find.text('重新加载'), findsNothing);
    expect(api.publicRequests.length, 1);
  });

  testWidgets('照片权限失败给出系统设置恢复路径', (WidgetTester tester) async {
    bool openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: _PublicGateway(),
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          confirmImagePurpose: (_) async => true,
          chooseImageSource: (_) async => CyImagePickSource.gallery,
          pickImages: (_, _) async =>
              throw PlatformException(code: 'photo-denied'),
          openImageSettings: () async {
            openedSettings = true;
            return true;
          },
          uploadImage: (String path) async => _signedReviewImage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('public-review-add-image')));
    await tester.pump();
    expect(find.text('需要照片权限，请到系统设置开启后重试'), findsOneWidget);
    await tester.tap(find.text('去设置'));
    await tester.pump();
    expect(openedSettings, isTrue);
    CyNativeNotice.hide();
  });

  testWidgets('评价图片保持三列九宫格，并显示商家回复时间', (WidgetTester tester) async {
    final _PublicGateway api = _PublicGateway()
      ..withImages = true
      ..withMerchantReply = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MerchantPublicReviewsPage(
          api: api,
          merchantRowId: 31,
          merchantOwnerMemberId: 41,
          liquidGlassSupported: false,
          confirmImagePurpose: (_) async => true,
          uploadImage: (String path) async => _signedReviewImage,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('public-review-list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    final Offset first = tester.getTopLeft(
      find.byKey(const Key('public-review-image-101-0')),
    );
    final Offset second = tester.getTopLeft(
      find.byKey(const Key('public-review-image-101-1')),
    );
    final Offset fourth = tester.getTopLeft(
      find.byKey(const Key('public-review-image-101-3')),
    );
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(fourth.dy, greaterThan(first.dy));
    expect(fourth.dx, first.dx);
    expect(find.text('2026-08-27 13:00'), findsOneWidget);
  });

  testWidgets('★ 坏深链(缺参/0/非数字)落「链接参数无效」态，不抛构造期 assert', (
    WidgetTester tester,
  ) async {
    // b1-sim-merchant-4 P2:路由兜出的 0 曾撞构造期 assert → Debug 整屏
    // 英文断言、无出口。同 public-home 口径:无效主体 ID 是一个界面态。
    final List<({int? row, int? owner, String label})> badLinks =
        <({int? row, int? owner, String label})>[
          (row: null, owner: 41, label: '缺 merchantRowId'),
          (row: 0, owner: 41, label: 'merchantRowId=0'),
          (row: int.tryParse('abc'), owner: 41, label: 'merchantRowId 非数字'),
          (row: 31, owner: null, label: '缺 ownerMemberId'),
          (row: 31, owner: 0, label: 'ownerMemberId=0'),
        ];
    for (final ({int? row, int? owner, String label}) bad in badLinks) {
      final _PublicGateway api = _PublicGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: MerchantPublicReviewsPage(
            api: api,
            merchantRowId: bad.row,
            merchantOwnerMemberId: bad.owner,
            liquidGlassSupported: false,
            uploadImage: (String path) async => '',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('链接参数无效'), findsOneWidget, reason: bad.label);
      expect(
        find.text('这个链接缺少商家或店主信息，无法打开这份口碑页。'),
        findsOneWidget,
        reason: bad.label,
      );
      // 链接的问题不给「点了永远不会好」的重试。
      expect(find.text('重新加载'), findsNothing, reason: bad.label);
      // 不拿猜出来的 id 去打接口。
      expect(api.publicRequests, isEmpty, reason: bad.label);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

class _PublicGateway implements MerchantPublicReviewGateway {
  MerchantReviewEligibility eligibility = const MerchantReviewEligibility(
    canCreate: true,
    reasonCode: 'ELIGIBLE',
    registrationId: 902,
  );
  bool failFirstCreate = false;
  bool failFirstReport = false;
  bool withImages = false;
  bool withMerchantReply = false;
  bool empty = false;
  final List<({int merchantRowId, int pageNum})> publicRequests =
      <({int merchantRowId, int pageNum})>[];
  final List<String> createRequestIds = <String>[];
  final List<MerchantReviewCreateDraft> createDrafts =
      <MerchantReviewCreateDraft>[];
  final List<int> reportOwnerIds = <int>[];
  final List<String> reportRequestIds = <String>[];

  @override
  Future<MerchantReviewPage> publicPage({
    required int merchantRowId,
    required int pageNum,
    required int pageSize,
  }) async {
    publicRequests.add((merchantRowId: merchantRowId, pageNum: pageNum));
    return MerchantReviewPage(
      mode: MerchantReviewMode.public,
      pageNum: pageNum,
      pageSize: pageSize,
      total: empty ? 0 : 1,
      hasMore: false,
      averageRating: 4.8,
      eligibility: eligibility,
      items: empty
          ? const <MerchantReviewItem>[]
          : <MerchantReviewItem>[
              MerchantReviewItem(
                id: 101,
                rating: 5,
                content: '环境很好，服务也很耐心。',
                imageUrls: withImages
                    ? <Uri>[
                        Uri.parse('https://cdn.example/review-1.jpg'),
                        Uri.parse('https://cdn.example/review-2.jpg'),
                        Uri.parse('https://cdn.example/review-3.jpg'),
                        Uri.parse('https://cdn.example/review-4.jpg'),
                      ]
                    : const <Uri>[],
                authorNickname: '城瘾玩家',
                authorAvatar: null,
                verifiedRedemption: true,
                status: MerchantReviewStatus.visible,
                merchantReply: withMerchantReply ? '谢谢认可，欢迎再来。' : null,
                repliedAt: withMerchantReply ? DateTime(2026, 8, 27, 13) : null,
                createTime: DateTime(2026, 8, 27, 12, 30),
                version: 2,
                canReply: false,
                canReport: true,
              ),
            ],
    );
  }

  @override
  Future<MerchantReviewReceipt> create({
    required MerchantReviewCreateDraft draft,
    required String requestId,
  }) async {
    createRequestIds.add(requestId);
    createDrafts.add(draft);
    if (failFirstCreate && createRequestIds.length == 1) {
      throw const MerchantReviewApiException('网络中断');
    }
    return const MerchantReviewReceipt(
      reviewId: 201,
      status: 'PENDING_REVIEW',
      version: 0,
      replayed: false,
      auditTaskId: 901,
    );
  }

  @override
  Future<MerchantReviewReceipt> reportPublic({
    required int merchantOwnerMemberId,
    required MerchantReviewReportDraft draft,
    required String requestId,
  }) async {
    reportOwnerIds.add(merchantOwnerMemberId);
    reportRequestIds.add(requestId);
    if (failFirstReport && reportRequestIds.length == 1) {
      throw const MerchantReviewApiException('网络中断');
    }
    return MerchantReviewReceipt(
      reviewId: draft.reviewId,
      status: 'PENDING_PLATFORM_REVIEW',
      version: null,
      replayed: false,
      auditTaskId: 902,
    );
  }
}
