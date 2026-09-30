@Tags(<String>['needs-local-env'])
// 要 git 读后端兄弟仓的 github/master ref;仓根由 test/support/backend_repo.dart 解析
// (env CHENGYIN_BACKEND → $HOME/Downloads/chengyin → /tmp/be-master),不绑死某一台机器的家目录。
// 见 .github/workflows/ci.yml:CI 上按 tag 排除。
library;

// 小程序在用、但 App 里**没有任何页面调得到**的接口清单。
//
// ★★★ 2026-08-19:我此前报过「一致性缺口 80 → 4」,那是**错的**。
//   当时的对账脚本判 App 是否接通,用的是「路径字符串在不在 lib/ 里」——
//   可路径就写在 `lib/data/api/` 的客户端方法里,于是**写了方法就恒算接通**,
//   哪怕没有任何页面调它。这是把「回执」(方法存在)当成「观测」(用户点得到)。
//   `tool/endpoint_parity.py` 已改成按可达性判，并将平台等价
//   收口为「后端存在 + App 页面可达 + 后端语义证据」三重门禁。
//
// ★ 与页面级对账的关系:页面数已经对齐(112 个页面都有对应路由),
//   缺的是**页面里的模块** —— 比如 App 有 `/club/:id`,但那页只有简介、
//   没有小程序里的动态区;有 `/merchant/ledger`,但缺对公打款批次两层。
//   页面级对账天然看不见这一层,所以两套都要留着。
//
// 这份清单的作用是**不让它悄悄烂掉**:
//   · 接通了其中一条 → 这里没删 → 红(提醒你把它从清单里划掉)
//   · 冒出新的一条 → 不在清单里 → 红(提醒你判它)
// 判据全自动来自 tool/endpoint_parity.py,人不必手抄。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_repo.dart';

