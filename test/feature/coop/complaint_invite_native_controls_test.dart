import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  group('投诉页使用 Apple 原生表单交互', () {
    final String code = codeOf('lib/feature/coop/complaint_page.dart');

    test('活动与类型从 Cupertino Sheet 选择', () {
      expect(code.contains('showCupertinoSheet<int>'), isTrue);
      expect(code.contains('coopComplaintActivity'), isTrue);
      expect(code.contains('coopComplaintType'), isTrue);
      expect(code.contains("'服务与履约'"), isTrue);
      expect(code.contains("'费用与退款'"), isTrue);
    });

    test('文本输入、加载与提交都是 Cupertino 控件', () {
      expect(code.contains('CupertinoTextField('), isTrue);
      expect(code.contains("Key('complaint-reason')"), isTrue);
      expect(code.contains("Key('complaint-contact')"), isTrue);
      expect(code.contains('CupertinoActivityIndicator'), isTrue);
      expect(code.contains('CupertinoButton.filled'), isTrue);
      expect(code.contains(RegExp(r'(?<!Cupertino)\bTextField\(')), isFalse);
      expect(code.contains('FilledButton('), isFalse);
      expect(code.contains('RadioListTile'), isFalse);
    });

    test('保留小程序的 5 字门禁和 reason 组装格式', () {
      expect(code.contains('_reason.text.trim().length >= 5'), isTrue);
      expect(code.contains(r"'【${_complaintTypes[_typeIndex!]}】$r'"), isTrue);
      expect(code.contains(r"'$r\n联系方式：$c'"), isTrue);
    });
  });

  group('协作邀约页使用 Apple 原生控件', () {
    final String code = codeOf('lib/feature/coop/coop_invite_page.dart');

    test('合作条款为系统分段控件', () {
      expect(
        code.contains('CupertinoSlidingSegmentedControl<CoopShareMode>'),
        isTrue,
      );
      expect(code.contains('CyTabs('), isFalse);
    });

    test('顺序保持小程序的主题 → 条款 → 邀请对象', () {
      final int topic = code.indexOf('coopAssociatedTheme');
      final int terms = code.indexOf('② 合作条款');
      final int targets = code.indexOf('coopRecipients');
      expect(topic, greaterThan(0));
      expect(terms, greaterThan(topic));
      expect(targets, greaterThan(terms));
      expect(code.contains('coopInviteTopicsProvider'), isTrue);
    });

    test('选人、留言、删除与提交均为 Cupertino 控件', () {
      expect(code.contains('CupertinoTextField('), isTrue);
      expect(code.contains('CupertinoButton.tinted'), isTrue);
      expect(code.contains('CupertinoButton.filled'), isTrue);
      expect(code.contains('CupertinoActivityIndicator'), isTrue);
      expect(code.contains(RegExp(r'(?<!Cupertino)\bTextField\(')), isFalse);
      expect(code.contains('OutlinedButton'), isFalse);
      expect(code.contains('FilledButton'), isFalse);
      expect(code.contains('Chip('), isFalse);
    });
  });

  test('邀约路由同时支持无主题入口与小程序预填参数', () {
    final String router = codeOf('lib/core/router/app_router.dart');
    expect(router.contains("path: '/coop/invite'"), isTrue);
    expect(router.contains("queryParameters['type']"), isTrue);
    expect(router.contains("queryParameters['toId']"), isTrue);
    expect(router.contains("queryParameters['originApplyId']"), isTrue);
  });
}
