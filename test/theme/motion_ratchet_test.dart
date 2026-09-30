// 动效时长棘轮门禁。
//
// ★ 为什么需要它：动画中间帧不进 golden 基线，写死一个「看着差不多」的时长
//   不会被任何现有测试抓住。本轮收编前，App 侧同时存在 160/180/200/220/250
//   五种值在做同一类态切换，而小程序档位里根本没有 160 和 180。没有门禁，
//   两端手感只会一路漂移，且全程零告警。
//
// ★ 判据是**字面量**：`Duration(milliseconds: 180)` 拦，
//   `Duration(seconds: 1)` / `Duration(microseconds: 180000)` 也拦。
//   `Duration(milliseconds: base * n)` 这类算出来的不拦——那是退避、编排偏移，
//   不是设计档位。
//
// ★ 整行注释才跳过。行内 `//` 不剥——字符串里的 `https://` 会被当成注释起点，
//   同一行后面的时长就扫不到，形成假绿。CyMotion 文档里的反例是整行 `///`，
//   整行跳过仍然盖得住。
//
// ★ 白名单是双向的：新增未登记的字面量红，登记项消失了也红。后者逼着人在
//   收编之后回来更新清单，否则白名单会慢慢变成一张过期的免死金牌。
//
// ★ 要加新动效时长，去 tokens.wxss 加档位，别往白名单里加行。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `相对路径|180ms` / `相对路径|1s` / `相对路径|180us` → 允许出现的次数。
const Map<String, int> kAllowedLiterals = <String, int>{
  // 不是动效：网络、输入防抖、传感器采样、假等待
  'feature/search/search_page.dart|300ms': 1, // 搜索输入防抖，交互延迟不是动画
  'feature/club/club_customers_page.dart|300ms': 1, // 客户搜索输入防抖，交互延迟不是动画
  'feature/merchant/merchant_customer_page.dart|300ms':
      1, // CRM 客户搜索输入防抖，交互延迟不是动画
  'feature/publish/publish_pro_page.dart|400ms':
      1, // pro 编辑器草稿自动保存的写盘合并窗口,落盘节流不是 UI 过渡
  'feature/play/stillness_challenge_controller.dart|250ms': 1, // 陀螺仪采样间隔上限
  'feature/merchant/merchant_coop_profile_page.dart|500ms': 1, // 保存后的可见性停顿
  'feature/orders/payment_verifier.dart|1500ms':
      1, // 支付结果轮询间隔(真源 payment-verifier.js)
  'feature/orders/payment_verifier.dart|5000ms': 1, // 单次状态回读的请求超时
  'feature/orders/payment_verifier.dart|20000ms': 1, // 轮询总时限(网络预算,不是动画)
  // 驻留时长：决定「显示多久」，不是「动多久」
  'core/widgets/cy_native_notice.dart|2400ms': 1, // 原生提示条停留时长
  'feature/orders/payment_result_sheet.dart|2000ms': 1, // 成功面板驻留(显示多久,不是动多久)
  'core/widgets/cy_native_notice.dart|6s': 1, // 带操作的提示条最短停留
  'feature/play/play_session_page.dart|6s': 1, // 彩蛋气泡驻留时长（决定显示多久,不是动多久）
  // 具名时间轴：逐帧编排，不属于五档
  'core/widgets/status_view.dart|1400ms': 1, // 骨架屏呼吸循环
  'feature/play/pack_opening_intro.dart|2600ms': 1, // 卡包开启揭示延迟
  // 「预制人生」(subpackagePrefab) 一局玩法的调度节拍与驻留时长：逐值对齐小程序
  // 真源 `subpackagePrefab/index.js`（250/253→280、271→100、290→900、412/489→80、
  // 550→1000、215→1800、211→2200、228→50），改任何一档都会改玩法手感，
  // 不在 CyMotion 五档里，属上面「具名时间轴 / 采样节拍」一类。
  'feature/prefab/prefab_life_page.dart|50ms':
      1, // 唤醒进度条刷新节拍（真源 setInterval 50）
  'feature/prefab/prefab_life_page.dart|80ms': 2, // 走路进度推进 + 长按进度刷新（真源两处 80）
  'feature/prefab/prefab_life_page.dart|100ms':
      1, // 开机倒计时条刷新节拍（真源 setInterval 100）
  'feature/prefab/prefab_life_page.dart|280ms':
      1, // 开机输错后复位停顿（真源 setTimeout 280）
  'feature/prefab/prefab_life_page.dart|900ms': 1, // 「输入完成」后推进下一幕的停顿
  'feature/prefab/prefab_life_page.dart|1s':
      1, // 老师局 60 秒倒计时每拍（真源 setInterval 1000）
  'feature/prefab/prefab_life_page.dart|1800ms': 1, // 梦境逐条切换驻留（决定显示多久，不是动多久）
  'feature/prefab/prefab_life_page.dart|2200ms':
      1, // 梦境末条到落幕的收束时长（真源 setTimeout 2200）
  'feature/play/play_session_controller.dart|3500ms': 1, // 场次轮询节拍
  'feature/play/free_explore/story_reveal.dart|30ms': 1, // 逐字落定·慢档
  'feature/play/free_explore/story_reveal.dart|70ms': 1, // 逐字落定·快档
  'feature/play/free_explore/widgets/story_line_view.dart|500ms': 1, // 单行故事显示时长
  'feature/play/free_explore/chapter_story_page.dart|30ms': 1, // 故事开场延迟
  // 秒级：倒计时 / 轮询 / 超时 / TTL，不是 UI 过渡
  'core/analytics/tracker.dart|5s': 1, // 埋点 flush 间隔
  'core/config/env.dart|15s': 1, // 连接超时
  'core/config/env.dart|20s': 1, // 接收超时
  'feature/tickets/pass_page.dart|1s': 1, // 票面倒计时节拍
  'feature/roam/city_node_voucher_page.dart|1s': 1, // 券码倒计时节拍
  'feature/npc/npc_controller.dart|5s': 1, // NPC 气泡 TTL
  'feature/auth/auth_controller.dart|5s': 1, // 钥匙串读 token 的有界超时,不是 UI 过渡
  'feature/merchant/chapter_node_code_sheet.dart|1s':
      1, // 点位核销码倒计时节拍（对齐小程序 1s 刷新）
  'feature/merchant/merchant_customer_page.dart|1500ms':
      1, // CRM 导出状态轮询节拍（对齐小程序 1.5s）
  'feature/merchant/merchant_node_npc_page.dart|5s': 1, // 点位角色语音状态轮询
  'feature/merchant/merchant_npc_voice_page.dart|5s': 1, // 商家 NPC 语音状态轮询
  'feature/merchant/merchant_npc_avatar_page.dart|3s': 1, // NPC 形象轮询
  'feature/im/im_chat_page.dart|8s': 1, // 新消息轮询节拍（对齐小程序 im/chat 8s 轮询），不是 UI 过渡
  'feature/feed/widgets/countdown_text.dart|1s': 1, // 倒计时刷新
  'feature/coupon/coupon_code_page.dart|1s': 1, // 券码倒计时
  'feature/coupon/coupon_code_page.dart|5s': 1, // 核销轮询
  'feature/club/club_group_code_page.dart|1s': 1, // 群码倒计时
  'feature/square/square_detail_page.dart|1s': 1, // 达标轮询计时器
  'feature/play/advanced/advanced_play_sheet.dart|1s':
      1, // 倒计时刷新节拍（与 countdown_text 同档）
  'feature/activity/activity_waitlist_section.dart|50ms':
      1, // 候补名额到期后的调度补偿(在 delay 之上多等一拍再拉),不是过渡
  'feature/play/stopwatch_game_page.dart|50ms': 1, // 秒表读数刷新节拍（20Hz 计数,不是过渡）
  // playkit 整屏计时族:对时/刷新节拍与循环周期,都不是 UI 过渡
  'feature/play/advanced/fullscreen/playkit_scan_view.dart|2200ms':
      1, // 取景框扫描线循环周期(连续环境循环,不是过渡;减动效时停)
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|1000ms':
      2, // 倒计时每拍对时 + 秒表开跑 1 秒后藏数字
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|1s':
      1, // 油面每拍步长(Tween 时长,与对时钟同频,不累加)
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|50ms':
      1, // 秒表读数刷新节拍(20Hz 计数,同 stopwatch_game_page)
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|620ms':
      1, // 秒表 3-2-1 起跑每拍(具名时间轴;减动效时整段跳过)
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|4600ms':
      1, // 油面波形 A 循环周期(连续环境循环,不是过渡;减动效时停)
  'feature/play/advanced/fullscreen/playkit_timer_logic.dart|7400ms':
      1, // 油面波形 B 循环周期(与 A 不同速,避免整块像刚体)
  // 时间窗 / 媒体clamp：决定「多久内有效」「素材多长」
  'feature/map/route_preview_sheet.dart|8s': 1, // 重规划态有效期，时间窗不是动画
  // 锁屏/控制中心 MediaItem.duration 的防炸兜底:just_audio_background 的
  // fastForward/rewind/连续拖动对 `duration!` 强解包,null 会炸后台 handler。
  // 1ms 是「不可拖」哨兵值,不是动效时长。
  'feature/topic/topic_detail_page.dart|1ms': 1,
  // 屏③两条 MediaItem:节点语音导览键 + 章节背景旁白自动播。
  'feature/play/free_explore/chapter_story_page.dart|1ms': 2,
  'feature/play/advanced/advanced_play_sheet.dart|1ms': 1,
  'feature/npc/widgets/merchant_npc_chat_sheet.dart|1ms': 1,
  'feature/merchant/merchant_node_npc_page.dart|1ms': 1,
  'feature/merchant/merchant_npc_voice_page.dart|1ms': 1,
  'feature/play/free_explore/shop_npc_logic.dart|1200ms':
      1, // NPC 思考起手延迟（假等待节奏）
  'feature/play/free_explore/shop_npc_logic.dart|500ms': 1, // 语音最短时长（媒体截断下限）
  'feature/play/free_explore/shop_npc_logic.dart|60s': 1, // 语音最长时长（媒体截断上限）
  // 网络节流窗口：决定「多久内不重复拉」，不是「动多久」（#50 漫游实时）
  'feature/roam/roam_live_controller.dart|30s': 1, // 在线状态上报节流
  'feature/roam/roam_live_controller.dart|45s': 2, // 跑者与附近的局拉取节流（两处同档）
  // ⚠️ grandfather：门禁落地时已在 main 上的真过渡，属各页自己的线。
  //   收编成 CyMotion 档位后**必须删掉对应行**，双向棘轮会盯着。
  'feature/play/free_explore/shop_npc_page.dart|260ms':
      1, // 样机镜像整屏入场(.fx-npc opacity .26s)
  'feature/play/free_explore/shop_npc_page.dart|30ms':
      1, // 开页延迟（同 chapter_story_page）
  'feature/play/free_explore/shop_npc_page.dart|300ms': 2, // 问好气泡淡出/上滑
  'feature/play/free_explore/widgets/npc_message_list.dart|200ms': 1, // 消息列表滚到底
  // 整屏玩法(playkit fullscreen)：一局玩法的整段编排与采样节拍。
  // 数值与小程序原型逐值对齐(SPIN_MS / ROLL_MS / STEP_MS / TICK_MS / calibrate-ms…)——
  // 转动时长必须等于动画时长(短了提前剧透、长了空转),不在 CyMotion 五档里,属上面
  // 「具名时间轴」一类；改这里必须同时改 xcx-ref 原型对照件。
  'feature/play/advanced/fullscreen/playkit_fullscreen_parts.dart|900ms':
      1, // 摇一摇提示行摆动周期(.9s infinite,提示动画本身)
  'feature/play/advanced/fullscreen/playkit_fullscreen_sources.dart|100ms':
      1, // 安静挑战响度采样间隔(TICK_MS,采样节拍)
  'feature/play/advanced/fullscreen/coin_flip_view.dart|2200ms':
      1, // 抛硬币整段旋转(SPIN_MS),转完才落面
  'feature/play/advanced/fullscreen/coin_flip_view.dart|9000ms':
      1, // 硬币待机慢自转循环(.cf-spin 9s linear)
  'feature/play/advanced/fullscreen/dice_roll_view.dart|900ms':
      1, // 掷骰子整段翻滚(ROLL_MS),摇完才报和
  'feature/play/advanced/fullscreen/ball_shake_view.dart|16ms':
      1, // 弹球定步长物理节拍(STEP_MS)
  'feature/play/advanced/fullscreen/ball_shake_view.dart|420ms':
      1, // 撞边闪光(bl-edge 动画同值)
  'feature/play/advanced/fullscreen/ball_shake_view.dart|1200ms':
      1, // 校准台面时长(calibrate-ms)
  'feature/play/advanced/fullscreen/ball_shake_view.dart|620ms':
      1, // 3-2-1 倒计时每一拍(cy-play-countin TICK_MS)
  'feature/play/advanced/fullscreen/ball_shake_view.dart|1000ms':
      1, // 限时条读数刷新节拍(采样不是过渡)
  'feature/play/advanced/fullscreen/quiet_hold_view.dart|2000ms':
      1, // 安静校准时长(calibrate-ms=2000)
  'feature/play/advanced/fullscreen/playkit_silent_order_view.dart|1s':
      1, // 「已表演」正计时刷新节拍(真源 1s tick,不是 UI 过渡)
  'feature/play/advanced/fullscreen/playkit_prefab_views.dart|1s':
      1, // typeIn 限时表每拍对时(倒计时刷新节拍,与 playkit_timer_logic 同档,不是 UI 过渡)
};

