// 玩法(playkit)家族金图 · 批次2 —— F32–F80 那批 shot 的 App 侧。
//
// 这批 shot 的小程序路由都是 `/pages/play/index?mock=1`,判定选择器是
// `cy-playkit-*`(即「屏上是哪一个玩法组件」),所以 App 侧的对照物就是
// **同一个玩法组件**:半屏那批走 `AdvancedPlaySheet` 的卡片格(真源 v5.1),
// 整屏那批走 `fullscreen/` 各自的组件(真源 v5.2)。
//
// ★ 夹具一律按**服务端段**写,再走 `projectPlayKit` 真投影 —— 不手搓
//   `PlayKitCard`。小程序 shot 夹具用的是组件 props(`headsLabel` / `opts` /
//   `cellSpecs` 那套),照抄会让卡片渲成空壳(与 E12 同一个坑)。
//   例外只有四个**本地 kind**(walk / stickerBook / gameTimer / bingo):
//   服务端不下发它们,字段只能由宿主给,所以直接构造卡片并传参。
//
// ★ 定时器:整屏那几件一「开始」就跑 `Timer.periodic`(物理步 / 限时读数)。
//   这里只拍没有开跑的态,不推进时钟。
//
// ★ 宿主必须带 Scaffold:没有 Material 祖先时 `DefaultTextStyle` 落在
//   flutter_test 的兜底字体上,**整屏中文会全变方框**(按钮反而是好的 ——
//   goldenTheme 单独给按钮补过族名),第一版基线就这么拍坏过。
//
// 更新基准图:flutter test --update-goldens test/golden/playkit_batch2_golden_test.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_sheet.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/ball_shake_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/coin_flip_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/dice_roll_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_bingo_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_countdown_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_fullscreen_sources.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_game_timer_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_predict_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_random_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_scan_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stickerbook_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stopwatch_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timer_logic.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_walk_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/quiet_hold_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/reaction_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';

import 'golden_theme.dart';

const Size _shot = Size(390, 844);

/// 没有传感器的来源:整屏那几件会订阅摇一摇,不注入就会去碰真 MethodChannel。
class _NoAcceleration implements PlayKitAccelerationSource {
  const _NoAcceleration();

  @override
  Stream<PlayKitAcceleration> watch() =>
      const Stream<PlayKitAcceleration>.empty();
}

