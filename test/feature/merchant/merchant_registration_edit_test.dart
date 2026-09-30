// 报名编辑表单。这是本轮**新接通**的写入口(/api/registration/merchant/update),
// 此前 App 侧被显式记为「不许接」。
//
// ★★ 原来的理由是「没有完整表单,接了会拿半截数据覆盖后端」。核到服务端后:
//   · 覆盖成空**不会**发生 —— 白名单只有九个字段,mapper 又是逐字段增量更新;
//   · 真正的实害是**表单缺一项 = 商家永远改不了那一项**。
//   所以这一组盯的是「表单齐不齐」和「该发的都发出去了没有」,
//   而不是「有没有多发」。
//
// ★ 另一半盯「改不了的时候别摆一张能填的表」。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_sheets.dart';
import 'package:chengyin_app/feature/merchant/merchant_registration_edit_page.dart';
import '../../support/source_text.dart';

MerchantRegistrationDetail detail(Map<String, dynamic> j) =>
    MerchantRegistrationDetail.fromJson(<String, dynamic>{
      'id': 9,
      'topicId': 42,
      'topicName': '梧桐区寻味',
      ...j,
    });

Widget page(MerchantRegistrationDetail d) => ProviderScope(
      overrides: [
        merchantRegistrationDetailProvider(9).overrideWith((ref) async => d),
      ],
      child: const MaterialApp(
        home: MerchantRegistrationEditPage(registrationId: 9),
      ),
    );

void main() {
  group('★★ 表单要发全 —— 增量更新下,少发一项 = 那一项永远改不掉', () {
    test('九个白名单字段里 App 采集得到的七项都在 body 里,且空值也发', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      final Map<String, dynamic> body = f.toJson();
      for (final String k in <String>[
        'addressName',
        'address',
        'longitude',
        'latitude',
        'activityDesc',
        'limitNum',
        'picUrl',
      ]) {
        expect(body.containsKey(k), isTrue,
            reason: '$k 没发出去 —— 增量更新会把上一次的值留在库里,'
                '而界面上它已经被清空了');
      }
    });

    test('★ 清空照片要真的能清掉 —— 发空串,不是整个字段不发', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      f.seed(detail(<String, dynamic>{'picUrl': 'a.jpg,b.jpg'}));
      expect(f.pics.length, 2);
      f.pics.clear();
      expect(f.toJson()['picUrl'], '',
          reason: '不发的话服务端会保留旧图,商家会看到"删掉的照片又回来了"');
    });

    test('★★ startDate / endDate 有意不发 —— 两端都没有采集控件,'
        '把读回来的时间串原样发回去是在赌日期格式', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      f.seed(detail(<String, dynamic>{
        'startDate': '2026-08-20 00:00:00',
        'endDate': '2026-08-30 23:59:59',
      }));
      final Map<String, dynamic> body = f.toJson();
      expect(body.containsKey('startDate'), isFalse);
      expect(body.containsKey('endDate'), isFalse);
    });

    test('★★ limitNum 缺席时表单留空,不显示 0 —— 0 的含义是「不限」', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      f.seed(detail(const <String, dynamic>{}));
      expect(f.limitNum.text, '',
          reason: '把"没设置过"写成 0,保存时就变成了一个真实设定');
      // 留空提交 = 不限人数,发 0。
      expect(f.toJson()['limitNum'], 0);
    });

    test('limitNum 有值时原样带回', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      f.seed(detail(const <String, dynamic>{'limitNum': 12}));
      expect(f.limitNum.text, '12');
      expect(f.toJson()['limitNum'], 12);
    });

    test('seed 把详情填满 —— 空表单 + 增量更新 = 拿空值覆盖没碰过的项', () {
      final MerchantRegistrationFormState f = MerchantRegistrationFormState();
      addTearDown(f.dispose);
      f.seed(detail(const <String, dynamic>{
        'addressName': '南京西路店',
        'address': '南京西路 1 号',
        'longitude': '121.45',
        'latitude': '31.23',
        'activityDesc': '二层有 20 个位子',
      }));
      final Map<String, dynamic> body = f.toJson();
      expect(body['addressName'], '南京西路店');
      expect(body['address'], '南京西路 1 号');
      expect(body['longitude'], '121.45');
      expect(body['latitude'], '31.23');
      expect(body['activityDesc'], '二层有 20 个位子');
    });
  });

  group('★ 改不了的时候不摆能填的表', () {
    testWidgets('已中标 → 锁死,并说清为什么', (WidgetTester tester) async {
      await tester.pumpWidget(page(
          detail(const <String, dynamic>{'status': 1, 'auditStatus': 1})));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reg-edit-locked')), findsOneWidget);
      expect(find.byKey(const Key('reg-edit-save')), findsNothing);
    });

    testWidgets('status 缺席(没拿到)→ 一样锁死,不赌它是待审核',
        (WidgetTester tester) async {
      await tester.pumpWidget(page(detail(const <String, dynamic>{})));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reg-edit-locked')), findsOneWidget);
    });

    testWidgets('已驳回 → 给表单,并把驳回原因摆在最上面',
        (WidgetTester tester) async {
      await tester.pumpWidget(page(detail(const <String, dynamic>{
        'status': 2,
        'reason': '门头照太糊',
      })));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reg-edit-reason')), findsOneWidget);
      expect(find.text('驳回原因:门头照太糊'), findsOneWidget);
      expect(find.byKey(const Key('reg-edit-save')), findsOneWidget);
    });

    testWidgets('★ 驳回但没填原因时说实话,不编一句', (WidgetTester tester) async {
      await tester.pumpWidget(page(detail(const <String, dynamic>{'status': 2})));
      await tester.pumpAndSettle();
      expect(find.textContaining('没填原因'), findsOneWidget);
    });
  });

  group('★ 入口不再是假的', () {
    final String code =
        codeOf('lib/feature/merchant/merchant_registrations_page.dart');

    test('「修改」按钮跳到真的编辑页,不再弹提示', () {
      expect(code.contains("/merchant/registration/"), isTrue);
      expect(code.contains('报名修改表单还在做'), isFalse,
          reason: '假入口已经换成真页面了,提示文案不该留着');
    });
  });
}