final RegExp _literal = RegExp(
  r'Duration\(\s*(milliseconds|seconds|microseconds):\s*(\d+)\s*\)',
);

String? stripWholeLineComment(String line) {
  final String trimmed = line.trimLeft();
  if (trimmed.startsWith('//')) return null;
  return line;
}

String literalKey(String unit, String value) {
  switch (unit) {
    case 'seconds':
      return '${value}s';
    case 'microseconds':
      return '${value}us';
    default:
      return '${value}ms';
  }
}

void main() {
  test('★★ UI 动效时长必须走 CyMotion，未登记的裸时长字面量一律红', () {
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '找不到 lib/，扫描退化为空会把「查不了」伪装成通过');

    final Map<String, int> found = <String, int>{};
    int scanned = 0;

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 生成物是档位定义本身，它就该写字面量。
      if (entity.path.endsWith('cy_tokens.g.dart')) continue;
      scanned++;
      final String relative = entity.path.substring('lib/'.length);
      for (final String line in entity.readAsLinesSync()) {
        final String? code = stripWholeLineComment(line);
        if (code == null) continue;
        for (final RegExpMatch match in _literal.allMatches(code)) {
          final String key =
              '$relative|${literalKey(match.group(1)!, match.group(2)!)}';
          found[key] = (found[key] ?? 0) + 1;
        }
      }
    }

    expect(
      scanned,
      greaterThan(100),
      reason: '只扫到 $scanned 个 dart 文件，遍历可能已经失效',
    );

    final List<String> unregistered = <String>[];
    for (final MapEntry<String, int> entry in found.entries) {
      final int allowed = kAllowedLiterals[entry.key] ?? 0;
      if (entry.value > allowed) {
        unregistered.add('${entry.key} 出现 ${entry.value} 次，登记 $allowed 次');
      }
    }
    unregistered.sort();
    expect(
      unregistered,
      isEmpty,
      reason:
          '出现未登记的动效时长字面量。若是 UI 过渡，改用 CyMotion.fast /'
          ' CyMotion.standard 等档位；确属非动效再来登记：\n'
          '${unregistered.join('\n')}',
    );

    final List<String> stale = <String>[];
    for (final MapEntry<String, int> entry in kAllowedLiterals.entries) {
      final int actual = found[entry.key] ?? 0;
      if (actual < entry.value) {
        stale.add('${entry.key} 登记 ${entry.value} 次，实际 $actual 次');
      }
    }
    stale.sort();
    expect(
      stale,
      isEmpty,
      reason: '白名单有过期项，收编之后请一并删掉登记行：\n${stale.join('\n')}',
    );
  });

  test('整行注释才跳过，行内 https:// 后面的时长仍能扫到', () {
    expect(
      stripWholeLineComment('  /// 不要写 Duration(milliseconds: 180)'),
      isNull,
    );
    expect(
      stripWholeLineComment(
        "const u = 'https://x'; Duration(milliseconds: 777)",
      ),
      "const u = 'https://x'; Duration(milliseconds: 777)",
    );
  });
}