class _SilentAudio implements AdvancedPlayAudio {
  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<Duration> get positionChanged => const Stream<Duration>.empty();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> setUrl(String url, {MediaItem? mediaItem}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Widget _host(Widget child) => MaterialApp(
  theme: goldenTheme(),
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: const MediaQueryData(
      size: _shot,
      padding: EdgeInsets.only(top: 47, bottom: 34),
    ),
    child: Scaffold(body: child),
  ),
);

PlayKitCard _card(Map<String, Object?> segment) =>
    projectPlayKit(segment).single;

PlayKitFullscreenContext _ctx(PlayKitCard card) =>
    PlayKitFullscreenContext(card: card, enabled: true);

PlayKitCard _local(PlayKitKind kind, String title) =>
    PlayKitCard(kind: kind, title: title, detail: '');

/// 半屏那批的宿主:真源 `cy-sheet`,卡片格由页面给,这里给一个最小 controller。
Future<void> _shotSheet(
  WidgetTester tester,
  Map<String, Object?> segment,
  String goldenPath,
) async {
  final AdvancedPlayController controller = AdvancedPlayController(
    gateway: _FakeGateway(_sessionState(segment)),
    activityId: 3,
    topicId: 0,
    nodeId: 11,
  );
  addTearDown(controller.dispose);
  await controller.start();
  setGoldenViewport(tester, _shot);
  await tester.pumpWidget(
    _host(
      AdvancedPlaySheet(
        controller: controller,
        title: '玩法',
        onReadyForBase: () {},
        audio: _SilentAudio(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// 整屏那件:直接给组件,注入随件而定。
Future<void> _shotFull(
  WidgetTester tester,
  Widget view,
  String goldenPath,
) async {
  setGoldenViewport(tester, _shot);
  await tester.pumpWidget(_host(view));
  await tester.pump();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// 真源是 `cy-sheet`(半屏):贴底呈现,别让内容浮在屏顶。
Future<void> _shotBottom(
  WidgetTester tester,
  Widget view,
  String goldenPath,
) async {
  setGoldenViewport(tester, _shot);
  await tester.pumpWidget(
    _host(Align(alignment: Alignment.bottomCenter, child: view)),
  );
  await tester.pump();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

Map<String, dynamic> _sessionState(Map<String, Object?> playKit) =>
    <String, dynamic>{
      'sessionId': 7,
      'activityId': 3,
      'topicId': 0,
      'nodeId': 11,
      'status': 'RUNNING',
      'version': 1,
      'score': 0,
      'readyForBase': true,
      'config': <String, dynamic>{
        'leaderboard': <String, dynamic>{'enabled': false},
        'multiplayer': <String, dynamic>{'enabled': false},
      },
      'draws': <dynamic>[],
      'playKit': playKit,
      'multiplayer': <String, dynamic>{},
    };

void main() {
  // ── v5.1 半屏那批(F32–F41)────────────────────────────────────────
  // 真源 `pages/play/components/playkit-{timewindow,blindtaste,…}`。
  // 卡片格 = AdvancedPlaySheet 里那一段(标题 + 说明 + 1~2 个动词)。

  testWidgets('F32 时段限定玩法 · 开放窗口', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'timeWindow': <String, Object?>{
        'title': '午夜电台即将开播',
        'openFrom': '23:00',
        'openTo': '01:00',
      },
    }, 'goldens/playkit_f32_timewindow.png');
  });

  testWidgets('F33 盲品玩法 · 三步 + 三选 + 已作答', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'blindTaste': <String, Object?>{
        'title': '猜出杯里的城市气味',
        'steps': '闻香、入口、选择',
        'hint': '猫向导：别偷看，舌头比眼睛诚实',
        'xp': 30,
        'solved': true,
        'lastKey': 'B',
        'options': <Object?>[
          <String, Object?>{'key': 'A', 'label': '桂花乌龙'},
          <String, Object?>{'key': 'B', 'label': '陈皮白茶'},
          <String, Object?>{'key': 'C', 'label': '栀子冷萃'},
        ],
      },
    }, 'goldens/playkit_f33_blindtaste.png');
  });

  testWidgets('F34 沉默点单 · 规则 + 进行时', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'silentOrder': <String, Object?>{
        'title': '不用说话完成一次点单',
        'rule': '只能用手势和表情，店员猜中后扫描见证码。',
      },
    }, 'goldens/playkit_f34_silentorder.png');
  });

  testWidgets('F35 作品命名 · 已填名称', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'diyName': <String, Object?>{
        'title': '给刚完成的咖啡拉花起名',
        'name': '黄昏潮汐',
        'maxLength': 16,
      },
    }, 'goldens/playkit_f35_diyname.png');
  });

  testWidgets('F36 音乐角 · 到点 + 曲名 + 现场提示', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'musicCorner': <String, Object?>{
        'title': '在河岸听完这一首',
        'trackName': '晚风经过苏州河',
        'durationSeconds': 240,
        'audioUrl': 'https://example.invalid/audio/wanfeng.mp3',
      },
    }, 'goldens/playkit_f36_musiccorner.png');
  });

  testWidgets('F37 计步玩法 · 当前步数 + 目标', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'steps': <String, Object?>{
        'todaySteps': 4286,
        'goal': 6000,
        'reached': false,
      },
    }, 'goldens/playkit_f37_steps.png');
  });

  testWidgets('F38 贴纸图鉴 · 已收集 + 分类 + 未解锁格', (WidgetTester tester) async {
    await _shotBottom(
      tester,
      PlayKitStickerBookView(
        data: _ctx(_local(PlayKitKind.stickerBook, '城市贴纸册')),
        eyebrow: '我的城市贴纸',
        total: 4,
        categories: const <PlayKitStickerCategory>[
          PlayKitStickerCategory(key: 'all', label: '全部'),
          PlayKitStickerCategory(key: 'river', label: '河岸'),
          PlayKitStickerCategory(key: 'street', label: '街巷'),
        ],
        activeCategory: 'all',
        stickers: const <PlayKitSticker>[
          PlayKitSticker(id: 1, label: '外白渡桥', color: '#2F6FB2'),
          PlayKitSticker(id: 2, label: '河畔邮筒', color: '#3E8E6E'),
          PlayKitSticker(id: 3, label: '梧桐树影', color: '#B2882F', isNew: true),
        ],
      ),
      'goldens/playkit_f38_stickerbook.png',
    );
  });

  testWidgets('F39 今日城市签 · 打印机出票 + 上一个人的留言', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'dailySign': <String, Object?>{
        'lines': <Object?>['巷口那家豆浆七点才开', '别去早了'],
        'signer': '阿May',
        'textMax': 40,
      },
    }, 'goldens/playkit_f39_dailysign.png');
  });

  testWidgets('F40 限时玩法 · 完成读数 + 奖励', (WidgetTester tester) async {
    await _shotBottom(
      tester,
      PlayKitGameTimerView(
        data: _ctx(
          const PlayKitCard(
            kind: PlayKitKind.gameTimer,
            title: '一分钟找出三处年份',
            detail: '你在旧楼立面找到了 1932、1986 和 2010。',
            eyebrow: '限时挑战',
            durationSeconds: 60,
            complete: true,
          ),
        ),
        state: PlayKitGameTimerState.result,
        remainingSeconds: 18,
        statusLabel: '挑战完成',
        chips: const <String>['+40 EXP', '观察力 +1'],
      ),
      'goldens/playkit_f40_gametimer.png',
    );
  });

  testWidgets('F41 跨日慢任务 · 已兑现内容', (WidgetTester tester) async {
    await _shotSheet(tester, <String, Object?>{
      'slowTask': <String, Object?>{
        'title': '把一张街景留到明天再看',
        'started': true,
        'claimed': true,
        'daysLeft': 0,
        'unlockText': '同一扇窗，在两天的光里有了完全不同的颜色。',
      },
    }, 'goldens/playkit_f41_slowtask.png');
  });

  // ── v5.2 整屏那批(F55 / F63–F80)──────────────────────────────────
  // 真源 `pages/play/components/playkit-*`;这些配件压在半屏里「整屏就是判定区」
  // 「墙就是手机的四条边」当场不成立,所以 App 也走整屏组件。

  testWidgets('F55 变色就点 · 开局前整屏是判定区', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitReactionView(
        data: _ctx(
          _card(<String, Object?>{
            'reaction': <String, Object?>{
              'kicker': '变绿就点',
              'rounds': 3,
              'goalMs': 320,
            },
          }),
        ),
        random: () => 0,
      ),
      'goldens/playkit_f55_reaction_idle.png',
    );
  });

  testWidgets('F63 分支剧情 · 正文 + 两条路径', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitBranchView(
        data: _ctx(
          _card(<String, Object?>{
            'branch': <String, Object?>{
              'currentStep': <String, Object?>{
                'id': 's1',
                'title': '钟楼下的岔路',
                'body': '雨停了。左边巷子传来烤面包的味道，右边是往河堤去的石阶。',
                'options': <Object?>[
                  <String, Object?>{'id': 'o1', 'label': '拐进巷子'},
                  <String, Object?>{'id': 'o2', 'label': '走上石阶'},
                ],
              },
            },
          }),
        ),
      ),
      'goldens/playkit_f63_branch.png',
    );
  });

  testWidgets('F64 猜数字 · 答案不下发,揭晓时间写在屏上', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitEstimateView(
        data: _ctx(
          _card(<String, Object?>{
            'estimate': <String, Object?>{
              'question': '这棵树有多少岁?',
              'unit': '年',
              'min': 0,
              'max': 400,
              'maxTries': 3,
            },
          }),
        ),
      ),
      'goldens/playkit_f64_estimate.png',
    );
  });

  testWidgets('F65 猜图 · 四项名字落在色块外面', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitPricePairView(
        data: _ctx(
          _card(<String, Object?>{
            'pricePair': <String, Object?>{
              'title': '哪一张是这家店的招牌?',
              'maxTries': 3,
              'items': <Object?>[
                <String, Object?>{'id': 'a', 'name': '冰美式'},
                <String, Object?>{'id': 'b', 'name': '燕麦拿铁'},
                <String, Object?>{'id': 'c', 'name': '单一产地手冲'},
                <String, Object?>{'id': 'd', 'name': '海盐芝士奶盖'},
              ],
            },
          }),
        ),
      ),
      'goldens/playkit_f65_pricepair.png',
    );
  });

  testWidgets('F66 找东西 · 只给待找清单,不给坐标', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitHiddenView(
        data: _ctx(
          _card(<String, Object?>{
            'hiddenObject': <String, Object?>{
              'title': '找出画面里的三只猫',
              'imageUrl': 'https://example.invalid/scene/cats.png',
              'total': 3,
              'targets': <Object?>[
                <String, Object?>{'id': 't1', 'label': '窗台上的'},
                <String, Object?>{'id': 't2', 'label': '柜子后的'},
                <String, Object?>{'id': 't3', 'label': '门口的'},
              ],
            },
          }),
        ),
      ),
      'goldens/playkit_f66_hidden.png',
    );
  });

  testWidgets('F67 竞猜 · 押完不当场出结果', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitPredictView(
        data: _ctx(
          _card(<String, Object?>{
            'predict': <String, Object?>{
              'question': '明天哪款会卖得最好?',
              'hint': '押一个，商家给答案时揭晓。',
              'options': <Object?>[
                <String, Object?>{'key': 'A', 'label': '冰美式'},
                <String, Object?>{'key': 'B', 'label': '燕麦拿铁'},
                <String, Object?>{'key': 'C', 'label': '桂花冷萃'},
              ],
            },
          }),
        ),
      ),
      'goldens/playkit_f67_predict.png',
    );
  });

  testWidgets('F68 抽卡 · 两张已开 + 剩一张没翻', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitRandomView(
        data: _ctx(
          _card(<String, Object?>{
            'random': <String, Object?>{
              'title': '城市盲盒',
              'deckName': '老城卡池',
              'drawCount': 3,
              'drawn': <Object?>[
                <String, Object?>{
                  'id': 'c1',
                  'label': '行动',
                  'content': '去找一扇蓝色的门',
                },
                <String, Object?>{
                  'id': 'c2',
                  'label': '加成',
                  'content': '和同行者交换一个发现',
                },
              ],
            },
          }),
        ),
      ),
      'goldens/playkit_f68_random.png',
    );
  });

  testWidgets('F69 九宫格 · 第一行已连成线', (WidgetTester tester) async {
    await _shotBottom(
      tester,
      PlayKitBingoView(
        data: _ctx(_local(PlayKitKind.bingo, '这周的九宫格')),
        title: '这周的九宫格',
        cellSpecs: const <Map<String, Object?>>[
          <String, Object?>{'t': '老张咖啡', 'how': '扫码到店'},
          <String, Object?>{'t': '猜豆子数量', 'how': '估数题'},
          <String, Object?>{'t': '巷口书店', 'how': '扫码到店'},
          <String, Object?>{'t': '哪杯最贵', 'how': '比价连击'},
          <String, Object?>{'t': '找三只猫', 'how': '找东西'},
          <String, Object?>{'t': '今日销冠', 'how': '竞猜转盘'},
          <String, Object?>{'t': '第一声钟', 'how': '到点打卡'},
          <String, Object?>{'t': '石碑拓印', 'how': '拍照题'},
          <String, Object?>{'t': '河岸邮筒', 'how': '扫码到店'},
        ],
        filledPositions: const <int>[0, 1, 2],
      ),
      'goldens/playkit_f69_bingo.png',
    );
  });

  testWidgets('F70 扫码参与 · 扫完即完成', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitScanView(
        data: _ctx(
          _card(<String, Object?>{
            'scan': <String, Object?>{
              'title': '扫一扫',
              'kind': '文字',
              'reply': '欢迎来到这家店，今天的手冲是耶加雪菲。',
            },
          }),
        ),
      ),
      'goldens/playkit_f70_scan.png',
    );
  });

  testWidgets('F71 低碳行动 · 步数只能同步不能填', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitWalkView(
        data: _ctx(
          const PlayKitCard(
            kind: PlayKitKind.walk,
            title: '低碳行动',
            detail: '',
            maxLength: 6000,
          ),
        ),
        steps: 4286,
        syncAvailable: true,
      ),
      'goldens/playkit_f71_walk.png',
    );
  });

  testWidgets('F72 抛硬币 · 结果落在正面', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitCoinFlipView(
        data: _ctx(
          _card(<String, Object?>{
            'coinFlip': <String, Object?>{
              'kicker': '抛一次，认结果',
              'heads': <String, Object?>{'label': '正面', 'action': '这杯店家请'},
              'tails': <String, Object?>{'label': '反面', 'action': '这杯你请'},
              'side': 'HEADS',
              'flipped': true,
            },
          }),
        ),
        accelerationSource: const _NoAcceleration(),
        random: math.Random(1),
      ),
      'goldens/playkit_f72_coinflip_heads.png',
    );
  });

  testWidgets('F73 掷骰子 · 两颗同色只报点数和', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitDiceRollView(
        data: _ctx(
          _card(<String, Object?>{
            'diceRoll': <String, Object?>{
              'kicker': '掷到几就做第几件事',
              'diceCount': 2,
              'pips': <Object?>[5, 4],
              'faces': <Object?>[
                '跟店员说一句今天的天气',
                '把桌上的花挪个位置',
                '给同行的人读一段菜单',
                '找出店里最旧的那件东西',
                '换一个座位坐下',
                '替下一位客人点一杯',
              ],
            },
          }),
        ),
        accelerationSource: const _NoAcceleration(),
      ),
      'goldens/playkit_f73_diceroll_two.png',
    );
  });

  testWidgets('F74 弹球 · 墙是四条边,计数与剩余秒数在顶部', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitBallShakeView(
        data: _ctx(
          _card(<String, Object?>{
            'ballShake': <String, Object?>{
              'kicker': '撞够 30 次',
              'goal': 30,
              'timed': true,
              'seconds': 12,
            },
          }),
        ),
        accelerationSource: const _NoAcceleration(),
        random: math.Random(5),
      ),
      'goldens/playkit_f74_ballshake_idle.png',
    );
  });

  testWidgets('F75 安静挑战 · 数字与底色都在说别出声', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitQuietHoldView(
        data: _ctx(
          _card(<String, Object?>{
            'quietHold': <String, Object?>{
              'kicker': '别出声',
              'sub': '声音过线就从头再来。',
              'seconds': 15,
            },
          }),
        ),
      ),
      'goldens/playkit_f75_quiethold_idle.png',
    );
  });

  testWidgets('F76 倒计时 · 白底一钟油', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitCountdownView(
        data: _ctx(
          _card(<String, Object?>{
            'countdown': <String, Object?>{
              'kicker': '倒计时',
              'seconds': 90,
              'doneText': '时间到。',
            },
          }),
        ),
      ),
      'goldens/playkit_f76_countdown_idle.png',
    );
  });

  testWidgets('F77 精准停表 · 容差写在屏上', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitStopwatchView(
        data: _ctx(
          _card(<String, Object?>{
            'stopwatch': <String, Object?>{
              'kicker': '盲停',
              'targetSeconds': 10,
              'toleranceMs': 300,
              'tries': 3,
            },
          }),
        ),
      ),
      'goldens/playkit_f77_stopwatch_idle.png',
    );
  });

  testWidgets('F78 选项问答 · 发丝线的行不是卡片', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitQaView(
        data: _ctx(
          _card(<String, Object?>{
            'qa': <String, Object?>{
              'mode': 'PICK',
              'title': '石碑上的图案象征什么?',
              'lead': '向店员领一份盲品小样，闭眼尝一口',
              'maxTries': 3,
              'options': <Object?>[
                <String, Object?>{'id': 'a', 'label': '丰收'},
                <String, Object?>{'id': 'b', 'label': '远航'},
                <String, Object?>{'id': 'c', 'label': '守护'},
              ],
            },
          }),
        ),
      ),
      'goldens/playkit_f78_qa_pick.png',
    );
  });

  testWidgets('F79 文字问答 · 答案框是这一屏的主体', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitQaView(
        data: _ctx(
          _card(<String, Object?>{
            'qa': <String, Object?>{
              'mode': 'TYPE',
              'title': '这座桥建于哪一年?',
              'maxTries': 3,
            },
          }),
        ),
      ),
      'goldens/playkit_f79_qa_type.png',
    );
  });

  testWidgets('F80 拍照打卡 · 提示词大字摆在正中', (WidgetTester tester) async {
    await _shotFull(
      tester,
      PlayKitQaView(
        data: _ctx(
          _card(<String, Object?>{
            'qa': <String, Object?>{
              'mode': 'SHOT',
              'title': '在这棵树下拍一张',
              'shotLead': '和这棵古树合个影',
            },
          }),
        ),
      ),
      'goldens/playkit_f80_qa_shot.png',
    );
  });
}

/// 最小网关:只回答 start(state),这张快照不需要第二个动作。
class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway(this._stateJson);

  final Map<String, dynamic> _stateJson;

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => AdvancedPlayState.fromJson(_stateJson);

  @override
  Future<AdvancedPlayState> state(int sessionId) async =>
      AdvancedPlayState.fromJson(_stateJson);

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async => AdvancedPlayState.fromJson(_stateJson);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('快照不需要: $invocation');
}
