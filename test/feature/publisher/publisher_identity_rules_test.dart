import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';
// 发布者实名(RUN-52)共用规则门禁:校验顺序、证件自洽、文案逐字、隐私红线。
//
// 对齐真源 chengyinhub-xcx/utils/publisher-identity.js + utils/form-state.js。
// 三入口(主理人申请/商家入驻/发布确认)只调这一份规则;这里钉住的是
// 「顺序与文案不许各写一套」和「永不回显 PII、永不说『认证』」两条红线。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/publisher/publisher_identity.dart';
import 'package:chengyin_app/feature/publisher/publisher_identity_fields.dart';

import '../../support/fake_publisher_identity.dart';
import '../../support/source_text.dart';

/// 用前 17 位拼出校验位自洽的完整号码(只为造日期用例,
/// 不重复被测算法的判错路径 —— 校验位错本身另有用例)。
String idWith17(String first17) {
  const weights = <int>[
    7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2,
  ];
  const codes = '10X98765432';
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += int.parse(first17[i]) * weights[i];
  }
  return '$first17${codes[sum % 11]}';
}

PublisherIdentityFormState form({
  String name = '陈晨',
  String id = '99000019491231019X',
  bool consent = true,
  bool registered = false,
}) =>
    PublisherIdentityFormState(
      realName: name,
      idCard: id,
      consented: consent,
      registered: registered,
      source: 'club_apply',
    );

