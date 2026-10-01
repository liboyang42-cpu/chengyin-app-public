import '../../l10n/app_localizations.dart';
import 'dart:async';

import 'package:dio/dio.dart';

import '../../data/api/publisher_identity_api.dart';

/// 发布者实名(RUN-52 改判后口径)—— 三个入口共用的采集规则真源,
/// 对齐小程序 `utils/publisher-identity.js` + `utils/form-state.js`。
///
/// 校验规则、同意文案、状态查询、提交时序若在每处各写一遍,一定会有一处漏
/// ——所以三入口只调这里,页面不许自己拿身份证校验位。

/// 采集入口(后端 MemberIdentityService 白名单校验)。
const String kIdentitySourceClubApply = 'club_apply';
const String kIdentitySourceMerchantApply = 'merchant_apply';
const String kIdentitySourceTopicPublish = 'topic_publish';

/// 必须写清「哪些信息、给谁、干什么用」(个保法 §29 单独同意),不能只写"我已阅读并同意"。
const String kIdentityConsentText =
    '同意向城瘾提供真实姓名与身份证号，仅用于发布人身份核验，不对外展示';
const String kIdentityAlreadyRegisteredHint =
    '已登记。如需变更实名信息，请联系平台客服。';
const String kIdentityNetworkErrorText = '网络异常，实名信息没有提交成功';
const String kIdentityRegisterFallbackText = '实名信息登记没有完成，请稍后重试';

/// 与后端 `IdCardUtils` 逐条同口径(校验位表、日期判、只收 18 位)。
/// 前端这份只负责「当场说清哪一格错了」,两边算法不一致时用户会看到
/// 「前端放行、后端报格式不正确」这种解释不了的失败。
const List<int> _idCardWeights = <int>[
  7,
  9,
  10,
  5,
  8,
  4,
  2,
  1,
  6,
  3,
  7,
  9,
  10,
  5,
  8,
  4,
  2,
];
const String _idCardCheckCodes = '10X98765432';

/// 去首尾与内部空白、末位 x 转大写。手写 X 几乎必然是小写,不归一化会把合法号判成非法。
String normalizeIdCard(Object? value) =>
    (value == null ? '' : value.toString()).replaceAll(RegExp(r'\s+'), '').toUpperCase();

bool isValidIdCard(Object? value) {
  final id = normalizeIdCard(value);
  if (id.length != 18) return false;
  if (!RegExp(r'^\d{17}[0-9X]$').hasMatch(id)) return false;
  final year = int.parse(id.substring(6, 10));
  final month = int.parse(id.substring(10, 12));
  final day = int.parse(id.substring(12, 14));
  if (year < 1900 || year > DateTime.now().year) return false;
  if (month < 1 || month > 12) return false;
  const daysInMonth = <int>[
    31,
    28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  final maxDay =
      month == 2 && _isLeap(year) ? 29 : daysInMonth[month - 1];
  if (day < 1 || day > maxDay) return false;
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += int.parse(id[i]) * _idCardWeights[i];
  }
  return _idCardCheckCodes[sum % 11] == id[17];
}

bool _isLeap(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// 一份规则的形状:页面字段名到这里做唯一一次翻译。
class PublisherIdentityFormState {
  const PublisherIdentityFormState({
    this.realName = '',
    this.idCard = '',
    this.consented = false,
    this.registered = false,
    this.source = '',
  });

  final String realName;
  final String idCard;
  final bool consented;
  final bool registered;
  final String source;

  PublisherIdentityFormState copyWith({
    String? realName,
    String? idCard,
    bool? consented,
    bool? registered,
  }) =>
      PublisherIdentityFormState(
        realName: realName ?? this.realName,
        idCard: idCard ?? this.idCard,
        consented: consented ?? this.consented,
        registered: registered ?? this.registered,
        source: source,
      );
}

/// 返回第一条不满足的原因;全通过返回 null。
/// 与后端 `MemberIdentityService.register` 的校验顺序一致:姓名 → 证件 → 单独同意。
String? checkIdentityForm(PublisherIdentityFormState form, {AppLocalizations? strings}) {
  final name = form.realName.trim();
  if (name.isEmpty) return strings?.merchantApplyRealNameRequired ?? '请填写真实姓名';
  if (name.length < 2 || name.length > 20) return strings?.merchantApplyRealNameLength ?? '请填写真实姓名(2-20 个字)';
  if (RegExp('[0-9]').hasMatch(name)) return strings?.merchantApplyRealNameDigits ?? '姓名里不应包含数字';
  if (!isValidIdCard(form.idCard)) return strings?.merchantApplyIdInvalid ?? '身份证号格式不正确，请核对后重填';
  if (!form.consented) return strings?.merchantApplyConsentRequired ?? '请先同意提供真实姓名与身份证号';
  return null;
}

/// 按钮亮不亮的轻量判定:已登记直接过;没登记则三格都要满足。
/// 规则仍只有 [checkIdentityForm] 一份 —— 这里只是不要那段文案,不是另写一套判断。
bool identitySatisfied(PublisherIdentityFormState form) =>
    form.registered || checkIdentityForm(form) == null;

/// 提交结果,对齐真源 onDone({ ok, message, network }):
/// message 用接口原文(它是服务端唯一说得清「这张证件已绑在别的账号上」的地方),
/// network 供调用方选报错条样式(重试 vs 核对)。
class IdentityRegisterOutcome {
  const IdentityRegisterOutcome.ok()
    : message = '',
      network = false,
      ok = true;

  const IdentityRegisterOutcome.fail(this.message, {this.network = false})
    : ok = false;

  final bool ok;
  final String message;
  final bool network;
}

/// 提交登记:先过同一份校验(没过一个请求都不许发出去),再落 /api/publisher/identity。
Future<IdentityRegisterOutcome> registerPublisherIdentity(
  PublisherIdentityApi api,
  PublisherIdentityFormState form, {
  AppLocalizations? strings,
}) async {
  final problem = checkIdentityForm(form, strings: strings);
  if (problem != null) {
    return IdentityRegisterOutcome.fail(problem);
  }
  try {
    await api.register(
      realName: form.realName.trim(),
      idCard: normalizeIdCard(form.idCard),
      consent: true,
      source: form.source,
    );
    return const IdentityRegisterOutcome.ok();
  } on PublisherIdentityException catch (e) {
    return IdentityRegisterOutcome.fail(
      e.message.isEmpty ? (strings?.publisherUiRegisterIncomplete ?? kIdentityRegisterFallbackText) : e.message,
    );
  } on DioException {
    return IdentityRegisterOutcome.fail(
      strings?.merchantApplyIdentityNetworkError ?? kIdentityNetworkErrorText,
      network: true,
    );
  }
}
