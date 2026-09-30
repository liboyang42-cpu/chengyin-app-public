// 三张承接表单的提交闸与 body 形状。
//
// ★★ 「填实际供给」的 body 形状由**章节条款档**决定,不由前端挑:
//   服务端拿章节档位和提交的档位比,不一致直接拒
//   (「本章节是「权益承接」,不能按「计酬承接」入驻」)。
//   档位选错或必填项缺失,表现出来都是"点了提交什么也没发生 + 一句看不懂的话"。
//
// ★ 断言锚 Key,不锚中文标签。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_sheets.dart';

/// 只覆盖本组用到的那两个读接口,其余一律不实现 —— 被调到就会抛,
/// 那正好证明「这张表单不该调它」。
class _FakeCoopApi implements CoopApi {
  _FakeCoopApi(this.perks);
  final List<Map<String, dynamic>> perks;

  @override
  Future<List<Map<String, dynamic>>> perkTemplates() async => perks;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被这张表单调到');
}

class _FakeTemplateApi implements TemplateApi {
  _FakeTemplateApi(this.rows);
  final List<PlayTemplate> rows;

  @override
  Future<List<PlayTemplate>> myList() async => rows;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被这张表单调到');
}

class _FakeMerchantApi implements MerchantApi {
  @override
  Future<Map<String, dynamic>> merchantInfo() async => <String, dynamic>{
    'address': '南京西路 1 号',
    'name': '拐角咖啡',
  };

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被这张表单调到');
}

