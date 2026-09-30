import 'package:chengyin_app/data/api/merchant_customer_detail_api.dart';
import 'package:chengyin_app/data/models/merchant_customer_detail.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('无 CRM 读权限时显示岗位权限态，且不请求详情', (WidgetTester tester) async {
    final _FakeGateway api = _FakeGateway(
      accessValue: MerchantCustomerAccess.inactive,
      detailValue: _detail(),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前岗位没有客户查看权限'), findsOneWidget);
    expect(find.text('请联系店主调整经营团队权限'), findsOneWidget);
    expect(api.detailCalls, 0);
  });

  testWidgets('只读岗位显示客户事实与分组标签，不显示写入入口', (WidgetTester tester) async {
    final _FakeGateway api = _FakeGateway(
      accessValue: const MerchantCustomerAccess(
        active: true,
        merchantId: 7,
        roleCode: 'MERCHANT_CHECKIN',
        permissions: <String>{MerchantCustomerAccess.crmRead},
      ),
      detailValue: _detailWithContent(),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('林青'), findsOneWidget);
    expect(find.text('无查看权限'), findsOneWidget);
    expect(find.text('到店'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('系统标签 · 自动更新'), findsOneWidget);
    expect(find.text('已到店'), findsOneWidget);
    expect(find.text('店内标签 · 团队可见'), findsOneWidget);
    expect(find.text('高频复购'), findsOneWidget);
    expect(find.text('互动时间线'), findsOneWidget);
    expect(find.text('记得无糖'), findsOneWidget);
    expect(find.text('添加'), findsNothing);
    expect(find.text('保存跟进'), findsNothing);
    expect(
      find.byKey(const Key('merchant-customer-remove-tag-3')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('merchant-customer-correct-note-8')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('merchant-customer-hide-note-8')),
      findsNothing,
    );
  });

  testWidgets('可编辑岗位用 Cupertino 输入与 Apple 按钮保存标签、跟进', (
    WidgetTester tester,
  ) async {
    final _FakeGateway api = _FakeGateway(
      accessValue: const MerchantCustomerAccess(
        active: true,
        merchantId: 7,
        roleCode: 'MERCHANT_OWNER',
        permissions: <String>{
          MerchantCustomerAccess.crmRead,
          MerchantCustomerAccess.crmSegment,
        },
      ),
      detailValue: _detailWithContent(),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();

    final Finder tagInput = find.byKey(
      const Key('merchant-customer-tag-input'),
    );
    await tester.ensureVisible(tagInput);
    await tester.enterText(tagInput, '  常来  ');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(api.assignedTagNames, <String>['  常来  ']);
    expect(api.assignedTagColors, <String>['#2E6D5A']);
    expect(api.assignedTagRequestIds.single, startsWith('crm-tag-'));

    final Finder noteInput = find.byKey(
      const Key('merchant-customer-note-input'),
    );
    await tester.ensureVisible(noteInput);
    await tester.enterText(noteInput, '  下周提醒报名  ');
    await tester.tap(find.text('保存跟进'));
    await tester.pumpAndSettle();

    expect(api.addedNoteContents, <String>['  下周提醒报名  ']);
    expect(api.addedNoteRequestIds.single, startsWith('crm-note-'));
    expect(api.addedNoteCorrections.single, isNull);
    expect(api.detailCalls, 3);
  });

  testWidgets('追加更正传原备注 ID，用新记录而不改原文', (WidgetTester tester) async {
    final _FakeGateway api = _editableGateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('merchant-customer-detail-scroll')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    final Finder correction = find.byKey(
      const Key('merchant-customer-correct-note-8'),
    );
    await tester.ensureVisible(correction);
    await tester.tap(correction);
    await tester.pump();

    expect(find.text('追加更正'), findsWidgets);
    expect(find.textContaining('正在更正备注 #8'), findsOneWidget);
    final Finder input = find.byKey(const Key('merchant-customer-note-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '原备注应为无冰');
    await tester.tap(find.text('保存跟进'));
    await tester.pumpAndSettle();

    expect(api.addedNoteCorrections, <int?>[8]);
    expect(api.addedNoteContents, <String>['原备注应为无冰']);
    expect(api.addedNoteRequestIds.single, startsWith('crm-note-'));
  });

  testWidgets('隐藏备注先显示 Apple 确认弹窗，确认后提交 CAS 版本', (WidgetTester tester) async {
    final _FakeGateway api = _editableGateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('merchant-customer-detail-scroll')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    final Finder hide = find.byKey(const Key('merchant-customer-hide-note-8'));
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(find.text('隐藏跟进记录'), findsOneWidget);
    expect(find.textContaining('原文会保留在审计记录中'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '隐藏'));
    await tester.pumpAndSettle();

    expect(api.hiddenNoteIds, <int>[8]);
    expect(api.hiddenNoteVersions, <int>[0]);
    expect(api.hiddenNoteRequestIds.single, startsWith('crm-note-'));
    expect(api.detailCalls, 2);
  });

  testWidgets('移除店内标签先确认，只提交当前客户与标签关系', (WidgetTester tester) async {
    final _FakeGateway api = _editableGateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();

    final Finder remove = find.byKey(
      const Key('merchant-customer-remove-tag-3'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(find.text('移除标签'), findsOneWidget);
    expect(find.text('只会移除当前客户与该标签的关系。'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '移除'));
    await tester.pumpAndSettle();

    expect(api.removedTagIds, <int>[3]);
    expect(api.removedTagRequestIds.single, startsWith('crm-tag-'));
    expect(api.detailCalls, 2);
  });

  testWidgets('更正回执丢失后原地报错，重试复用同一幂等标识', (WidgetTester tester) async {
    final _FakeGateway api = _editableGateway()..noteFailuresRemaining = 1;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantCustomerDetailPage(api: api, customerMemberId: 41),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('merchant-customer-detail-scroll')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-customer-correct-note-8')));
    await tester.pump();
    final Finder input = find.byKey(const Key('merchant-customer-note-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '原备注应为无冰');

    await tester.tap(find.text('保存跟进'));
    await tester.pumpAndSettle();
    expect(find.text('网络连接失败，请稍后重试'), findsOneWidget);

    await tester.tap(find.text('保存跟进'));
    await tester.pumpAndSettle();
    expect(api.addedNoteRequestIds, hasLength(2));
    expect(api.addedNoteRequestIds.toSet(), hasLength(1));
    expect(api.addedNoteCorrections, <int?>[8, 8]);
  });
}

_FakeGateway _editableGateway() => _FakeGateway(
  accessValue: const MerchantCustomerAccess(
    active: true,
    merchantId: 7,
    roleCode: 'MERCHANT_OWNER',
    permissions: <String>{
      MerchantCustomerAccess.crmRead,
      MerchantCustomerAccess.crmSegment,
    },
  ),
  detailValue: _detailWithContent(),
);

MerchantCustomerDetail _detail() =>
    MerchantCustomerDetail.fromJson(<String, dynamic>{
      'summary': <String, dynamic>{
        'customerMemberId': 41,
        'displayName': '林青',
        'arrivedCount': 2,
        'pendingCount': 1,
        'refundedCount': 0,
        'paidAmount': null,
      },
      'systemTags': <dynamic>[],
      'merchantTags': <dynamic>[],
      'timeline': <dynamic>[],
    }, expectedCustomerMemberId: 41);

MerchantCustomerDetail _detailWithContent() =>
    MerchantCustomerDetail.fromJson(<String, dynamic>{
      'summary': <String, dynamic>{
        'customerMemberId': 41,
        'displayName': '林青',
        'arrivedCount': 2,
        'pendingCount': 1,
        'refundedCount': 0,
        'paidAmount': null,
      },
      'systemTags': <dynamic>[
        <String, dynamic>{'code': 'ARRIVED', 'label': '已到店'},
      ],
      'merchantTags': <dynamic>[
        <String, dynamic>{'id': 3, 'tagName': '高频复购', 'tagColor': '#2E6D5A'},
      ],
      'timeline': <dynamic>[
        <String, dynamic>{
          'key': 'note-8',
          'type': 'NOTE',
          'title': '团队跟进',
          'description': '记得无糖',
          'noteId': 8,
          'noteVersion': 0,
        },
      ],
    }, expectedCustomerMemberId: 41);

class _FakeGateway implements MerchantCustomerDetailGateway {
  _FakeGateway({required this.accessValue, required this.detailValue});

  final MerchantCustomerAccess accessValue;
  final MerchantCustomerDetail detailValue;
  int detailCalls = 0;
  int noteFailuresRemaining = 0;
  final List<String> addedNoteContents = <String>[];
  final List<String> addedNoteRequestIds = <String>[];
  final List<int?> addedNoteCorrections = <int?>[];
  final List<String> assignedTagNames = <String>[];
  final List<String> assignedTagColors = <String>[];
  final List<String> assignedTagRequestIds = <String>[];
  final List<int> hiddenNoteIds = <int>[];
  final List<int> hiddenNoteVersions = <int>[];
  final List<String> hiddenNoteRequestIds = <String>[];
  final List<int> removedTagIds = <int>[];
  final List<String> removedTagRequestIds = <String>[];

  @override
  Future<MerchantCustomerAccess> access() async => accessValue;

  @override
  Future<MerchantCustomerDetail> detail(int customerMemberId) async {
    detailCalls += 1;
    return detailValue;
  }

  @override
  Future<MerchantCustomerMutationReceipt> addNote({
    required int customerMemberId,
    required String content,
    required String requestId,
    int? correctsNoteId,
  }) async {
    addedNoteContents.add(content);
    addedNoteRequestIds.add(requestId);
    addedNoteCorrections.add(correctsNoteId);
    if (noteFailuresRemaining > 0) {
      noteFailuresRemaining -= 1;
      throw const MerchantCustomerDetailApiException('网络连接失败，请稍后重试');
    }
    return const MerchantCustomerMutationReceipt(
      message: '跟进备注已保存',
      data: <String, dynamic>{'id': 9},
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> assignTag({
    required int customerMemberId,
    required String tagName,
    required String tagColor,
    required String requestId,
  }) async {
    assignedTagNames.add(tagName);
    assignedTagColors.add(tagColor);
    assignedTagRequestIds.add(requestId);
    return const MerchantCustomerMutationReceipt(
      message: '客户标签已保存',
      data: <String, dynamic>{'id': 4},
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> hideNote({
    required int customerMemberId,
    required int noteId,
    required int expectedVersion,
    required String requestId,
  }) async {
    hiddenNoteIds.add(noteId);
    hiddenNoteVersions.add(expectedVersion);
    hiddenNoteRequestIds.add(requestId);
    return const MerchantCustomerMutationReceipt(
      message: '备注已隐藏',
      data: '备注已隐藏',
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> removeTag({
    required int customerMemberId,
    required int tagId,
    required String requestId,
  }) async {
    removedTagIds.add(tagId);
    removedTagRequestIds.add(requestId);
    return const MerchantCustomerMutationReceipt(
      message: '标签已移除',
      data: '标签已移除',
    );
  }
}
