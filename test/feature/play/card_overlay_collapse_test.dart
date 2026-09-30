// 卡盒是**滚动区之上的浮层**,不在滚动流里(样机 .fx-hero__card 是 absolute + z-index:4)。
// 这条差别不是排版洁癖,它决定三件事,每件这里钉一条:
//   ① 卡片不随正文滚走 —— 在流里的话顶栏接管那一刻它已经滚出屏幕,而它 w×1.38 的
//      槽位还占着,上方就是一块空背景(样机 index.wxml:383 点名的坑)。
//   ② 收缩原点是左上角(transform-origin:0 0)—— 朝顶栏缩略图那一侧缩,不往中间飘。
//   ③ 浮层压在滚动区上,手势要能分轴:横向归卡片、竖向归正文。挡死就是半屏死区。
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/free_explore/card_detail_page.dart';
import 'package:chengyin_app/feature/play/free_explore/widgets/card_box_3d.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const PlaySessionKey _key = (activityId: 77, topicId: null);

/// 只出现在卡背的一句 —— 章节头渲的是 meta + title,不渲 description。
/// 拿它判「翻到背面了没有」,不会和正面/正文串。
const String _backOnly = '这一章讲的是唱片与旧书。';

class _Api implements PlayApi {
  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(<String, dynamic>{
        'topicId': 23,
        'mode': 2,
        'playable': true,
        'total': 1,
        'doneCount': 0,
        // 章节键照后端:name / imgArr / description,**没有** meta/title/cover。
        'chapters': <dynamic>[
          <String, dynamic>{'chapterId': 99, 'name': '晨间烘焙'},
          <String, dynamic>{
            'chapterId': 100, 'name': '旧书与唱片', 'description': _backOnly,
          },
        ],
        'nodes': <dynamic>[
          <String, dynamic>{
            'nodeId': 1, 'name': '长乐路旧物店', 'address': '长乐路 139 号', 'sortId': 1,
            'chapterId': 100, 'hookText': '你得先说出一个年份。',
            'businessTime': '11:00-20:00', 'openStatus': '营业中',
          },
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 390×640:卡盒 350×483,正文比视口高出一截,才滚得动 220 以上。
Future<void> _pump(WidgetTester t) async {
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.binding.setSurfaceSize(const Size(390, 640));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[playApiProvider.overrideWithValue(_Api())].cast(),
      child: const MaterialApp(
        home: CardDetailPage(sessionKey: _key, nodeId: 1, onPrimary: _noop),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void _noop(PlayNode _) {}

ScrollPosition _pos(WidgetTester t) => t
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// 卡盒外面最近的那个 [IgnorePointer](浮层自己套的那个)。
IgnorePointer _guard(WidgetTester t) => t.widget<IgnorePointer>(
  find
      .ancestor(
        of: find.byType(CardBox3d),
        matching: find.byType(IgnorePointer),
      )
      .first,
);

void main() {
  testWidgets('★顶栏接管时卡片仍钉在原位 —— 原来那块地方不会剩一片空背景', (WidgetTester t) async {
    await _pump(t);
    expect(t.getTopLeft(find.byType(CardBox3d)), const Offset(20, 20));
    expect(
      _pos(t).maxScrollExtent,
      greaterThanOrEqualTo(240),
      reason: '滚不到 240 这条测试就是空跑的,先把固件撑够',
    );

    _pos(t).jumpTo(240); // p = 1.09 → 夹到 1,顶栏早已接管(> 0.85)
    await t.pumpAndSettle();

    final Rect r = t.getRect(find.byType(CardBox3d));
    expect(
      r.top,
      moreOrLessEquals(20, epsilon: 0.5),
      reason: '卡盒还在滚动流里的话,这时它已经滚到屏幕外,原位留一块空背景',
    );
    expect(
      r.left,
      moreOrLessEquals(20, epsilon: 0.5),
      reason: '收缩原点不是左上角的话卡片会往中间飘,离顶栏缩略图越缩越远',
    );
    expect(
      r.height,
      lessThan(100),
      reason: '真缩了才算数:整张没缩说明 scrollTop 压根没喂进来',
    );
  });

  testWidgets('★p > 0.92 才淡出,而且同时不吃手势(样机 pointer-events:none)', (
    WidgetTester t,
  ) async {
    await _pump(t);
    expect(_guard(t).ignoring, isFalse);

    // p = 0.9:顶栏已接管(>0.85),但还没到淡出线。
    _pos(t).jumpTo(198);
    await t.pumpAndSettle();
    expect(
      _guard(t).ignoring,
      isFalse,
      reason: '0.85 到 0.92 之间卡片还在,连续淡出会让它提前变成半透明的死热区',
    );
    expect(t.widget<Opacity>(_opacityOf(t)).opacity, 1);

    _pos(t).jumpTo(220); // p = 1
    await t.pumpAndSettle();
    expect(t.widget<Opacity>(_opacityOf(t)).opacity, 0);
    expect(
      _guard(t).ignoring,
      isTrue,
      reason: '看不见还照吃点击 = 屏幕上半张是一块隐形热区',
    );
  });

  testWidgets('★浮层不挡正文:在卡片上竖着拖,滚的是正文', (WidgetTester t) async {
    await _pump(t);
    // (195, 300) 落在卡盒身上(卡盒 y 20..503),且高于底部 CTA 条。
    await t.dragFrom(const Offset(195, 300), const Offset(0, -160));
    await t.pumpAndSettle();
    expect(
      _pos(t).pixels,
      greaterThan(100),
      reason: '浮层把命中测试截断的话,卡片占的上半屏就是滚不动的死区',
    );
  });

  testWidgets('★浮层照样跟手转:在卡片上横着拖能翻到背面', (WidgetTester t) async {
    await _pump(t);
    expect(find.text(_backOnly), findsNothing, reason: '一开始是正面');
    // ry += dx * 0.8,越过 90° 需 dx > 112.5。
    await t.dragFrom(const Offset(195, 300), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(
      find.text(_backOnly),
      findsOneWidget,
      reason: '横向拖被滚动区吃掉了 —— 卡片必须仍在滚动区之上',
    );
    expect(_pos(t).pixels, 0, reason: '横向拖不该顺手把正文也滚了');
  });
}

Finder _opacityOf(WidgetTester t) => find
    .ancestor(of: find.byType(CardBox3d), matching: find.byType(Opacity))
    .first;
