/// 节点玩法模板族最后四件(predict / random / scan / bingo)的数据与**纯逻辑**。
///
/// 真源 = 小程序:
/// - `utils/playkit-view.js#pickPlayKit` 的 predict / random / scan 分支(字段映射);
/// - `utils/playkit-view.js#segmentComplete`(完成口径);
/// - `utils/playkit-view.js#serverPayload`(载荷换算);
/// - 各组件自己的「纯算法出口」:`_gestureOf` / `_posOf` / `_themeFor`(random)、
///   `shadeOf` / `lineCount`(bingo)、`normalizeKind`(scan)、`revealOf` / `waitLabelOf`(predict)。
///
/// 这一层**没有**任何「算出结果」的入口:押没押中、抽到什么、扫的码对不对,
/// 判定一律在服务端。这里只做字段搬运、单位/文案换算、以及手势这种有对错的纯函数
/// ——它们不需要一帧渲染,但错一步就是另一个结果。
///
/// ⚠️ bingo 是**本地 kind**(真源 `KIT_TYPES` 里有、`ACTION_OF` 里没有):
/// 它和 `walk` / `stickerBook` 一样不做服务端动作,由本地流程点名。
library;

import 'package:flutter/foundation.dart';

// ══════════════════════════════════ predict ══════════════════════════════════

/// 竞猜的一个选项。字段名逐字照抄 `pickPlayKit` 的 predict 分支:
/// `options: (seg.options || []).map((o) => ({ key: o.key, label: o.label || '' }))`。
@immutable
class PlayKitPredictOption {
  const PlayKitPredictOption({required this.key, required this.label});

  /// 服务端认的选项 id:提交时带的是它(`{optionKey: key}`),不是下标。
  final String key;
  final String label;

  static PlayKitPredictOption? from(Object? raw) {
    if (raw is! Map) return null;
    final Object? key = raw['key'];
    if (key == null || '$key'.trim().isEmpty) return null;
    return PlayKitPredictOption(
      key: '$key'.trim(),
      label: '${raw['label'] ?? ''}'.trim(),
    );
  }

  static List<PlayKitPredictOption> listFrom(Object? raw) =>
      (raw is List ? raw : const <Object?>[])
          .map(PlayKitPredictOption.from)
          .whereType<PlayKitPredictOption>()
          .toList(growable: false);
}

/// 揭晓那一块的四种态。真源 `revealOf` 把「等揭晓」和「这一轮作废了」分开说 ——
/// 对玩家是两件完全不同的事,合成一句「暂无结果」等于什么都没说。
enum PlayKitPredictReveal { wait, won, lost, voided }

@immutable
class PlayKitPredictRevealText {
  const PlayKitPredictRevealText({
    required this.kind,
    required this.head,
    required this.text,
  });

  final PlayKitPredictReveal kind;
  final String head;
  final String text;
}

/// key → 选项文案。找不到就把 key 原样回去,**不编**一个「未知选项」出来
/// (真源 `pickLabel`)。
String predictPickLabel(List<PlayKitPredictOption> options, String key) {
  for (final PlayKitPredictOption option in options) {
    if (option.key == key) return option.label;
  }
  return key;
}

/// 揭晓文案。`settleStatus` 没给(没押过 / 还没结算)返回 null —— 整块不渲染,
/// 而不是摆一个空壳。0 待揭晓 / 1 已揭晓 / 2 已作废。
PlayKitPredictRevealText? predictRevealOf({
  required Object? settleStatus,
  required String settledOption,
  required bool won,
  required List<PlayKitPredictOption> options,
  required String myOptionKey,
}) {
  if (settleStatus == null || '$settleStatus'.trim().isEmpty) return null;
  final int status = int.tryParse('$settleStatus') ?? -1;
  if (status == 2) {
    return const PlayKitPredictRevealText(
      kind: PlayKitPredictReveal.voided,
      head: '这一轮作废了',
      text: '商家没有在期限内给出答案。这一轮不发奖，你押的那一下不算数。',
    );
  }
  if (status == 1) {
    final String answer = predictPickLabel(options, settledOption);
    final String mine = predictPickLabel(options, myOptionKey);
    return won
        ? PlayKitPredictRevealText(
            kind: PlayKitPredictReveal.won,
            head: '猜中了',
            text: '答案是「$answer」，你押的就是它。',
          )
        : PlayKitPredictRevealText(
            kind: PlayKitPredictReveal.lost,
            head: '没猜中',
            text: '答案是「$answer」，你押的是「$mine」。',
          );
  }
  return const PlayKitPredictRevealText(
    kind: PlayKitPredictReveal.wait,
    head: '等商家给答案',
    text: '答案给出来之后，这里会告诉你中没中。',
  );
}