/// 已知未接通、且**已经判过**的接口。清单按「缺的是哪一块」分组,
/// 而不是按接口字母序 —— 分组本身就是排期单位。
const List<String> kKnownUnreachable = <String>[
  // ══════════════════════════════════════════════════════════════
  // 2026-09-17 P18 复核(基线 origin/main@4e16d3a0,后端 github/master@1b3ca1c4):
  //   复核前实测 32 条,其中 5 条是**假红**,已随判据修复归零(见下方
  //   「假红台账」);剩下 27 条**逐条 grep 过**,分三类写在各组标题里。
  //   复核方法:`python3 -c` 直接问工具要 unreached 方法清单,再对每条端点
  //   grep 出「持有该路径字面量的方法」和「API 层之外的调用点」,不靠肉眼。
  //   ★ 同日上游前进到 efe929f1(release-0917 + play 旅程模组化),把 11 条
  //     **上游新功能**带进清单(E 组)—— 那是新缺口,不是判据回归:固定
  //     1b3ca1c4 重跑仍是 27 条(`CHENGYIN_BACKEND_REF=1b3ca1c4… python3
  //     tool/endpoint_parity.py`)。
  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // 2026-09-22 b1-reverify-round77 大收口(基线 origin/main@c419e705,真源
  //   github/master@662f7669):清单 38 条 → 1 条。#516/#518/#520/#463 合并潮 +
  //   #134/#137/#249/#251/#101/#107/#95/#114/#115/#248 的接线/⊘ 登记把 37 条
  //   关掉了 gap,但登记行散在各组没删(main 上「已接通,请划掉」判红,
  //   本单逐条点名核对后补删)。留下的唯一一条:
  //   · /api/play/scan-entry —— 此刻仍报 gap;接线在 #399(OPEN)手里,
  //     合入 main 时把这条移进 kClaimedByOpenPr 或直接划掉(见下方 r9 注释)。
  // ★ 划掉的每一行上方都有就地注释(哪条 PR 关的、用什么证据关的);
  //   「防假降」口径:37 条全部是工具实测「不再报 gap」,不是从判据里抹数。
  // ══════════════════════════════════════════════════════════════

  // ── A. 假红:页面**已在调**,只是判据认不出路径 —— 修法是让路径可枚举
  //   三个开关的调用链是真的(club_detail_page 的三个 toggle),但路径由
  //   `_toggleOpenSetting(pathTail)` 拼 `/api/club/open-settings/$pathTail`,
  //   对账按整串字面量判 ⇒ 认不出。**不是缺功能**,是路径写法不肯露字面量
  //   (该文件自己的注释就写着「接口路径必须是可枚举字面量」)。
  //   处置:#114(开放设置三端点改可枚举字面量)。
  //   ── 2026-09-22(b1-reverify-round77)划掉:#114 `cb5dcfaf` 已落地,三条
  //     改成了可枚举字面量,对账实测(github/master@662f7669)不再报 gap。

  // ── B. 假红:同文件内转调 + 同名撞车 —— `MyProjectApi.list` 转调同类的
  //   `page`,而 `page` 与 `pointsApi.page` 同名 ⇒ dup 规则要求 receiver,
  //   转调那一跳认不出。端点**真接通**(我发布的内容页走 list)。
  //   处置:#114 会再落一处调用点;工具侧的修法见下方「假红台账」末尾。
  //   ── 2026-09-22(b1-reverify-round77)划掉:#114 `cb5dcfaf` 落了
  //     club_manage_stage.dart 的 /api/project/my 调用点,对账不再报 gap。

  // ── C. 真不可达 · 由在途 PR 承接(清单留着是为了别让它悄悄烂掉;
  //   接通那条 PR 落地时,把对应行删掉,判据会红着提醒你)
  //   · R10 资金线五条:App 侧**故意不接**(提现只弹客服微信 + 复制,
  //     不做银行卡表单;club_crm_api.dart / club_settlement_page.dart 就地写明)
  //     → #115「App 侧不接」登记。
  //   ── 2026-09-22(b1-reverify-round77)划掉五条:#115 `8237756d` 已把它们
  //     做成 tool/endpoint_parity.py 的 DOCUMENTED ⊘ 条目(带 App 侧不发的证据),
  //     对账不再报 gap ⇒ 留行必被「已接通,请划掉」判红。R10 判词本体继续
  //     在脚本 ⊘ 条目里生效(App 侧 grep `/api/withdrawal/create` 仍为 0)。
  //   · 广场详情互动(评论列表/点赞/举报/删除)→ #101。
  //   ── 2026-09-22(b1-reverify-round77)划掉四条:#101 `6621133f` 接通
  //     (square_api.dart 真发 /api/comment/*),下方 09-22 a1-gap-r9 收口注释
  //     早已判撤,行没跟着删 —— 本单补删。
  //   · 招商详情页的两个供给动作 → #111 / #94。
  //   ── 2026-09-22(b1-reverify-round77)划掉三条:#134 `9fb7f029` 落地
  //     (coop_api.dart 发 circle-supply pause/reconfirm/reconfirm-current,
  //     商家承接页调用),对账不再报 gap。
  //   · 商家侧四条(撤回待审认领 / 口碑回复改删 / 客户换明文再拨)→ #107。
  //   ── 2026-09-22(b1-reverify-round77)划掉四条:#107 `09383431` 落地
  //     (claim/cancel、reviews/reply update/delete、customers/{id}/contact),
  //     对账不再报 gap。

  // ── D. 真不可达 · 无人接手,且**不是小改**(整块功能在哪边都还没做)
  //   · 创意广场整块(小程序 `pages/square/list` 内嵌编辑器 +
  //     `components/cy/profile` 的创作者入口):App 里连路径字面量都没有,
  //     两端都没有对应页面 ⇒ 属新功能,不是「补一条调用」。
  //   ── 2026-09-22(b1-reverify-round77)划掉五条:前提已变 —— #101
  //     `6621133f` 把广场互动接回旧契约(square_api.dart 真发
  //     /api/creativesquare/*),下方 09-22 a1-gap-r9 收口注释早已判撤、
  //     行没跟着删 —— 本单补删。
  //   · 首页扫码进门(小程序 `pages/index` 的-door scene,`scan-entry`):
  //     App 侧没有这个入口(有扫码页,但走的是核销/探店那条链路)。
  //   ── 2026-09-23(gap-spec-player #1)划掉:判词前提已在本分支改变 ——
  //     门口码落地页 `/door`(door_entry_page.dart)真发 POST scan-entry
  //     (`play_api.dart` scanEntry),对本分支树跑对账不再报该 gap ⇒ 行
  //     从 kKnownUnreachable 与 kClaimedByOpenPr 同时划掉(合入 main 后
  //     主线缺口 1→0)。码载体仍是拍板项(小程序码只有微信认得;App 侧
  //     靠深链带 scene)。
  //   · 招商详情页提交审核(小程序 `pages/topic/merchantinfo`):需先定 App
  //     落点,未核实 → 不编理由。
  //   ── 2026-09-22(b1-reverify-round77)划掉:#95 `660550c3` 已落点 ——
  //     page_parity_api.dart `reviewCircleInstance` 由商家主页
  //     (project_home_page.dart)调用,判词「未核实」的前提(没有落点)消失,
  //     对账不再报 gap。

  // ── E. 真不可达 · 上游 2026-09-17 新并入(release-0917 + play 旅程模组化)
  //   这 11 条来自后端仓 `1b3ca1c4..efe929f1` 的 4 个 commit。App 侧既无路径
  //   字面量、也**没有动态拼路径的等价物**(逐条 grep 过 `lib/`),两条都是
  //   「新功能没落」而不是「调用点藏起来了」。小程序调它们的页面/组件具名在下面,
  //   归各页面线;本 slice(P18)只做复核,不去别人的页面上开功能。
  //   · 俱乐部主理人运营(`pages/club/topic-detail`,App 对应
  //     `lib/data/api/club_topic_ops_api.dart` 那条线):
  //   ── 2026-09-22(b1-reverify-round77)划掉这两条(#249 `9ee91eaa` 接通):
  //   · 券停发(`subpackageMember/coupon`):App **没有券管理页**,整块未做。
  //   · 商家客户群发(`pages/merchant/customer`):App 有客户页(`merchant_customer_page`),
  //     缺群发这个动作。
  //   ── 2026-09-22(b1-reverify-round77)划掉券停发 + 群发三条:#251
  //     `28bffd6d` 收口 merchant/coupon/wallet 域(my_published_coupons_page
  //     发 coupon/stop,CRM 名册页发 broadcast/preview),对账不再报 gap。
  //   · 跨设备续玩(`utils/play-run-session`、`utils/index/continue-explore`):
  //     首页「继续探索」尚无服务端进行中会话的恢复。
  //   ── 2026-09-22(b1-reverify-round77)划掉续玩三条:#137 `7f77745c`
  //     接通 run-session save/list/clear,对账不再报 gap。
  //   · 漫游分享卡上云(`utils/roam-share-snapshot`):App 只有**本机**分享卡
  //     编码器(`BoundaryRoamShareCardEncoder`),没有快照接口。
  //   ── 2026-09-22(b1-reverify-round77)划掉漫游两条:#248 `38447022` 已把
  //     snapshot/revoke 做成脚本 ⊘ 等价(带证据),下方 09-22 收口注释早已判撤、
  //     行没跟着删 —— 本单补删。
  //   · 资金阶段(`components/cy/funds-stages`);归资金线,与 R10 那五条同源。
  //   ── 2026-09-22(b1-reverify-round77)划掉:#251 `28bffd6d` 接通
  //     /api/wallet/stages,对账不再报 gap。
  // ══════════════════════════════════════════════════════════════
  // 假红台账(P18 2026-09-17 复核;复核前实测 32 条 → 修完 27 条)
  //
  // ① 接口声明参与 dup —— **假红 4 条,已修**。
  //    `abstract interface class XGateway` 与 `class XApi implements XGateway`
  //    常写在同一文件里 ⇒ 每个方法名被数两次 ⇒ dup 规则(「同名方法会互相证明
  //    可达」)把判据从「裸名匹配」升级成「必须带 receiver」;而页面拿到的是
  //    **接口类型**(`final AdvancedPlayGateway gateway;`),`gateway.state(...)`
  //    这种真调用认不出。实测:`/api/play/advanced/{start,action,state,leaderboard}`。
  //    (#117 用「provider 改名」绕过了 game/session 那一组同源的四条 —— 只改了
  //     病例,没改判据;这次把根因修了:接口声明不算方法,接口类型也算 receiver 证据。)
  //
  // ② 小程序语料读工作区、后端路由读 ref —— **假红 1 条 + 假绿 1 条,已修**。
  //    本机镜像 checkout 在 release-0917(`7bdeb58d`,128 页),而新鲜度门禁认可的
  //    `github/master` 是 release-0916(`1b3ca1c4`,129 页)⇒ 同一次固定 commit 的
  //    对账结果随 checkout 漂移:
  //      · 假红 `/api/club/lead/edit-ops`(只在工作区有调用点);
  //      · 假绿 `/api/coop/candidates/reject`(master 的 pages/coop/list 在调,
  //        工作区那条已不在 —— 真缺口被藏掉;该条本身已由 #105 接通)。
  //    已改:小程序语料与后端路由同按 `BACKEND_REF` 读。
  //    ★ 这条负控原来断言的是「master 此刻在调哪条」,上游当天前进就红了 ——
  //      已改成**自包含判别对**(临时仓里造 ref/工作区两份不同内容),不再依赖
  //      master 恰好在调什么。
  //    ★ 上游稍后前进到 `efe929f1`,上述两条的证据基础随之移动
  //      (`edit-ops` 进了 master ⇒ 它在清单里变成**真缺口**,进 E 组;
  //      `candidates/reject` 已不在产品代码里)。台账记的是当时 ref 的事实。
  //
  // ③ 还留着一条:**同文件转调撞同名** —— `MyProjectApi.list` 转调同类的 `page`,
  //    而 `page` 与 `pointsApi.page` 同名 ⇒ 那一跳被 dup 规则挡住(B 组那条)。
  //    修法要在不动点迭代里按 owner 分组,收益 1 条、波及全部 632 条判定 ——
  //    本 PR 不动,记在这里等人认领。
  // ══════════════════════════════════════════════════════════════
  // ── 2026-09-22(a1-gap-r9 第二遍收口,pr-rebase-n)划掉:comment×4 +
  //   creativesquare×5 共 9 条(原 2026-09-18 gap-square 登记,判据为
  //   「App 做在了没合并的 v1 社区契约上」)。
  //   前提已被 main 自己的上位实现改变:**#101 `6621133f`**「广场互动/发布链路
  //   接旧契约(撤 #113 v1 社区侧,保留 #101 契约)」—— 真源核:`lib/data/api/
  //   square_api.dart:114` 发 `/api/creativesquare/info`、`:623` 发
  //   `/api/comment/list`,v1 社区侧已撤 ⇒ 这 9 条既在 mini 语料、又在 App 调用点,
  //   对账不再报 gap,留着会被「已接通,请划掉」断言判红(本单实跑逐条点名,见
  //   REPORT-a1-gap-r9 §四·C)。
  //   ⚠️ 那套判据里「等后端把 v1 合进 master 再回来接」的分支从此关闭;
  //   `test/blocked_by_backend_test.dart` 盯 master 长 `/api/v1/community` 的前提门
  //   仍在,长出来时按原判据回来复核(不是复登记这 9 条)。

  // ── 2026-09-18 登记行统一收口:登记表**只允许一个写入者**。
  //   并行线(a1-roam / a1-play / …)的判定结果集中登记在这一处,撤行也从这里撤;
  //   各分支各写一行,合并时同一段必然冲突(PR #132/#137 就是这么撞上的)。

  // ── 漫游分享卡片链(2026-09-17 判:App 侧没有合法调用方,不是没接线)
  //   小程序:卡片只能带 path,而轨迹只存在分享者本机 ⇒ 才需要服务端快照 + 令牌。
  //   打开「分享足迹卡」面板即 POST snapshot(utils/roam-share-snapshot.js:96-113;
  //   subpackageRoam/session/index.js:291,296-310),onShareAppMessage 把 token 拼进卡片 path;
  //   朋友凭令牌只读 GET(未登录可读);「清空本机缓存」时 revoke(pages/roam/index.js:5215-5220)。
  //   后端 ApiRoamShareController:同一 ts 复用同一令牌(按 memberId+clientTs),
  //   坐标平移到整数度锚点、时间只留到小时,revoke = 删行。
  //   App:/roam/session 只吃 ts(app_router.dart:1423-1426),没有任何入站链接管线
  //   (pubspec 无 app_links/uni_links、SceneDelegate 空壳、无 continueUserActivity;
  //   全仓唯一深链特例是 /merchant/team?invite=),Runner.entitlements 的 applinks
  //   只有微信登录那个域名,没有足迹落地页 ⇒ GET 这条**没有 App 侧读取方**,接了就是纯写不读。
  //   分享出口是系统分享面板里的自包含图片(roam_share_actions.dart,share_plus),
  //   没有 path 可带令牌;位置隐私闸(小程序发布前默认裁首尾各 10%、private 拒发)
  //   与「清空本机缓存」入口 App 侧都还没有(RoamSessionStore 无删除能力)
  //   ⇒ 此时发布快照就是把家门口/回家那段传服务端,revoke 也无对象可作废。
  //   判定 BLOCKED(不是缺页,是缺三件前置):Universal Link 落地页 + 裁剪/可见性设置 + 清空入口。
  //   ⚠️ 朋友「在 App 内打开这条足迹」是可做未做 —— 补上落地页时这两条必须划掉。
  //   docs/plans/2026-09-17-a1-roam-endpoints.md
  // ── 2026-09-22(a1-gap-r9 第二遍收口,pr-rebase-n)划掉:snapshot、revoke 两条。
  //   判词没被推翻,是**换了存放位置**:**#248 `38447022`**「roam 分享快照两条登记为
  //   平台差异,等价带证据」已把它们做成 `tool/endpoint_parity.py` 的
  //   `DOCUMENTED_EQUIVALENTS`(脚本 `_ROAM_SHARE_MINI_UTILS:277-279` + `EndpointEquivalent`
  //   条目,判据原文与「补上入站路由再把这两条移出」的 TODO 常驻脚本)⇒ 对账不再报
  //   gap,台账留行必被「已接通,请划掉」判红(本单实跑点名)。
  //   上面那段判据(三件前置)与「可做未做」的提醒以脚本 ⊘ 条目为准继续生效。

  // ── 2026-09-19(a1-gap-r9)从这里移走:`/api/play/scan-entry`。
  //   r9 的依据是 PR #252(feat/gap-play,当时叠进本线)把它转成
  //   `tool/endpoint_parity.py` 的 DOCUMENTED_EQUIVALENTS(⊘ App 侧不发请求,
  //   等价物是游玩页内扫码器 → /api/play/checkin)。**该依据已失效**:#252 已
  //   CLOSED、那条 ⊘ 从未进主线(主线脚本 grep `scan-entry` = 0),主线 `lib/`
  //   也仍零命中 ⇒ 对账此刻仍报 gap,行不能凭空消失。
  //   接线现在在 **本分支**(gap-spec-player #1)手里:门口码落地页 `/door`
  //   (`lib/feature/account/door_entry_page.dart`)消费 `?scene=` →
  //   POST scan-entry → 分流 /play 或 /topic,同时承接 `?inviter` 归因。
  //   码载体仍是拍板项(小程序码只有微信认得;App 侧靠深链带 scene)。
];

