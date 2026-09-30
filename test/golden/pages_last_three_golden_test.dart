// 最后三个还没有基准图的路由:/publish/pro、/im/chat、/roam/session。
//
// 这三个之前一直没拍,理由是"替身太重"—— 但"重"不是不拍的理由,
// 只是拍之前要多写几十行假件。本轮已经靠看图抓到过四个只在整页渲染时
// 才现形的问题(模型层各自都对),漏掉的页越少越好。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_last_three_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/publisher_identity_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/im/im_chat_page.dart';
import 'package:chengyin_app/feature/publish/publish_pro_page.dart';
import 'package:chengyin_app/feature/roam/roam_session_page.dart';
import 'package:chengyin_app/feature/roam/roam_session_store.dart';
import 'golden_theme.dart';

/// 只实现页面真正会调的那几个方法,其余交给 noSuchMethod ——
/// 页面要是偷偷调了别的,这里会抛,而不是拿到一份编好的假数据。
class _FakeImApi implements ImApi {
  _FakeImApi(this._page);
  final ChatPage _page;

  @override
  Future<ChatPage> messages(int conversationId,
          {int cursorId = 0, int size = 30}) async =>
      _page;

  @override
  Future<void> read(int conversationId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoamStore implements RoamSessionStore {
  _FakeRoamStore(this._session);
  final RoamSession? _session;

  @override
  Future<RoamSession?> findByTs(int ts) async => _session;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClubApi implements ClubApi {
  @override
  Future<List<Club>> my() async => <Club>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePublisherIdentityApi implements PublisherIdentityApi {
  @override
  Future<bool> status() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

Future<void> _shot(WidgetTester t, Widget app, String path,
    {Size size = const Size(390, 1000)}) async {
  setGoldenViewport(t, size);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

Widget _app(List<dynamic> overrides, Widget home, {ThemeData? theme}) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: theme ?? goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );

void main() {
  // ⚠️★★★ 聊天基准图**不许用相对时间会变的日期**。
  //   第一版用的是「昨天」那一档(2026-08-18,拍图那天是 08-19)——
  //   到了 08-20 它自动变成「8月18日」,基准图**每天都会红一次**,
  //   而红的原因和代码无关。那是会自己腐烂的证据,比没有更坏
  //   (它会训练人忽略红色)。
  //   im_time.dart 的判据是 `diffDays`:0=HH:mm / 1=昨天 / 更早=M月d日。
  //   ⇒ fixture 一律用**远早于今天**的日期,让它永远落在「更早」那一档。
  testWidgets('★★ 聊天:自己/对方气泡 + 图片消息 + 拉黑入口(有 peerMemberId)',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          // ★ myId 来自 authControllerProvider —— 不 override 的话它是 0,
          //   于是**自己发的消息也会渲成对方的**(左侧+对方头像)。
          //   第一版基准图就是这样,差点被我当成"气泡左右判反了"的 bug。
          authControllerProvider.overrideWith(() => _FixedAuth(AuthState(
                user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
                initialized: true,
              ))),
          imApiProvider.overrideWithValue(_FakeImApi(ChatPage(
            list: <ChatMessage>[
              ChatMessage(
                id: 1,
                conversationId: 9,
                senderId: 2,
                msgType: kMsgText,
                content: '你好,我看到你在静安夜行那场也报名了',
                createTime: '2026-01-15 20:10:00',
              ),
              ChatMessage(
                id: 2,
                conversationId: 9,
                senderId: 1,
                msgType: kMsgText,
                content: '是的,周六见',
                createTime: '2026-01-15 20:11:30',
              ),
              // ★ 图片消息:URL 是坏的 —— 兜底不能画系统碎图标
              ChatMessage(
                id: 3,
                conversationId: 9,
                senderId: 2,
                msgType: kMsgImage,
                content: 'https://example.invalid/a.png',
                createTime: '2026-01-15 20:12:00',
              ),
              // ★ 空内容的文本:后端字段可空,不能渲成一个空气泡
              ChatMessage(
                id: 4,
                conversationId: 9,
                senderId: 2,
                msgType: kMsgText,
                createTime: '2026-01-15 20:13:00',
              ),
            ],
          ))),
        ],
        const ImChatPage(
          conversationId: 9,
          peerName: '小李',
          peerMemberId: 2,
        ),
      ),
      'goldens/page_im_chat.png',
    );
  });

  testWidgets('★ 聊天空态:一句话都还没说', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          imApiProvider.overrideWithValue(
              _FakeImApi(ChatPage(list: <ChatMessage>[]))),
        ],
        // ★ peerMemberId=0:上游没带过来 —— 拉黑入口必须**不在**,
        //   而不是摆着点下去必然失败。
        const ImChatPage(conversationId: 9, peerName: '小李'),
      ),
      'goldens/page_im_chat_empty.png',
    );
  });

  testWidgets('★★ 漫游回看:路线图 + 统计 + 点亮的店',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          roamSessionStoreProvider.overrideWithValue(_FakeRoamStore(
            const RoamSession(
              ts: 1755518400000,
              zone: '静安寺街区',
              dateLine: '2026-08-18 晚',
              distance: 3.4,
              explorePct: 62,
              shops: 2,
              time: '48:20',
              durSec: 2900,
              pois: <RoamPoi>[
                RoamPoi(name: '静安咖啡', cat: 'merchant'),
                RoamPoi(name: '愚园路口袋公园', cat: 'park'),
              ],
              track: <RoamPoint>[
                RoamPoint(lat: 31.2230, lng: 121.4450),
                RoamPoint(lat: 31.2245, lng: 121.4468),
                RoamPoint(lat: 31.2261, lng: 121.4462),
                RoamPoint(lat: 31.2270, lng: 121.4489),
              ],
            ),
          )),
        ],
        const RoamSessionPage(ts: 1755518400000),
      ),
      'goldens/page_roam_session.png',
    );
  });

  testWidgets('★ 漫游回看:找不到这次(本地只留最近 50 条)',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          roamSessionStoreProvider.overrideWithValue(_FakeRoamStore(null)),
        ],
        const RoamSessionPage(ts: 1),
      ),
      'goldens/page_roam_session_not_found.png',
      size: const Size(390, 700),
    );
  });

  testWidgets('★★ 专业版编辑器:新建草稿的第一屏',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(AuthState(
                user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
                initialized: true,
              ))),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          // #463 开页即查发布者实名状态:不挡掉,dio 真链在测试里挂表,
          // teardown 必炸「A Timer is still pending」。
          publisherIdentityApiProvider.overrideWithValue(
              _FakePublisherIdentityApi()),
        ],
        const PublishProPage(),
        // ★ 恒浅(app_router.dart:_topicEditorLight),基准图也必须浅色。
        theme: topicEditorGoldenTheme(),
      ),
      'goldens/page_publish_pro.png',
      size: const Size(390, 1400),
    );
  });
}