void main() {
  test('English local validation never rewrites matching server error text', () async {
    final strings = AppLocalizationsEn();
    final invalid = validIdentityForm().copyWith(realName: '');
    expect(checkIdentityForm(invalid, strings: strings), 'Enter your real name');
    final api = FakePublisherIdentityApi();
    final blocked = await registerPublisherIdentity(api, invalid, strings: strings);
    expect(blocked.ok, isFalse);
    expect(api.registerCalls, isEmpty);
    api.registerError = PublisherIdentityException('请填写真实姓名');
    final server = await registerPublisherIdentity(api, validIdentityForm(), strings: strings);
    expect(server.message, '请填写真实姓名');
    api.registerError = PublisherIdentityException('');
    final missing = await registerPublisherIdentity(api, validIdentityForm(), strings: strings);
    expect(missing.message, 'Identity registration was not completed. Please try again later.');
  });

  group('isValidIdCard / normalizeIdCard:与后端 IdCardUtils 同口径', () {
    test('真源样例 99000019491231019X 合法', () {
      expect(isValidIdCard('99000019491231019X'), isTrue);
    });
    test('末位小写 x 归一化后合法(手写 X 几乎必然是小写)', () {
      expect(isValidIdCard('99000019491231019x'), isTrue);
    });
    test('内部空白归一化后合法', () {
      expect(isValidIdCard(' 990000 1949123101 9X '), isTrue);
      expect(normalizeIdCard(' 990000 1949123101 9x '),
          '99000019491231019X');
    });
    test('校验位不对就拒', () {
      expect(isValidIdCard('990000194912310191'), isFalse);
      final valid = idWith17('99000019491231019');
      expect(valid.endsWith('X'), isTrue);
      expect(isValidIdCard('${valid.substring(0, 17)}0'), isFalse);
    });
    test('位数与字符集:17 位 / 19 位 / 中间带字母都拒', () {
      expect(isValidIdCard('1101051949123100 2'), isFalse); // 去空白后 17 位
      expect(isValidIdCard('${idWith17('99000019491231019')}9'), isFalse);
      expect(isValidIdCard('1101051949123O002X'), isFalse);
    });
    test('日期档:闰年 2 月 29 收,平年 2 月 29 拒,大月 31 收小月 31 拒', () {
      expect(isValidIdCard(idWith17('11010520000229001')), isTrue); // 2000 闰
      expect(isValidIdCard(idWith17('11010519990229001')), isFalse); // 1999 平
      expect(isValidIdCard(idWith17('11010519980131001')), isTrue); // 1 月 31
      expect(isValidIdCard(idWith17('11010519980431001')), isFalse); // 4 月无 31
      expect(isValidIdCard(idWith17('11010519981301001')), isFalse); // 13 月
      expect(isValidIdCard(idWith17('11010519980001001')), isFalse); // 0 月
    });
    test('出生年不许在未来、不许早于 1900', () {
      final future = (DateTime.now().year + 1).toString();
      expect(isValidIdCard(idWith17('110105${future}0101001')), isFalse);
      expect(isValidIdCard(idWith17('11010518991231001')), isFalse);
    });
    test('idWith17 造的号确实通过(辅助函数没跑偏)', () {
      expect(idWith17('99000019491231019'), '99000019491231019X');
      expect(isValidIdCard(idWith17('99000019491231019')), isTrue);
    });
  });

  group('checkIdentityForm:顺序与文案逐字对齐真源', () {
    test('姓名空的 → 先说姓名', () {
      expect(checkIdentityForm(form(name: '   ')), '请填写真实姓名');
    });
    test('姓名 1 字 / 21 字 → 说 2-20', () {
      expect(checkIdentityForm(form(name: '陈')), '请填写真实姓名(2-20 个字)');
      expect(
          checkIdentityForm(
              form(name: '陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈陈')),
          '请填写真实姓名(2-20 个字)');
    });
    test('姓名带数字 → 单独一条(且在长度之后判)', () {
      expect(checkIdentityForm(form(name: '陈晨9')), '姓名里不应包含数字');
      expect(checkIdentityForm(form(name: '9')), '请填写真实姓名(2-20 个字)',
          reason: '长度先于数字,顺序不许换');
    });
    test('证件不自洽 → 点名身份证,哪怕勾了同意', () {
      expect(checkIdentityForm(form(id: '990000194912310191')),
          '身份证号格式不正确，请核对后重填');
    });
    test('前两项都过、没勾同意 → 说同意', () {
      expect(checkIdentityForm(form(consent: false)),
          '请先同意提供真实姓名与身份证号');
    });
    test('三项齐 → null;已登记直接 null(不再要字段)', () {
      expect(checkIdentityForm(form()), isNull);
      expect(checkIdentityForm(form(registered: true)), isNull);
    });
    test('identitySatisfied 与 checkIdentityForm 同源', () {
      expect(identitySatisfied(form()), isTrue);
      expect(identitySatisfied(form(consent: false)), isFalse);
      expect(identitySatisfied(form(registered: true, name: '', id: '',
          consent: false)), isTrue);
    });
  });

  group('文案红线', () {
    test('同意文案逐字(个保法 §29:哪些信息、给谁、干什么)', () {
      expect(
        kIdentityConsentText,
        '同意向城瘾提供真实姓名与身份证号，仅用于发布人身份核验，不对外展示',
      );
    });
    test('只说「已登记」,不许说「认证」——平台没有三要素通道', () {
      expect(kIdentityAlreadyRegisteredHint,
          '已登记。如需变更实名信息，请联系平台客服。');
      for (final text in <String>[
        kIdentityConsentText,
        kIdentityAlreadyRegisteredHint,
        kIdentityNetworkErrorText,
        kIdentityRegisterFallbackText,
        checkIdentityForm(form(consent: false))!,
        checkIdentityForm(form(id: 'x'))!,
      ]) {
        expect(text, isNot(contains('认证')));
      }
    });
    test('改绑走人工:提示里指路客服', () {
      expect(kIdentityAlreadyRegisteredHint, contains('客服'));
    });
    test('网络失败与兜底文案各一条,都点名失败的是什么', () {
      expect(kIdentityNetworkErrorText, '网络异常，实名信息没有提交成功');
      expect(kIdentityRegisterFallbackText, '实名信息登记没有完成，请稍后重试');
    });
    test('三入口 source 常量与后端白名单一致', () {
      expect(kIdentitySourceClubApply, 'club_apply');
      expect(kIdentitySourceMerchantApply, 'merchant_apply');
      expect(kIdentitySourceTopicPublish, 'topic_publish');
    });
  });

  group('registerPublisherIdentity:没过校验一个请求都不发', () {
    test('字段不全时不触网,直接回第一条问题', () async {
      final api = FakePublisherIdentityApi();
      final outcome = await registerPublisherIdentity(api, form(id: ''));
      expect(outcome.ok, isFalse);
      expect(outcome.message, '身份证号格式不正确，请核对后重填');
      expect(api.registerCalls, isEmpty, reason: '没过校验就该零请求');
    });
    test('过校验后按归一化值提交,consent 恒真', () async {
      final api = FakePublisherIdentityApi();
      final outcome = await registerPublisherIdentity(
        api,
        form(name: ' 陈晨 ', id: '990000 1949123101 9x'),
      );
      expect(outcome.ok, isTrue);
      expect(api.registerCalls, <Map<String, Object?>>[
        <String, Object?>{
          'realName': '陈晨',
          'idCard': '99000019491231019X',
          'consent': true,
          'source': 'club_apply',
        },
      ]);
    });
  });

  group('钉子:URL 字面量写在调用点、隐私红线在页面层', () {
    test('两条 endpoint 以字面量出现在 API 调用点(常量不提,parity 才认得到)', () {
      final code = codeOf('lib/data/api/publisher_identity_api.dart');
      expect(code, contains("""'/api/publisher/identity/status'"""));
      expect(code, contains("""'/api/publisher/identity'"""));
    });
    test('三个入口页的业务 payload 里不许出现 realName / idCard', () {
      for (final path in <String>[
        'lib/feature/club/club_apply_page.dart',
        'lib/feature/merchant/merchant_apply_page.dart',
        'lib/feature/publish/publish_pro_page.dart',
        'lib/feature/publish/publish_pro_sheets.dart',
      ]) {
        final code = codeOf(path);
        expect(code, isNot(contains("'realName'")), reason: '$path 往业务请求塞实名');
        expect(code, isNot(contains("'idCard'")), reason: '$path 往业务请求塞证件号');
      }
    });
    test('共用件之外不许再写一份姓名/证件字段名给后端', () {
      final code = codeOf('lib/feature/publisher/publisher_identity_fields.dart');
      expect(code, isNot(contains("'idCard'")));
    });
    test('Controller 登记成功当场清值(姓名/证件不留在页面状态里)', () async {
      final controller =
          PublisherIdentityController(source: kIdentitySourceClubApply);
      addTearDown(controller.dispose);
      controller.realName.text = '陈晨';
      controller.idCard.text = '99000019491231019X';
      controller.setConsented(true);
      controller.setError('随便一条');
      controller.markRegistered();
      expect(controller.registered, isTrue);
      expect(controller.realName.text, isEmpty);
      expect(controller.idCard.text, isEmpty);
      expect(controller.consented, isFalse);
      expect(controller.error, isNull);
    });
  });
}