/// ★★ 接线已在 **OPEN PR 手里**、合入 main 前仍会出现在对账 gap 里的端点。
///   与 kKnownUnreachable 的区别:那是「没人接、已判定」,这是「已有人接、
///   等合并」。不登记的话它们会撞进「冒出了没判过的未接通接口」红 ——
///   那是假红(判定早已做过,见各 PR 与 REPORT-a1-gap-r8 §三)。
///   ⚠️ 这里**不放行判定,只放行台账差集**;对应 PR 合入 main 后 gap 关闭,
///   下面的「claimed 必须仍是 gap」断言会红,提醒来划行。划行前确认数字来自主线实跑。
const List<String> kClaimedByOpenPr = <String>[
  // ── 2026-09-22(pr-rebase-n 叠加主线)划掉 PR #251 feat/gap-merchant 那四条:
  //   #251 已以 `28bffd6d`「收口 merchant/coupon/wallet 域 4 条接口缺口」合入 main,
  //   主线 `lib/` 现在 grep 得到 coupon/stop(coupon_api.dart)、wallet/stages
  //   (withdrawal_api.dart)、merchant/crm/broadcast(,/preview)
  //   (merchant_crm_console_api.dart:208/232)⇒ gap 已关,这条反向断言此刻正是
  //   r9 设计来提醒划行的时刻(它设计时预告的假红由本次处置销账)。
  // PR #463 feat/a1-publisher-identity(RUN-52,OPEN / MERGEABLE):发布者实名登记
  //   共用件,`/api/publisher/identity/status` 真调用点在其
  //   `lib/data/api/publisher_identity_api.dart:21`(主线 `lib/` 此刻仍零命中,
  //   主线 test/tool 亦无该端点的判定 ⇒ 它属于「已有人接、等合并」而非「没判过」)。
  //   #463 合入后按同法划行。
  // ── 2026-09-23(b1-reverify-round77)划掉 #463 那条:`c419e705`「发布者实名
  //   登记共用件 + 三入口接闸(RUN-52)(#463)」已合入 main,真调用点
  //   `lib/data/api/publisher_identity_api.dart:21` 在主线树内(`git merge-base
  //   --is-ancestor c419e705 HEAD` 实测通过)⇒ 工具实测(真源
  //   `github/master@4f63025c`,未解释缺口只剩 scan-entry 1 条)不再报该 gap,
  //   「claimed 必须仍是 gap」反向断言此刻变红 —— 正是上面预告的划行时刻。
  // ── 2026-09-23(gap-spec-player #1)划掉最后一条 scan-entry:认领人 #399
  //   的接线本体就是本分支 —— 对本分支树跑对账该 gap 已关(见上 kKnownUnreachable
  //   D 组划掉注),认领清单随之清零;合入 main 后主线缺口 1→0。
];