/// 什么时候揭晓。商家没配就别编一个 —— 宁可不写(真源 `waitLabelOf`,
/// 标点逐字,全角逗号是两个字符)。
String predictWaitLabelOf(String closeMode, int closeDays) {
  if (closeMode == 'DAYS') return '第 ${closeDays > 0 ? closeDays : 1} 天揭晓，到点由商家给出答案。';
  if (closeMode.isNotEmpty) return '由商家随时结算，到点给出答案。';
  return '';
}

// ══════════════════════════════════ random ══════════════════════════════════

/// 一副牌面里的一张。`drawn` 里每张 `{ id, label, content }` —— 字段名照抄
/// 组件(它把 label/content 落成卡片标题/正文)。
@immutable
class PlayKitDeckCard {
  const PlayKitDeckCard({
    required this.id,
    required this.title,
    required this.body,
    required this.opened,
  });

  final String id;
  final String title;
  final String body;

  /// 盖着的牌牌面写着「?」而不是真标题 —— 真标题此刻还没抽出来,
  /// 服务端也不会提前给(真源组件原文)。
  final bool opened;
}

/// 服务端段 → 一副牌。真源组件 `show, cards, drawn, drawCount` 观察者的
/// 线上分支:总张数取 `drawCount` 与已抽数的较大者(至少 1,不然是空屏)。
List<PlayKitDeckCard> buildRandomDeck({
  required List<Map<String, Object?>> drawn,
  required int drawCount,
}) {
  final int total = <int>[drawCount, drawn.length, 1].reduce((int a, int b) => a > b ? a : b);
  final List<PlayKitDeckCard> deck = <PlayKitDeckCard>[];
  for (int i = 0; i < total; i++) {
    final Map<String, Object?>? one = i < drawn.length ? drawn[i] : null;
    deck.add(
      PlayKitDeckCard(
        id: one == null ? 'back$i' : '${one['id'] ?? 'd$i'}',
        title: one == null ? '?' : '${one['label'] ?? ''}',
        body: one == null ? '' : '${one['content'] ?? ''}',
        opened: one != null,
      ),
    );
  }
  return deck;
}

/// 开局停在哪一张:下一张还没翻的牌,不用玩家自己滑过去(真源组件)。
int randomActiveIndex(int drawnCount, int total) {
  if (total <= 0) return 0;
  return drawnCount.clamp(0, total - 1);
}

/// 拖了这么远算不算一次甩(真源 `gestureOf`,阈值是卡宽的 22%:
/// 再小就是手抖)。`width <= 0` 时**不判**——量不到宽度就不猜。
enum PlayKitDeckGesture { next, open, none }

PlayKitDeckGesture randomGestureOf(double dx, double width) {
  if (!(width > 0)) return PlayKitDeckGesture.none;
  if (dx < -width * 0.22) return PlayKitDeckGesture.next;
  if (dx > width * 0.22) return PlayKitDeckGesture.open;
  return PlayKitDeckGesture.none;
}

/// 第 index 张相对当前这张的位置:0/1/2 是可见的三张,再往后不渲染。
/// 取模是为了循环:一副牌翻到底要能接回开头,不然最后一张之后是空屏(真源 `posOf`)。
int randomPosOf(int index, int active, int total) {
  if (total <= 0) return -1;
  final int p = (index - active + total) % total;
  return p < 3 ? p : -1;
}

/// 第 index 张的底色下标。按卡序轮转,**不按内容猜** ——
/// 同一张卡每次抽到必须同色(真源 `themeFor` / `THEMES`)。
int randomThemeIndexFor(int index) {
  final int i = index < 0 ? 0 : index;
  return i % 3;
}

// ══════════════════════════════════ scan ══════════════════════════════════

/// 商家选的回复形态。认不出就当**文字** —— 它是最保守的那种,不会凭空要权限
/// (真源 `normalizeKind`)。
enum PlayKitScanKind { text, voice, image }

