@Tags(<String>['needs-local-env'])
// ★★ 2026-09-05 补标 needs-local-env(此前漏标):本文件读 backendRepoPath() ——
//   仓库**外**的兄弟后端仓。dart_test.yaml 对该 tag 的定义就是「依赖本机的兄弟仓
//   (后端 / 小程序)、本机脚本或注入的密钥」,同类的 endpoint_reachability /
//   page_parity 一直是标着的,这三个是漏网。
//
//   ⚠️ 漏标的真实代价不是「多跑几条」:自托管 runner 与开发机是**同一台**,
//   所以 CI 上这些文件不会 skip,它们会去读 ~/Downloads/chengyin —— 那个仓有 16 个
//   worktree、内容随开发者切分支而变。CI 的绿因此取决于「此刻那个仓在哪个分支」,
//   而这既不可复现也没人会想到去查。2026-09-05 实测:CI 里 flutter test 跑完
//   2915 条后进程不退出、静默到 30 分钟超时,而同一条命令在同一个 workspace
//   手动跑 2 分 01 秒全过 —— 未报结果的正是这三个文件(23 条,与差额逐条吻合)。
//
//   本地仍照跑(开发机有那个兄弟仓),CI 上按 tag 排除。
library;

// App 侧仍受后端落库缺口阻塞的清单。
//
// 后端接受字段但不落库时，前端不能摆一个假入口。
//
// ★ 为什么要有这张表:端点对账会把这些标成「App 没接」,
//   但**接了也没用** —— 硬接进去只会做出一个点了必失败的按钮。
//   不记下来的话,下一轮对账还会把它们再翻出来一次,然后再判断一次。
//
// 每条必须写清:缺什么、为什么现在接不了、需要后端做什么。
// 这道闸盯的是**前提有没有变**:后端一旦补上,这里就会红,提醒去接。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_repo.dart';

/// 后端仓库路径(与 App 仓库并列)。
final String _kBackend = backendRepoPath();

void main() {
  test('★ 商家券统计/经营漏斗:已被 marketing-home 聚合覆盖,不必单接', () {
    // 端点对账显示 `/api/merchant/coupon-summary` 与 `/funnel` 未接。
    // 查下去发现**不该接**:
    //   MerchantAggregateReadServiceImpl.marketingHome:250-252
    //     result.put("coupons", couponStats(memberId));
    //     result.put("funnel",  funnel(memberId));
    // App 的营销页走的正是 `/api/merchant/marketing-home`,
    // 那两条单条接口给的是**同一份数据**。再接一遍 =
    // 同一屏打两次网络 + 多一条会和聚合结果漂移的解析路径。
    //
    // ⚠️ 前提检查:聚合接口一旦不再包含它们,这条就该红,提醒去单接。
    final File impl = File(
      '$_kBackend/chengyinhub-system/src/main/java/com/chengyinhub/'
      'business/service/impl/MerchantAggregateReadServiceImpl.java',
    );
    if (!impl.existsSync()) {
      markTestSkipped('后端仓库不在预期路径,跳过前提核对');
      return;
    }
    final String src = impl.readAsStringSync();
    expect(
      src.contains('"coupons"'),
      isTrue,
      reason:
          'marketing-home 不再聚合 coupons —— '
          '请单独接 /api/merchant/coupon-summary,并删掉本条记录',
    );
    expect(
      src.contains('"funnel"'),
      isTrue,
      reason:
          'marketing-home 不再聚合 funnel —— '
          '请单独接 /api/merchant/funnel,并删掉本条记录',
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 由 worker t2-merchant-recruit 在做招商链路时发现,我逐条核实属实。
  // 都不在 App 侧,但**记在这里**:报告会丢,代码不会。

  test('★★ 探索值输入框**故意不做** —— 后端校验它却从不落库', () {
    // ChapterMerchantNodeServiceImpl.submit:
    //   · 校验在(:293)`if (cap != null && draft.getXpValue() > cap) throw`
    //     —— 超上限还会拒
    //   · 但 submit 往 toSave 上设了 12 个字段,**唯独没有 setXpValue**
    // ⇒ 商家填的探索值:验了、拒了、**然后丢掉**,DB 里那列纹丝不动。
    //   小程序 pages/publish/temp 那个输入框因此是**假的**。
    //
    // ⇒ App 不做这个输入框。做了就是让商家填一个注定不生效的数,
    //   而且他还会以为自己配置了奖励。
    //
    // ⚠️ 观测:后端补上落库(出现 setXpValue)后这条就该红,提醒回来做输入框。
    final File impl = File(
      '$_kBackend/chengyinhub-system/src/main/java/com/chengyinhub/'
      'business/service/impl/ChapterMerchantNodeServiceImpl.java',
    );
    if (!impl.existsSync()) {
      // 后端仓不在手边时不做断言 —— 但也不能静默通过。
      markTestSkipped('后端仓不可见,跳过');
      return;
    }
    final String src = impl.readAsStringSync();
    expect(
      src.contains('getXpValue'),
      isTrue,
      reason: '连校验都没了 —— 这条记录的前提变了,重新核一遍',
    );
    expect(
      src.contains('setXpValue'),
      isFalse,
      reason:
          '后端开始落库探索值了 —— '
          '现在可以在 App 的节点提交表单里做这个输入框,并删掉本条记录',
    );
  });

  test('★★ 广场核心互动使用小程序同源契约，后端旧控制器仍可用', () {
    const String creativeSquareController =
        'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/'
        'ApiCreativeSquareController.java';
    const String commentController =
        'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/'
        'ApiCommentController.java';
    final String? square = backendSource(creativeSquareController);
    final String? comments = backendSource(commentController);
    if (square == null && comments == null) {
      markTestSkipped('后端仓不可见,跳过前提核对');
      return;
    }
    expect(square, contains('@RequestMapping("/api/creativesquare")'));
    expect(comments, contains('@RequestMapping("/api/comment")'));
    final String app = File('lib/data/api/square_api.dart').readAsStringSync();
    for (final String path in <String>[
      '/api/creativesquare/info',
      '/api/creativesquare/like',
      '/api/creativesquare/report',
      '/api/creativesquare/delete',
      '/api/creativesquare/action',
      '/api/comment/list',
      '/api/comment/like',
      '/api/comment/report',
      '/api/comment/delete',
    ]) {
      expect(app, contains("'$path'"), reason: '核心互动应保持小程序同源契约');
    }
  });
}