void main() {
  test('★★ 未接通清单与实测一致 —— 接通了要划掉,新冒出来的要判', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      'tool/endpoint_parity.py',
    ], environment: backendEnvironment());
    expect(
      r.exitCode,
      0,
      reason:
          '对账脚本没跑起来:\n${r.stderr}\n'
          '★ 跑不了要判红,不能当"没缺口" —— '
          '"查不了"和"查完是 0"长得一模一样才是最危险的。',
    );

    final List<String> actual = const LineSplitter()
        .convert(r.stdout as String)
        .skip(1) // 第一行是统计
        .map((String l) => l.trim())
        .where((String l) => l.startsWith('/api/'))
        .toList();

    final RegExpMatch? summary = RegExp(
      r'未解释缺口 (\d+) 条',
    ).firstMatch(r.stdout as String);
    expect(summary, isNotNull, reason: '工具必须输出可回读的未解释缺口数');
    expect(int.parse(summary!.group(1)!), actual.length, reason: '统计与明细必须一致');

    // ★ /api/merchant/funnel 不列 here:它不是「App 没接」而是「产品根本不用」——
    //   小程序 github/master@3fa2b19 全历史产品侧零引用(唯一命中 scripts/
    //   _verify_funnel.js 是截图探针、tests/unit 那条是「产品不调它」的负断言,
    //   均被 _XCX_NON_PRODUCT 排除)⇒ 不进等价候选集,`≡` 回执恒打不出。
    //   2026-09-19 裁决删 expect(REPORT-a1-gap-close-verify-2 §四.1);
    //   funnel 数据经 marketing-home 聚合下发,App 侧续用有门禁兜底
    //   (test/blocked_by_backend_test.dart)。
    for (final String contract in <String>[
      '/api/coop/deposit/create => /api/coop/deposit/create/app + /api/coop/deposit/status',
      '/api/getwxbindphone => /api/sms/send + /api/login/phone',
      '/api/login/code => /api/login/wechat/app',
      '/api/registration/pay => /api/registration/pay/app',
    ]) {
      expect(
        r.stdout as String,
        contains('≡ $contract'),
        reason: '等价端点必须显式回执，不能从 gap 里静默消失',
      );
    }
    expect(r.stdout as String, contains('backend github/master@'));

    // `/api/merchant/funnel` 已退役 —— **小程序产品代码不再调它**:
    // `chengyinhub-xcx/tests/unit/merchant-console-identity-gate.test.js`
    // 反过来断言 `urls.includes('/api/merchant/funnel') === false`
    // (商家控制台改走 `/api/merchant/marketing-home`)。所以它既不该出现在
    // 缺口里,也不该再有等价回执;哪天它以任一种形态回来,这条会红,来核一遍。
    // (DOCUMENTED_EQUIVALENTS 里那条留作决策记录:mini 再调时它照样受三道门禁。)
    expect(r.stdout as String, isNot(contains('/api/merchant/funnel')));

    // ★ 清单里重复登记一条,会被下面的 diff 报成「已接通,请划掉」——
    //   判据说了假话,而假话的方向恰好是"你做完了"。2026-08-20 因此绕了三轮。
    expect(
      kKnownUnreachable.length,
      kKnownUnreachable.toSet().length,
      reason:
          '清单里有重复项:'
          '${kKnownUnreachable.where((String e) => kKnownUnreachable.where((String x) => x == e).length > 1).toSet()}',
    );

    final Set<String> todo = actual.toSet();

    final Set<String> known = kKnownUnreachable.toSet();
    final Set<String> claimed = kClaimedByOpenPr.toSet();
    final List<String> connected = (known.difference(todo)).toList()..sort();
    final List<String> appeared =
        (todo.difference(known).difference(claimed)).toList()..sort();
    // 在途 PR 的接线一旦合进 main,gap 会关掉 —— 那时这行就是过期的「已判」假账。
    final List<String> staleClaims = (claimed.difference(todo)).toList()
      ..sort();

    expect(
      connected,
      isEmpty,
      reason:
          '这些已经接通了,把它们从 kKnownUnreachable 里删掉:\n'
          '${connected.join('\n')}',
    );
    expect(
      appeared,
      isEmpty,
      reason:
          '冒出了没判过的未接通接口 —— 逐条判是"真缺 UI"还是'
          '"后台专用/有意不做",再决定放进清单还是去接:\n'
          '${appeared.join('\n')}',
    );
    expect(
      staleClaims,
      isEmpty,
      reason:
          'kClaimedByOpenPr 里这些端点已经不在 gap(对应 PR 已合入 main?)—— '
          '把它们从认领清单划掉:\n${staleClaims.join('\n')}',
    );
  });

  test('★★ 负控：未登记的任意小程序端点仍必须判为 gap', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
report = E.classify_endpoints(
    {'/api/negative-control/random'},
    '',
    '/api/negative-control/random',
)
assert report.gaps == ['/api/negative-control/random'], report
assert report.documented == [], report
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('★★ 负控：仅缺保证金 status 路由时等价合同必须变红', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
spec = next(s for s in E.DOCUMENTED_EQUIVALENTS
            if s.mini == '/api/coop/deposit/create')
report = E.classify_endpoints(
    {'/api/coop/deposit/create'},
    '/api/coop/deposit/create/app /api/coop/deposit/status',
    '/api/coop/deposit/create',
    equivalents=(spec,),
    backend_endpoints={
        '/api/coop/deposit/create',
        '/api/coop/deposit/create/app',
    },
)
assert report.gaps == ['/api/coop/deposit/create'], report
assert len(report.invalid) == 1, report
assert 'backend route missing:/api/coop/deposit/status' in report.invalid[0][1], report
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('★★ 默认 github/master 与远端 SHA 不同时必须 fail closed', () {
    final String local = backendMasterSha();
    final String stale = local == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/endpoint_parity.py'],
      environment: backendEnvironment(<String, String>{
        'CHENGYIN_BACKEND_REMOTE_SHA': stale,
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stderr.toString(), contains('本地 github/master 已过期'));
  });

  test('★★ 显式固定 40 位 commit 可离线审计', () {
    final String commit = backendMasterSha();
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/endpoint_parity.py'],
      environment: backendEnvironment(<String, String>{
        'CHENGYIN_BACKEND_REF': commit,
        // 固定 commit 不应读这个远端 seam，也不应访网。
        'CHENGYIN_BACKEND_REMOTE_SHA':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout.toString(), contains('backend $commit@'));
  });

  test('★★ 负控：切到 App 保证金路由落地前的后端 ref 必须变红', () {
    const String oldRef = 'e2a2008e076dbbdd77dfdbe24ff3be182e25fe85';
    final ProcessResult r = Process.runSync(
      'python3',
      <String>['tool/endpoint_parity.py'],
      environment: backendEnvironment(<String, String>{
        'CHENGYIN_BACKEND_REF': oldRef,
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout.toString(), contains('backend $oldRef@'));
    expect(
      r.stdout.toString(),
      contains('backend route missing:/api/coop/deposit/create/app'),
      reason: '旧 ref 没有路由时等价合同不得假绿',
    );

    final ProcessResult gate = Process.runSync(
      'python3',
      <String>['tool/page_parity.py'],
      environment: backendEnvironment(<String, String>{
        'CHENGYIN_BACKEND_REF': oldRef,
      }),
      stdoutEncoding: const Utf8Codec(),
      stderrEncoding: const Utf8Codec(),
    );
    expect(
      gate.exitCode,
      isNot(0),
      reason: '旧 ref 缺路由时页面端点门禁必须真红:\n${gate.stdout}',
    );
    expect(gate.stdout.toString(), contains('/api/coop/deposit/create'));
  });

  test('★★ 负控:同文件的接口声明不得参与 dup(否则真调用被判成缺口)', () {
    final ProcessResult r = Process.runSync('python3', <String>[
      '-c',
      """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
src = '''
abstract interface class DemoGateway {
  Future<void> read(int id);
  Future<void> start({required int id});
}

class DemoApi implements DemoGateway {
  Future<void> read(int id) async {
    await _post('/api/demo/read', id);
  }

  Future<void> start({required int id}) async {
    await _post('/api/demo/start', id);
  }
}
'''
decls = E._method_decls(src)
assert [name for name, _ in decls] == ['read', 'start'], decls
assert all('/api/demo/' in chunk for _name, chunk in decls), decls
""",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('★★ 负控:小程序语料必须按 ref 读 —— 工作区领先/落后都不许改判定', () {
    // ★ 2026-09-17(P18)第二版。第一版断言的是「master 此刻在调哪条端点」
    //   (`/api/coop/candidates/reject` 在 / `/api/club/lead/edit-ops` 不在)——
    //   上游当天前进到 `efe929f1` 就红了:负控自己成了漂移的受害者,和它要防的
    //   病同源。改成**自包含判别对**:临时仓里造两份内容不同的 ref 与工作区,
    //   断言语料只吃 ref 那份。不再依赖 master 恰好调了什么。
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'p18-xcx-corpus',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));

    void git(List<String> args) {
      final ProcessResult r = Process.runSync(
        'git',
        <String>['-C', sandbox.path, ...args],
        stdoutEncoding: const Utf8Codec(),
        stderrEncoding: const Utf8Codec(),
      );
      expect(
        r.exitCode,
        0,
        reason: 'git ${args.join(' ')}\n${r.stdout}${r.stderr}',
      );
    }

    void write(String relativePath, String body) {
      final File f = File('${sandbox.path}/$relativePath');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body);
    }

    write(
      'chengyinhub-xcx/pages/demo/index.js',
      "app.sendRequest({url: '/api/refonly/marker'})\n",
    );
    // 非产品目录(`/scripts/`、`/tests/` …)即使进了 ref 也必须被排除。
    write(
      'chengyinhub-xcx/scripts/probe.js',
      "app.sendRequest({url: '/api/probeonly/marker'})\n",
    );
    git(<String>['init', '-q']);
    git(<String>['add', '-A']);
    git(<String>[
      '-c',
      'user.email=p18@test',
      '-c',
      'user.name=p18',
      'commit',
      '-qm',
      'ref',
    ]);
    final ProcessResult head = Process.runSync('git', <String>[
      '-C',
      sandbox.path,
      'rev-parse',
      'HEAD',
    ], stdoutEncoding: const Utf8Codec());
    final String ref = (head.stdout as String).trim();
    expect(ref, matches(RegExp(r'^[0-9a-f]{40}$')));

    // 工作区**领先**:改掉同一文件 + 新增一个未提交文件。
    write(
      'chengyinhub-xcx/pages/demo/index.js',
      "app.sendRequest({url: '/api/worktreeonly/marker'})\n",
    );
    write(
      'chengyinhub-xcx/pages/demo/extra.js',
      "app.sendRequest({url: '/api/worktreeonly/extra'})\n",
    );

    final ProcessResult r = Process.runSync(
      'python3',
      <String>[
        '-c',
        """
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tool').resolve()))
import endpoint_parity as E
xcx = E.xcx_product_corpus()
assert '/api/refonly/marker' in xcx, 'ref 里的产品调用点没进语料 => 假绿'
assert '/api/worktreeonly/marker' not in xcx, '读了工作区改过的内容 => 判定随 checkout 漂移'
assert '/api/worktreeonly/extra' not in xcx, '工作区新增的未提交文件进了语料'
assert '/api/probeonly/marker' not in xcx, '非产品目录(/scripts/)没被排除'
""",
      ],
      environment: <String, String>{
        'CHENGYIN_BACKEND': sandbox.path,
        'CHENGYIN_BACKEND_REF': ref,
        // 固定 commit 时不该读远端 seam,更不该访网。
        'CHENGYIN_BACKEND_REMOTE_SHA':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    );
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });
}