/// 把表单挂在一个按钮后面,点开、操作、读回它 pop 出来的值。
Future<Object?> openSheet(
  WidgetTester tester, {
  required Future<Object?> Function(BuildContext, WidgetRef) open,
  List<Map<String, dynamic>> perks = const <Map<String, dynamic>>[],
  List<PlayTemplate> templates = const <PlayTemplate>[],
}) async {
  Object? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coopApiProvider.overrideWithValue(_FakeCoopApi(perks)),
        templateApiProvider.overrideWithValue(_FakeTemplateApi(templates)),
        merchantApiProvider.overrideWithValue(_FakeMerchantApi()),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (BuildContext ctx, WidgetRef ref, _) {
            return Scaffold(
              body: Builder(
                builder: (BuildContext inner) => Center(
                  child: ElevatedButton(
                    key: const Key('open'),
                    onPressed: () async => result = await open(inner, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  group('★★ 填实际供给:形状随章节档位走', () {
    testWidgets('引流档不收数字,开就能提交', (WidgetTester tester) async {
      final Object? Function() read =
          (await openSheet(
                tester,
                open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
                  c,
                  r,
                  chapterId: 7,
                  chapterName: '第一章',
                  termsMode: 'TRAFFIC',
                ),
              ))
              as Object? Function();
      expect(find.byKey(const Key('offer-quota')), findsNothing);
      expect(find.byKey(const Key('offer-fee')), findsNothing);
      await tester.tap(find.byKey(const Key('offer-submit')));
      await tester.pumpAndSettle();
      expect(read(), <String, dynamic>{'chapterId': 7, 'termsMode': 'TRAFFIC'});
    });

    testWidgets('★ 权益档:模板没选或额度 <1 时提交钮是灰的', (WidgetTester tester) async {
      final Object? Function() read =
          (await openSheet(
                tester,
                perks: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 3,
                    'name': '一杯手冲',
                    'retailValue': 30,
                    'quota': 50,
                  },
                ],
                open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
                  c,
                  r,
                  chapterId: 7,
                  chapterName: '第一章',
                  termsMode: 'PERK',
                ),
              ))
              as Object? Function();

      CupertinoButton submit() =>
          tester.widget<CupertinoButton>(find.byKey(const Key('offer-submit')));
      expect(submit().onPressed, isNull, reason: '什么都没填就能点 = 点了必被拒');

      await tester.enterText(find.byKey(const Key('offer-quota')), '0');
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull, reason: '额度 0 会被判「至少 1 人次」');

      await tester.enterText(find.byKey(const Key('offer-quota')), '20');
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull, reason: '还没选权益模板');

      await tester.tap(find.byKey(const Key('offer-perk-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一杯手冲').last);
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('offer-submit')));
      await tester.pumpAndSettle();
      expect(read(), <String, dynamic>{
        'chapterId': 7,
        'termsMode': 'PERK',
        'perkTemplateId': 3,
        'quotaTotal': 20,
      });
    });

    testWidgets('★★ 零售价或额度不是正数的权益模板不进选项 —— 选了也会在入驻那步被拒', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        perks: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 3,
            'name': '好用的',
            'retailValue': 30,
            'quota': 50,
          },
          <String, dynamic>{
            'id': 4,
            'name': '没定价的',
            'retailValue': 0,
            'quota': 50,
          },
          <String, dynamic>{
            'id': 5,
            'name': '没额度的',
            'retailValue': 30,
            'quota': 0,
          },
        ],
        open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
          c,
          r,
          chapterId: 7,
          chapterName: '第一章',
          termsMode: 'PERK',
        ),
      );
      await tester.tap(find.byKey(const Key('offer-perk-picker')));
      await tester.pumpAndSettle();
      expect(find.text('没定价的'), findsNothing);
      expect(find.text('没额度的'), findsNothing);
      expect(find.text('好用的'), findsWidgets);
    });

    testWidgets('计酬档:每人次金额必填,0 是合法的', (WidgetTester tester) async {
      final Object? Function() read =
          (await openSheet(
                tester,
                open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
                  c,
                  r,
                  chapterId: 7,
                  chapterName: '第一章',
                  termsMode: 'REVSHARE',
                ),
              ))
              as Object? Function();
      CupertinoButton submit() =>
          tester.widget<CupertinoButton>(find.byKey(const Key('offer-submit')));
      final CupertinoTextField fee = tester.widget<CupertinoTextField>(
        find.byKey(const Key('offer-fee')),
      );
      expect(
        fee.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(fee.textInputAction, TextInputAction.done);
      expect(submit().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('offer-fee')), '0');
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull, reason: '0 元合作是真实存在的档,不该拦');
      await tester.enterText(find.byKey(const Key('offer-fee')), '12.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offer-submit')));
      await tester.pumpAndSettle();
      expect(read(), <String, dynamic>{
        'chapterId': 7,
        'termsMode': 'REVSHARE',
        'perHeadFee': 12.5,
      });
    });

    testWidgets('★ 权益档没有可用模板时说清楚,而不是渲一个空下拉', (WidgetTester tester) async {
      await openSheet(
        tester,
        open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
          c,
          r,
          chapterId: 7,
          chapterName: '第一章',
          termsMode: 'PERK',
        ),
      );
      expect(find.byKey(const Key('offer-perk-empty')), findsOneWidget);
      expect(find.byKey(const Key('offer-perk-picker')), findsNothing);
    });
  });

  group('★★ 申请承接并配置点位', () {
    testWidgets('点位名和玩法模板都齐了才能提交', (WidgetTester tester) async {
      final Object? Function() read =
          (await openSheet(
                tester,
                templates: <PlayTemplate>[
                  const PlayTemplate(id: 11, title: '街角寻物'),
                ],
                open: (BuildContext c, WidgetRef r) =>
                    showChapterApplyForm(c, r, chapterName: '第一章'),
              ))
              as Object? Function();

      CupertinoButton submit() =>
          tester.widget<CupertinoButton>(find.byKey(const Key('apply-submit')));
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('apply-node-name')), '南京西路店');
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull, reason: '还没选玩法模板');

      await tester.tap(find.byKey(const Key('apply-template-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('街角寻物').last);
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('apply-submit')));
      await tester.pumpAndSettle();
      final ChapterNodeDraft d = read()! as ChapterNodeDraft;
      expect(d.name, '南京西路店');
      expect(d.templateId, 11);
      // 店址默认取店铺资料。
      expect(d.address, '南京西路 1 号');
    });

    testWidgets('★★ 玩法列表读失败说「没读出来」,不说「你还没有玩法」', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            templateApiProvider.overrideWithValue(_ThrowingTemplateApi()),
            merchantApiProvider.overrideWithValue(_FakeMerchantApi()),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (BuildContext ctx, WidgetRef ref, _) {
                return Scaffold(
                  body: Builder(
                    builder: (BuildContext inner) => Center(
                      child: ElevatedButton(
                        key: const Key('open'),
                        onPressed: () => showChapterApplyForm(
                          inner,
                          ref,
                          chapterName: '第一章',
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apply-template-error')), findsOneWidget);
      expect(
        find.byKey(const Key('apply-template-empty')),
        findsNothing,
        reason: '把"读不到"说成"你没有",商家会去重做一个已经存在的模板',
      );
    });
  });

  group('Apple 系统选择器与键盘', () {
    testWidgets('三张富内容表单都用 Cupertino sheet 与原生输入控件', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        templates: <PlayTemplate>[const PlayTemplate(id: 11, title: '街角寻物')],
        open: (BuildContext c, WidgetRef r) =>
            showChapterApplyForm(c, r, chapterName: '第一章'),
      );
      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoPageScaffold),
          matching: find.byKey(const Key('apply-node-name')),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('apply-node-name')),
            )
            .textInputAction,
        TextInputAction.next,
      );
      await tester.tap(find.byKey(const Key('apply-cancel')));
      await tester.pumpAndSettle();

      await openSheet(
        tester,
        open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
          c,
          r,
          chapterId: 7,
          chapterName: '第一章',
          termsMode: 'REVSHARE',
        ),
      );
      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CupertinoTextField &&
              widget.key == const Key('offer-fee'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('offer-cancel')));
      await tester.pumpAndSettle();

      await openSheet(
        tester,
        open: (BuildContext c, WidgetRef r) => showNodeRegistrationForm(
          c,
          r,
          topicId: 9,
          nodes: <TopicNode>[TopicNode(id: 21, name: '静安寺站')],
        ),
      );
      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CupertinoTextField &&
              widget.key == const Key('reg-activity-desc'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('玩法模板用 Cupertino Action Sheet 选择', (WidgetTester tester) async {
      await openSheet(
        tester,
        templates: <PlayTemplate>[const PlayTemplate(id: 11, title: '街角寻物')],
        open: (BuildContext c, WidgetRef r) =>
            showChapterApplyForm(c, r, chapterName: '第一章'),
      );

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      await tester.tap(find.byKey(const Key('apply-template-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('街角寻物'), findsOneWidget);
      await tester.tap(find.text('街角寻物'));
      await tester.pumpAndSettle();
      expect(find.text('街角寻物'), findsOneWidget);
    });

    testWidgets('动态选项超过三个时改用 CupertinoPicker，不让 Action Sheet 滚动', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        templates: List<PlayTemplate>.generate(
          4,
          (int index) => PlayTemplate(id: index + 1, title: '玩法 ${index + 1}'),
        ),
        open: (BuildContext c, WidgetRef r) =>
            showChapterApplyForm(c, r, chapterName: '第一章'),
      );

      await tester.tap(find.byKey(const Key('apply-template-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.byType(CupertinoPicker), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('权益用 Action Sheet，额度唤起 iOS 整数键盘', (WidgetTester tester) async {
      await openSheet(
        tester,
        perks: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 3,
            'name': '一杯手冲',
            'retailValue': 30,
            'quota': 50,
          },
        ],
        open: (BuildContext c, WidgetRef r) => showChapterOfferForm(
          c,
          r,
          chapterId: 7,
          chapterName: '第一章',
          termsMode: 'PERK',
        ),
      );
      final CupertinoTextField quota = tester.widget<CupertinoTextField>(
        find.byKey(const Key('offer-quota')),
      );
      expect(quota.keyboardType, TextInputType.number);
      expect(quota.textInputAction, TextInputAction.done);
      await tester.tap(find.byKey(const Key('offer-perk-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('一杯手冲'), findsOneWidget);
    });

    testWidgets('站点选择用 Action Sheet，可配合时间按起止顺序走系统轮盘', (
      WidgetTester tester,
    ) async {
      await openSheet(
        tester,
        open: (BuildContext c, WidgetRef r) => showNodeRegistrationForm(
          c,
          r,
          topicId: 9,
          nodes: <TopicNode>[TopicNode(id: 21, name: '静安寺站')],
        ),
      );

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      await tester.tap(find.byKey(const Key('register-node-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tester.tap(find.text('静安寺站'));
      await tester.pumpAndSettle();

      final CupertinoTextField limit = tester.widget<CupertinoTextField>(
        find.byKey(const Key('reg-limit-num')),
      );
      expect(limit.keyboardType, TextInputType.number);
      expect(limit.textInputAction, TextInputAction.next);

      final CupertinoTextField longitude = tester.widget<CupertinoTextField>(
        find.byKey(const Key('reg-longitude')),
      );
      expect(
        longitude.keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );
      expect(longitude.textInputAction, TextInputAction.next);
      final CupertinoTextField latitude = tester.widget<CupertinoTextField>(
        find.byKey(const Key('reg-latitude')),
      );
      expect(
        latitude.keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );
      expect(latitude.textInputAction, TextInputAction.done);

      await tester.tap(find.byKey(const Key('register-cooperate-date')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.text('开始时间'), findsOneWidget);
      CupertinoDatePicker picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.mode, CupertinoDatePickerMode.time);
      expect((picker.minimumDate!.hour, picker.minimumDate!.minute), (0, 0));
      expect((picker.maximumDate!.hour, picker.maximumDate!.minute), (23, 59));

      await tester.tap(find.byKey(const Key('cy-native-picker-done')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.text('结束时间'), findsOneWidget);
      picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.mode, CupertinoDatePickerMode.time);
      expect((picker.minimumDate!.hour, picker.minimumDate!.minute), (0, 0));
      expect((picker.maximumDate!.hour, picker.maximumDate!.minute), (23, 59));

      await tester.tap(find.byKey(const Key('cy-native-picker-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.text('例如 09:00-18:00'),
        findsOneWidget,
        reason: '取消结束时间时不应只写入开始时间',
      );
    });
  });
}

class _ThrowingTemplateApi implements TemplateApi {
  @override
  Future<List<PlayTemplate>> myList() async => throw Exception('网络异常');

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
