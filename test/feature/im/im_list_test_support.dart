// 会话列表测试的共用假件(不是测试文件,不会被 test 收集)。
//
// 假件只实现页面真正会调的方法,其余交给 noSuchMethod ——
// 页面要是偷偷调了别的,这里会抛,而不是拿到一份编好的假数据。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeImApi implements ImApi {
  final List<int> readIds = <int>[];
  final List<int> deletedIds = <int>[];
  final List<bool> muteValues = <bool>[];

  /// 让这几个会话的 read 失败 —— 用来验「全部已读」按真实成功数回话。
  final Set<int> failRead = <int>{};

  @override
  Future<void> read(int conversationId) async {
    if (failRead.contains(conversationId)) throw Exception('boom');
    readIds.add(conversationId);
  }

  @override
  Future<String> deleteConversation(int conversationId) async {
    deletedIds.add(conversationId);
    return '已删除会话';
  }

  @override
  Future<String> mute(int conversationId, {required bool muted}) async {
    muteValues.add(muted);
    return muted ? '已开启免打扰' : '已关闭免打扰';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Conversation conv({
  int id = 7,
  int type = kImTypeSingle,
  String nickname = '阿林',
  String avatar = '',
  String? preview = '周六见',
  String? at = '2026-01-15 20:10:00',
  int unread = 0,
  bool? muted = false,
}) => Conversation(
  conversationId: id,
  type: type,
  counterparty: ImCounterparty(id: 8, nickname: nickname, avatar: avatar),
  lastMsgText: preview,
  lastMsgAt: at,
  unread: unread,
  muted: muted,
);

Future<void> pumpImList(
  WidgetTester tester, {
  required List<Conversation> list,
  FakeImApi? api,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        imConversationsProvider.overrideWith((Ref ref) async => list),
        imApiProvider.overrideWithValue(api ?? FakeImApi()),
      ].cast(),
      child: MaterialApp(
        home: const ImListPage(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