PlayKitScanKind normalizeScanKind(Object? raw) {
  final String value = '${raw ?? ''}'.trim();
  if (value == '语音') return PlayKitScanKind.voice;
  if (value == '图片') return PlayKitScanKind.image;
  return PlayKitScanKind.text;
}

// ══════════════════════════════════ bingo ══════════════════════════════════

/// 八条线:三横三竖两斜(真源 `LINES`)。交叉的线各算各的 ——
/// 共用格子不代表只算一条。
const List<List<int>> kBingoLines = <List<int>>[
  <int>[0, 1, 2],
  <int>[3, 4, 5],
  <int>[6, 7, 8],
  <int>[0, 3, 6],
  <int>[1, 4, 7],
  <int>[2, 5, 8],
  <int>[0, 4, 8],
  <int>[2, 4, 6],
];

/// 棋盘深浅:`(行 + 列) % 2`。
/// ⚠️ 写成「行 + 序号」会把中间一整列涂黑 —— 原型里踩过(真源 `shadeOf`)。
bool bingoShadeIsDark(int index) =>
    ((index ~/ 3) + (index % 3)) % 2 == 1;

/// 连成几条线(真源 `lineCount`)。
int bingoLineCount(List<bool> filled) {
  int lines = 0;
  for (final List<int> line in kBingoLines) {
    bool all = true;
    for (final int i in line) {
      if (i >= filled.length || !filled[i]) {
        all = false;
        break;
      }
    }
    if (all) lines++;
  }
  return lines;
}

/// 一格的呈现数据。`how` 不是装饰:扫码格和玩法格要做的事不是一回事,
/// 不写清楚玩家会站在店门口发呆(真源组件原文)。
@immutable
class PlayKitBingoCell {
  const PlayKitBingoCell({
    required this.index,
    required this.no,
    required this.title,
    required this.how,
    required this.isScan,
    required this.filled,
    required this.inLine,
    required this.dark,
  });

  final int index;
  final int no;
  final String title;
  final String how;
  final bool isScan;
  final bool filled;

  /// 连成线的那三格:线是这个玩法的兑现点,得看得出是哪三格连上的。
  final bool inLine;
  final bool dark;
}

/// 九个格子。`cellSpecs` 每格 `{ t, how }`;只有名字的老写法走 `labels`
/// (真源组件 `show, labels, cellSpecs, filledPositions` 观察者)。
List<PlayKitBingoCell> buildBingoCells({
  required List<Map<String, Object?>> cellSpecs,
  required List<String> labels,
  required List<int> filledPositions,
}) {
  final List<bool> filled = List<bool>.generate(
    9,
    (int i) => filledPositions.contains(i),
    growable: false,
  );
  final bool anyLine = bingoLineCount(filled) > 0;
  final List<bool> inLine = List<bool>.generate(9, (int i) => false, growable: false);
  if (anyLine) {
    for (final List<int> line in kBingoLines) {
      if (line.every((int i) => filled[i])) {
        for (final int i in line) {
          inLine[i] = true;
        }
      }
    }
  }
  return List<PlayKitBingoCell>.generate(9, (int i) {
    final Map<String, Object?> spec = i < cellSpecs.length ? cellSpecs[i] : const <String, Object?>{};
    final String how = '${spec['how'] ?? ''}'.trim().isEmpty ? '走到即亮' : '${spec['how']}'.trim();
    return PlayKitBingoCell(
      index: i,
      no: i + 1,
      title: '${spec['t'] ?? (i < labels.length ? labels[i] : '')}'.trim(),
      how: how,
      // 扫码格 vs 玩法格:按「怎么点亮」里有没有「扫码」分,与原型同一条判据
      isScan: how.contains('扫码'),
      filled: filled[i],
      inLine: inLine[i],
      dark: bingoShadeIsDark(i),
    );
  }, growable: false);
}

/// 领到哪一档就报哪一档,没领到整条不出 ——
/// 默认摆一条灰的等于提前把奖亮出来,而这玩法的张力就在「还没连上」那一段。
String bingoRibbon({
  required bool full,
  required int lines,
  required String lineReward,
  required String fullReward,
}) {
  if (full) return fullReward.isEmpty ? '' : '九格全亮 · $fullReward';
  if (lines > 0 && lineReward.isNotEmpty) return '连成一条线 · $lineReward';
  return '';
}
