#!/usr/bin/env python3
"""文案一致性对账:小程序页面上写死的中文,App 里有没有。

★ 用户的要求是「UI 全部和小程序一样」。页面对账只能回答「有没有这个面」,
  回答不了「面上写的是不是同一件事」。文案是**能自动化的那部分内容等价**:
  同一个产品的同一个面,提示语、空态、按钮字应该是同一套。

★★ 它是**线索不是判决**。命中率低有三种可能,只有第一种是缺口:
  ① App 真的少了这块内容
  ② App 有意换了说法(如小程序的过渡告知页,App 用户从没有过旧流程)
  ③ 文案是运行时拼的,静态抽不到
  ⇒ 所以它**不设阈值判红**,只排序输出给人看。设一个阈值当门禁,
    第二类会天天误报,最后没人看 —— 那比没有更坏。

★ 覆盖面:app.json 注册的**每一页**都要落进一个明确判据(比对 / 已核 / 无静态文案 /
  系统承载),不留「未比」黑箱 —— 黑箱的代价是 106 页没人看得见,而看不见不等于对齐。

跑法: python3 tool/copy_parity.py [--min N] [--judged]
"""
import json
import re
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import endpoint_parity as E
import page_parity as P


# 系统性差异:多页共有、**同一个原因**、且原因在 App 侧无解。
# 逐页重复报它们会淹掉真信号,所以在这里统一剔除并写明理由。
# ⚠️ 剔除的是**噪音不是问题** —— 每条都要写清阻塞在哪,以及解开后要做什么。
_SYSTEMIC = {
    '分享': (
        '小程序用微信原生 open-type="share"(分享成小程序卡片)。App 两条路都堵着:\n'
        '      ① 微信分享要 fluwx + **移动应用 appid**,而 appid 仍是占位;\n'
        '      ② 系统分享面板只能分享链接,而 **没有落地页** ——\n'
        '         https://api.example.invalid/ 服务的是后台管理系统 SPA\n'
        '         (标题「城瘾小程序管理系统」),/topic/1 返回 200 是 SPA 兜底路由,\n'
        '         不是真的主题页。分享出去会把人带到后台。\n'
        '      ⇒ 两个前置都不是代码能解的。appid 到手且有公网详情页后再做。'),
}


# 已逐页核过的。★ 每条必须写**判成什么**,不能只写「看过了」——
# 空理由等于没判,而带着空理由的条目会让下一轮直接跳过它。
_JUDGED = {
    'pages/coop/withdraw/index':
        '小程序那页是「提现方式已调整 / 改为联系平台客服线下处理」的**过渡告知页**'
        '(唯一动作=弹平台客服微信);App 的 /withdrawal 入口按 R10 同样只弹客服号弹窗,'
        '两端口径已一致。有意不做。',
    'pages/mylike/mylike':
        '**真问题,已修**:标题叫「我的喜欢」而空态写「还没有收藏」,一页两个名字;'
        '且缺「取消收藏」。已统一为收藏并补上动作。剩余为措辞差异。',
    'pages/square/detail/index':
        '**真缺口,已补两次**:① 回复具体某条评论(commentApi 缺 reply_id);'
        '② 文案批次(09-18)按原文对齐 46%→86% —— 错误态「动态没能加载出来」、'
        '评论空态「还没有评论 / 说说你对这条动态的想法吧」、'
        '「评论没能加载 / 网络可能不稳定，已发布的评论不会丢失」、'
        '续页「正在加载更多评论…」+「更多评论没有加载出来」、'
        '发送态「发送中 / 正在发送评论」、失败态「评论内容仍保留在输入框」'
        '(回复态同款)、「举报评论」、输入框 aria「评论内容，输入后按键盘发送键提交」。'
        '剩余 4 条同属**「帖子已删/不存在」那一族**('
        '没有找到这条动态 / 这个链接可能已失效… / 这条动态暂不可用 / 它可能已被删除…)——'
        'App 只有一种错误态。要按原文分家,得先知道后端对已删帖返回什么码,'
        '而 community 系列不在 /tmp/be-master 的 Java 仓里、也不在 endpoint_parity 清单,'
        '本机看不到契约;猜一个 404 会把网络故障显示成「已被删除」,'
        '那是关于用户内容的错误事实陈述(同「余额没取到 ≠ ¥0.00」那条纪律)。'
        '契约到手后:info(id) 的错误码分家 + cy-empty 的两段原文。分享见系统性差异。',
    'subpackageMember/complaint/index':
        '**真缺口,已补**:联系方式(拼进 reason,后端没有独立字段)。其余措辞差异。',
    'subpackageMember/signup/index':
        '**真问题,已修**:票夹在滤掉 ① 经典定向(08-18 范围裁决残留,'
        '08-19 已被推翻)——玩家付了钱看不到票。',
    'pages/coop/nearby/index': '措辞差异;附近商家页功能对齐。',
    'pages/activity/official-inbox/index':
        '措辞差异(「接受职责」vs「接受」);承接邀约页功能对齐。',
    'pages/merchant/decor/story/index': '已对齐 /merchant/decor/story 独立全屏编辑器。',
    'pages/merchant/decor/gallery/index': '已对齐 /merchant/decor/gallery 独立相册页。',
    'pages/templatedetail/templatedetail':
        '**真缺口,已补**:App 详情页原来只有 3 块(说明/场地/物料),小程序有 13 块。'
        '后端 CmsMemberTemplate 一直在下发 ruleInstructions/storyText/storyImg/'
        'validationMethod,是 App 模型只解析了列表要用的字段。已补简介/规则说明/'
        '在哪用/怎么验证/创作者说。剩余(节点预览/试玩验证)要节点数据,另议。',
    'pages/publish/simple/index':
        '**真缺口,已补**:AI 起草(/api/ai/theme/draft)。三条纪律见 ai_draft_logic.dart。',
    'pages/activity/list/index':
        '⚠️ **同名不同物**:小程序那页是**官方活动**(scene-registry title:官方活动),'
        '不是活动目录。App 的 /activities 走 /api/activity/list 是另一回事。'
        '**已补** /official-events 列表页。',
    'pages/coop/invite/index':
        '入口模型不同(有意):App 从**路线**进(/coop/invite/:topicId,topicId 是路由参数),'
        '小程序在页内选主题。①②③ 编号与「先发布主题」空态随之不适用。'
        '页内选**邀请对象**这一步 App 已补(coop_target_picker)。',
    'pages/topic/merchantapply/index':
        '**已补**:「报名成功不等于中标」的预期管理(招商是竞争位,'
        '只说「等待审核」商家会按「已拿下」去排期备货)。'
        '「场地实拍照片」在 App 走商家资料的相册,不在申请表单里重复收。'
        '其余(申请说明/点位配置)App 在 merchant_recruit_sheets 有,措辞差异。',
    'pages/template/index': 'App 有 /templates 玩法目录,措辞与分区差异。',
    'subpackageA/pages/infomation/infomation': 'App 有 /infomation/:id 与玩法目录,措辞差异。',
    'pages/coop/list/index':
        '**本轮已补**接受/拒绝/取消三个动作与「选谁」选择器;'
        '「候选池 ›」入口 App 在 /coop/candidates/:topicId 有。措辞差异。',
    'subpackageRoam/session/index': 'App 有 /roam/session 回看页(三态分家),措辞差异。',
    'subpackageB/pages/im/chat/index':
        '**已补**:聊天里发路线卡片(kMsgCard 与 ChatMessage.extraJson 一直都在,'
        '是 ImApi.send 没有 extra_json 参数 —— 又一次「模型支持、链路断一节」)。'
        '复用 /api/topic/list 零新端点。其余措辞差异。',
    'pages/merchant/coop-center/index':
        '核过**不是**缺口:「历史邀约,仅供查看」App 已做 —— MerchantInvite.actionable '
        '为假时留在列表里只显 stateText、不摆按钮(模型注释:「摆了点下去必然失败」)。'
        '⚠️ 我看到接受后只弹 toast 就判成「处理完就消失了」—— 今天第四次同型,'
        '已记进 memory feedback-read-past-the-first-matching-fragment。',
    'subpackageP3/pages/growthcenter/leaderboard/index':
        '核过**不是**缺口:App 已分三档 —— BoardFailureKind.notice(榜没开,不给重试)/'
        'error(真故障,给重试)/ _EmptyBoard(没人上榜),注释里写着和小程序同样的判断。'
        '⚠️ 我看到「排行榜加载失败」就下结论,没往下读 data 分支 —— 今天第三次同型。',
    'pages/talent/list/index':
        '这页是**俱乐部主页**(接口是 club/home·members·post/feed)。'
        'App 对应 /club/:id,成员管理在 club_member_actions、邀约在合作中心。措辞差异。',
    'pages/square/list/index':
        '**文案批次已对齐(09-18),38%→80%**:错误态「加载失败 / 网络开了点小差，请稍后再试」、'
        '空态「广场还很安静 / 成为第一个发布创意路线的人吧」、'
        '续页「正在加载更多动态…」+ 失败改**原地**内联条「更多动态没有加载出来」'
        '(原先只弹 toast,用户看不见列表为什么没变长)、'
        '输入框「帖文内容」/ 图「删除这张图片」/ 地点「清除已选地点」/' 
        '入口「展开完整编辑页」四个 aria。'
        '剩余 4 条为**结构差异不是文案差异**:'
        '①「为该节点选点」是路线编辑的面(App 的节点选点在路线编辑里,广场 composer 没有这一格);'
        '②「清除已选活动」—— App 的关联 chip 是四种(活动/路线/地点/俱乐部)共用一行,'
        '清空按钮写「取消关联」,照抄只能对上其中一种;'
        '③「正在刷新动态…」—— App 走系统下拉刷新控件(iOS 27 原生化),没有自绘状态条;'
        '④「草稿与已选内容仍在这里」—— App 的同款承诺写在失败回执里'
        '(「…，已保存在本机」),比原文多说了**存到哪**,不为对账降级。',
    'subpackageA/pages/myproject/index': 'App 有 /my-projects,措辞差异。',
    'pages/index/index': 'App 首页是 /feed + /map,结构不同(小程序单页含推荐+附近)。措辞差异。',
    'subpackageTalent/search/index': 'App 有 /search 与 /search/result,措辞差异。',
    'subpackageMember/coupon/coupon': 'App 有「我发布的券」+ 发券 sheet(本轮已补),措辞差异。',
    'pages/merchant/relation/index': 'App 有 /merchant/relations,措辞差异。',
    'pages/publish/templateadd/templateadd':
        'App 同样是独立命名页 /template/new，确认后 replace 到编辑器。',
    'pages/publish/template-intro/index':
        'App 保留价值主张引导页，与命名页都用 replace 保持返回栈。',
    'pages/merchant/ledger/index':
        '**已补**:消息入口 + 未读角标(此前消息只在「我的」页,'
        '而合作邀约/官方通知都落在消息里,商家在工作台看不到)。'
        '结算相关(已入账/本月核销/对公批次/核销详情)App 都有,措辞差异。',
    'pages/topic/index/index':
        '**待拍板**:「主题音频讲解」(TopicInfoVO.audioUrl,后台录入、前端只播)。'
        'App 侧要新增音频播放依赖(just_audio 一类)+ 一个播放条 —— '
        '加依赖是产品决定,不自作主张。⚠️ 发布草稿里已有 audioUrl 透传字段,'
        '但两端都没有录音入口(音频从后台录),所以缺的只是**播放**这一半。'
        '「余席待确认」「参与品牌」「发布评价」在 App 其它面已有,措辞差异。',
    'pages/publish/activity/index':
        '**已补**:活动封面(模型有 imgUrl 界面没填)、合作者'
        '(后端字段叫 collaborators 不是 collaboratorIds)。'
        '票单管理 App 已有(添加/删除票种)。「搜索关键字」是选模板时的子面,另议。',
    'subpackageMember/mytemplate/mytemplate':
        'App 把三类发布(主题/活动/玩法)合并进 /my-projects 一页统一上下架,'
        '玩法用的就是 /api/template/updateLibraryStatus(my_project.dart:114)。'
        '不单开「我的节点玩法」一页,是有意的合并。',
    'pages/activity/baoming/baoming':
        '核过**不是**缺口:「同意将姓名手机号提供给主办方」这道单独同意闸 App 有'
        '(activity_detail_page:628 的 CheckboxListTile,未勾时提交钮禁用)。'
        '我一度只看到自动调 agreeSignupDataSharing 就判成「自动同意」,'
        '往下翻才看到勾选框 —— 又一次「只看调用点不看它的守卫」。',
    'pages/gerenziliao/gerenziliao':
        '**部分已补**:「城市签名」(App 原来叫通用的「简介」)。'
        '⚠️ 只改这一处 —— 小程序的俱乐部/模板/发布简介本来就叫「简介」,'
        '词汇对齐是逐处的不是查找替换(已配门禁两头都锁)。'
        '「探索作品」对应 App 的 /my-projects,措辞差异。',
    'subpackageP3/pages/stamp-camera/index/index':
        '**真问题,已修**:pickImage 没包 try —— 相机权限被拒时点了什么都不发生、'
        '也不报错。已分权限/非权限两种文案并给「去设置」。',
    'pages/coop/settlement-detail/index': 'App 有 /merchant/ledger/batch/:batchId,措辞差异。',
    'pages/club/join-requests/index': 'App 有 club_join_requests_page,措辞差异。',
    'pages/address/address': 'App 有 /address 与参与人信息,措辞差异。',
    'pages/publish/biaoqian/biaoqian': '选择分类是发布流程内的子面,App 在发布页内联,不单开一页。',
    'pages/coop/candidates/index': '候选池页 App 有(coop_candidates_page),措辞差异。',
    'pages/activity/official-mine/index':
        'App 有「我发布的活动 / 我发布的通知」两块与「触达 N 人」;'
        '空态是合并的一句而不是分两句 —— 两块都空时才显示,单块空时那块不渲染。',
    'pages/merchant/ledger/order-detail/index':
        'App 有 /merchant/redemption/:type/:id,含结算状态/结算路径(措辞不同)。',
    'pages/club/edition-report/index': 'App 有工时与证据(club_edition_report_page),措辞差异。',
    'pages/club/create/index': 'App 有(club_create_page),含城市必填提示;措辞与占位文案差异。',
    'pages/club/apply/index': 'App 有(club_apply_page),措辞差异。',
    'pages/merchant/index/index':
        '「工作台没能加载出来」是**运行时拼的**(merchantErrorView 的 what 参数),'
        '静态抽不到 —— 判据的第三类误报。其余措辞差异。',
    'pages/merchant/discover/index': '**已补** /merchant/discover(按调性找店)。',
    'pages/merchant/decor/index':
        '措辞差异;**已补**封面上传的 16:9 比例提示。',
    'pages/publish/temp/index':
        '**部分已补**:玩法封面上传(toJson 一直发 imgUrl,界面没地方填)。'
        '五种完成方式 App 编辑器全都有(我一度按文案条数误判成只有两种)。'
        '剩余(勋章图/优惠券挂载/提示/配图/时长)另议。',
    'pages/club/detail/index':
        '**真缺口,已补**:「AI 生成内容,请核对后再发布」的**合规标注**——'
        'App 三个 AI 产出面一处都没标。已收口成 AiGeneratedNote 并配门禁。'
        '其余(AI 策划入口本身)App 有 club_ai_design_sheet,措辞差异。',
    'pages/merchant/apply/index':
        '营业执照上传 App 有(merchant_apply_page),措辞差异;'
        '「品牌形象图」对应 App 的封面上传。',
    'pages/topic/merchantinfo/merchantinfo':
        '**部分已补**:「参与商家」统计(后端 TopicInfoVO.registrationMerchantCount '
        '一直在下发,App 模型没解析)。剩余(按章节列参与品牌、申请承接入口)'
        '在 /merchant/recruit/:topicId 已有,不重复放在路线详情。',
    'pages/merchant/citynode/index': '「+ 投放据点」入口 App 有(/merchant/city-nodes/create);其余措辞差异。',
    'pages/merchant/marketing/index':
        '「合作机会」入口 App 在商家首页有(/merchant/coop),小程序在营销页也放了一个。'
        '一个入口够用,不重复加。其余措辞差异。',
    'pages/merchant/decor/coop-setting/index':
        '对应独立页 /merchant/coop-profile(「可容纳人数」vs「可接待人数」是措辞)。',
    'pages/coop/withdraw/records/index':
        '**历史深链转向壳,App 没有这一跳**:那页 onLoad 里 wx.redirectTo 到 '
        '/subpackageMember/tixianjilu,自己只画「正在打开提现记录 / 即将前往银行卡提现记录」'
        '与失败态「页面打开失败」+ 运行时 message 重试(test/parity_ledger_test.dart 已把它记成"转向壳,App 已有 '
        '/withdrawal-records")。App 的 /withdrawal-records 直接就是记录页,没有过场壳 '
        '⇒ 那四条文案在 App 无对应面。「提现记录」两端一致;副标'
        '「银行卡提现与到账进度」是 cy-page-title 的副标,App 走 iOS 原生导航栏(不做副标)。',
    'subpackageA/pages/assetcenter/earnings/index':
        '**新收款模型(R10)有意删掉的那半页**:缺的 14 条里 13 条属于页内那张银行卡提现表单'
        '(提现金额 / 输入持卡人姓名 / 银行名称 / 银行账号 / 手机号码 / 全部提现 / '
        '提现到账说明 / 提现申请未提交 / 重新加载可提现余额及各自的 placeholder)。'
        '2026-09-15 起提现一律线下(withdrawal_contact_dialog.dart 的客服微信弹窗),'
        'App 按 R10 不做银行卡表单,故不是缺口。其余:小程序页题「账户收益」vs App /assets '
        '的「资产明细」—— App 那页混装积分/余额两 Tab 流水,收益明细与邀请记录各是独立页;'
        '措辞差异。',
    'subpackageRoam/nearby/index':
        '**同一份构造,词汇与 IA 有意不同**:App /roam/nearby 的类注释就写着「对齐 '
        'subpackageRoam/nearby:一图三类 + 常驻 HUD + 底部抽屉」,但 ① 小程序叫「队伍」,'
        'App 整页叫「局」(我的局 / 开一局 / 还没有局),逐句替换会把两端词汇改成两套;'
        '② 小程序的角控件(范围 / 我的队伍)与队伍申请·队长审批半屏,在 App 是'
        '「局卡 + 举报/退出 + 我的局列表」;③ 缺的 6 条正好就是这两类——队伍侧的 5 条'
        '(队伍 / 申请 / 地图 aria「附近的队伍地图」)与半屏收起 scrim 的包着词'
        '「关闭主题」⇒ 措辞 + IA 差异,不是文案缺口。',
    'pages/roam/index':
        '**App 那页是精简过的 live 视图,102 条里绝大多数属于 App 没有的面**:'
        '① 页内设置抽屉(减少动态效果 / 后台持续定位 / 到点提醒 / 锁屏也记录足迹 / '
        '玩法说明 / 位置权限 / 清空本机缓存)—— App 拆成 /settings 与系统权限,'
        '且动态效果跟随系统 MediaQuery.disableAnimationsOf,不做页内开关;'
        '② 一串可关闭提示条及其 aria(关闭足迹提示 / 关闭附近商家提示 / 关闭官方活动提示 / '
        '关闭地点提示)—— App 没有这些提示条;③ 结算页变体(关闭结算页 / 返回广场 / '
        '继续本次探索 / 不影响已上传的记录)与「首次发现商家」仪式卡(领优惠券 / 做微任务 / '
        '到店有礼 / 赚探索值 / 跳过首次发现奖励);④ 玩法说明的内容差异:App 有等价的'
        '「自由漫游怎么玩」,但不写「走近店铺 55 米」—— 55 是小程序侧的 REVEAL_M 常量,'
        'App 的揭示半径由服务端 tile 决定,印一个我们背不了的数字就是假话。'
        '⇒ 属结构差异(该页另开一批),不是文案能关的洞。',
    'subpackageP3/pages/growthcenter/index/index':
        '**部分已补**:「继续探索城市，第一枚徽章会在这里出现」的标点、徽章重试的 aria'
        '「重试徽章数据」、榜单入口的 aria「查看完整排行榜」已对齐。剩余属状态/外观:'
        '① 「城市探索 · 成就与排行榜」是 cy-page-title 的副标,App 走 iOS 原生导航栏'
        '(不做副标,iOS 27 原生化);② 「正在更新我的排名 / 现有排名仍可查看」与'
        '「正在更新足迹 / 现有数据仍可查看」是**陈旧-刷新态**(小程序 cy-progress-status),'
        'App 用下拉刷新 + 骨架,补这一态要改刷新模型,不属文案批;'
        '③ 「我的城市足迹」是小程序 metric 列表的 aria-label。',
    'pages/activity/official-detail/index':
        '**部分已补**:奖励区(「活动奖励」+「主办方尚未配置奖励，页面不承诺任何奖励。」,'
        '并去掉 App 原来那条兜底承诺「🏅 参与即有惊喜」)、发放说明(完成活动任务后按上方配置发放 / '
        '实际发放结果以活动结算为准)、集体进度两档提示、「详情信息」「人已报名」已对齐。'
        '剩余属结构(另开一批):od-facts 那一排事实(活动周期·总时长 / 开放时间·北京时间 / '
        '活动范围 / 活动任务·N 项任务)—— App 的 _StatBlock 只有参与与我的进度两格;'
        '「活动举办城市」那行—— App 把 city 降成一枚 CyTag,不写标签;'
        '主办方行(城瘾官方 · 发起);「活动介绍」的任务卡横排;顶部「正在更新活动详情…」刷新提示。',
    'pages/club/group-code/index':
        '**真缺口,已补**:小程序 E-12(2026-09-16)把「缺参」与「无权限」从通用失败里拆成'
        '**两个终态** —— 原话「重试永远失败且没有出路」;App 一直还是老样子(通用'
        '「出码失败」+ 重试)。已按原文补:缺参态(缺少路线或场次信息 / 返回俱乐部，'
        '选择具体场次后再出示团码 / 请从俱乐部管理进入具体场次)、无权限态(当前账号'
        '没有出码权限 / 当前账号不能出示这一场的团码)、两态共用出口「进入俱乐部管理」,'
        '选场次态补副标「选择本次带队场次」。判据(403 或文案含权限/无权)落在 '
        'group_code_api.dart 的 GroupCodePermissionException,与小程序 isPermissionDenial 同口径。'
        '5/12 → 12/12。',
    'pages/club/workbench/index':
        '**部分已补**:错误页文案照原文(没能进入俱乐部管理 / 暂时无法进入俱乐部管理，'
        '请重试或返回俱乐部。 / 重试进入 —— App 原来写「加载你的俱乐部失败」「重试」)。'
        '剩「返回俱乐部」:小程序那是个按钮,App 用系统返回键(iOS 27 原生化)。2/4 → 4/4。',
    'pages/club/topic-detail/index':
        '**部分已补**:页内三处语义标签照原文 —— 骨架 loading-label「正在加载活动详情」、'
        '四圆钮的 aria「活动快捷入口」、台账入口的 aria「打开核销台账」。'
        '**剩余 38 条全在「活动导演台」**(手动解锁章节 / 角色接管 / 定向广播 / 现场事件 /'
        '队伍进度 / 节点状态 / 活动漏斗 / 准备总览 / 集合时间 / 核对结果 …):'
        '小程序把原 `pages/club/game-director` 整页收进了这一页,写集是 '
        '`/api/game/session/{view,command,receipt,recap}` —— App 侧那套归 4-C(game/** 写集),'
        '本页只渲染 H1–H6、写入走 `/club/:id/event-ops`,文件头 30–47 行已写明是有意不做,'
        '不属文案批。「查看退出与暂停规则」是页底条的读屏名,App 的同一入口是设置表里那行'
        '(可见字与原文的「退出与暂停规则」一致),不叠一层会重复朗读的语义。53/94 → 56/94。',
    'pages/club/enroll/index':
        '**真缺口,已补**:小程序把「确认查看权限」失败分网络/业务两态,两态标题与重试键'
        '都不一样(暂时无法确认查看权限 / 重新检查 ↔ 网络连接失败);名册层也分两态'
        '(报名名册加载失败 / 检查网络后重新加载报名名册 / 重新加载)。App 原来四态塌成一态'
        '(全是「报名名册加载失败」+ 默认「重试」)。已用仓内既有的 clubOpsFailureState 分类补上,'
        '并补三处骨架 loading-label(正在确认报名名册查看权限 / 正在加载报名名册 / 正在加载报名详情,'
        '小程序那三句是 aria-label)与空态 sub 的原文(逗号按原文是半角)。'
        '剩「报名名册暂未更新」「正在更新报名名册…」:小程序有一条**陈旧-刷新条**(旧数据仍在屏上'
        '时给一条提示),App 走下拉刷新 + 骨架(刷新即重画),补这条要改刷新模型,不属文案批。'
        '12/20 → 18/20。',
    'pages/club/topic-story/index':
        '**已补**:两处空态副标(开放商家承接后，由承接商家补齐站点与玩法。 / '
        '承接商家补齐模板后会出现在这里。)、骨架 loading-label「正在加载剧情与玩法」、'
        '取答案中的正话「正在取答案…」。16/20 → 20/20。',
    'pages/club/customer-detail/index':
        '**已补**:骨架 loading-label「正在加载客户详情」、两个按钮的 aria'
        '(取消编辑标签与备注 / 添加标签)、保存失败的 inline-error 标题'
        '「标签与备注没保存成功」(原文有标题+副标+重试保存,App 原来只有一行红字)。'
        '20/24 → 24/24。',
    'pages/club/customers/index': '**已补**:骨架 loading-label「正在加载客户名单」。8/9 → 9/9。',
    'pages/club/settlement/index':
        '**已补**:提现键文案照原文「联系平台客服提现」(App 原来只写「提现」;'
        'R10 下这个键不跳表单、弹客服号,原文那句话正好说清点下去会发生什么)。9/9。',
    'pages/merchant/decor/ai-npc/index':
        '**部分已补**:「性格设定」(原叫「怎么说话」)、「角色声音」(原叫「它的声音」)、'
        '「让店铺角色用你的声音说话」,以及声音三档状态的正话'
        '(声音正在生成，可以先返回继续装修店铺。 / 角色的声音已准备好。 / '
        '声音生成失败，请重新选择清晰的录音。)与刷新动作「查询生成状态」已按原文对齐 '
        '—— 两端是同一个状态机,只是录音机制不同。剩余 12 条分四类,都不是文案能关的:'
        '① **预设形象**(选现成的 / 使用这个形象)—— 有意不移植,理由写在 '
        'merchant_node_npc_page.dart:28(12 张预设 = 30KB 行程编码表 + canvas 渲染器,'
        '而「照片」那条路小程序自己也有,等价可用);'
        '② **上传录音那半边的按钮与提示**(上传并生成声音 / 重新选择文件 / 重新选择录音 / '
        '请上传清晰、无背景音乐的说话录音。 / 10 秒—5 分钟，文件不超过 10MB。)—— '
        'App 走的是**五句声音克隆**(同一后端能力 /api/merchant/npc/voice/*,脚本由服务端下发),'
        '这几个按钮在 App 没有对应面(时限更不能照抄:上游是 mp3/m4a/wav、10 秒到 5 分钟、'
        '20MB,印 10MB 就是写一个背不了的数);'
        '③ **漫游落点** —— 小程序那格存的是 /api/merchant/decor/save 的 '
        'locationLat/locationLng/address,不是 NPC 字段;App 把这件事留在店铺装修页'
        '(「门店定位」,merchant_decor_page.dart:521),一个动作一个入口,不在这里重复摆;'
        '④ **错误/放弃标题**(角色资料没能打开 / 暂未完成 / 还没有保存 / '
        '离开后，本次修改不会保留。)—— App 用全仓共享的 merchantErrorView'
        '(说「店铺形象没能加载出来」,与新页题同名)与统一 UnsavedGuard 文案'
        '(与 pages/club/edit 逐字一致),为一页再造第二个名字,正是 mylike 那次判过的毛病。'
        '⚠️ 顺带查出(不属本批):App 店铺级声音链路打 /api/merchant/npc/voice/script 与 '
        'enroll{sampleUrls},钉版后端两条都对不上(只有 voiceSample 单文件,且无 script 端点)'
        '⇒ 那一页端到端跑不通,另立单项。',
    # ── 文案批 · roam 域(2026-09-18):下面三页都是**标点/读屏文案**级差异,
    #    已按原文逐字对齐(含半/全角逗号),命中率 100%,不再重复报。
    'subpackageRoam/citystamp/index':
        '**已对齐(11/15 → 15/15)**:三处逗号照原文改全角(空态副标 / 输入框 placeholder / '
        '「收下，出发」键),并补输入框读屏文案「留一句给下一个人」(原文 aria-label)。'
        '剩 0 条。App 有意不同:拖留言条进信箱 / 撕纸 / 刮开换成原生控件'
        '(文件头已写明),JS 运行时拼的 hint 措辞随之改口,不算缺口。',
    'subpackageP3/pages/stamp-album/index/index':
        '**已对齐(8/11 → 11/11)**:空态副标逗号照原文改全角;续页加载「加载中…」'
        '改原文「正在读取下一页」;续页重试行补读屏文案「重试加载这一页」(原文 aria-label)。'
        '剩 0 条。',
    'subpackageRoam/citynode-code/index':
        '**已对齐(1/2 → 2/2)**:缺参态副标「链接缺少据点参数,请回据点页重新进入」'
        '逗号照原文半角(App 原来写全角,一字之差对不上)。剩 0 条。',
    'pages/publish/fabu/index':
        '**文案批已收口(79/148 53% → 119/148 80%;同一批在 github/master 那份 wxml 上是'
        ' 80/166 48% → 120/166 72%,两个分母都过线),剩 29 条分八类,全是 App 没有那个面,'
        '不是措辞差异**(逐条对 github/master 的 index.wxml 核过,原文行号在括号里):'
        '① **待编排区**(155/157/169/172/175/188/189/193/417,7 条)—— 页头注释①写明有意不移植,'
        '素材直接落进章节;⚠️ 顺带:App 原来那句自创的「先连续录入地点，再补内容并归章」'
        '让「补内容」蒙中过一次,照原文换成 148 行的「先写一章的故事，再往里放地点」后它掉回缺口 —— '
        '蒙中的不是本行该要的东西,记录在此不回填。'
        '② **下一站/节点路线对应**(776/777/885/888/906/907,6 条)—— 真源那格 '
        '`wx:if productType===1`(自由探索),App 全仓 0 处「下一站」⇒ 功能未移植,不是文案缺。'
        '③ **文字说明子页**(584/595/596/658/668,5 条)—— App 把叙事写成故事流里的文字块, '
        '那个子页连同它的未保存守卫与「为什么会这样」没有对应面。'
        '④ **遮罩 scrim 的读屏名**(400/679,2 条)—— 原生 sheet 的下滑/点遮罩关闭是系统行为,'
        '不给遮罩起名;页内返回键已照 404 行原文命名「关闭故事流编辑器」。'
        '⑤ **玩法选择子页的导航读屏名**(716/719,2 条)—— App 的选择器是节点 sheet 内联展开, '
        '没有独立子页可返回/完成。'
        '⑥ **发布确认页 App 没有的三块**(1089/1095/1110/1161,4 条:本次发布摘要卡、自动检查'
        '通过项、玩家看到的样子、blocking 行尾的「去填写」)—— App 的检查页只有 必填/建议/奖励总览,'
        '且检查行不可点(没有 locatePublishIssue 那一跳),「去填写」没有动作可挂;'
        '预览在 App 是独立入口「预览 →」读服务端已保存的那一版。'
        '⑦ **章节卡的承接状态块**(216/226,2 条:已开放承接 / 未开放商家承接)—— '
        'App 章节行没有这一格;⚠️ 页头注释③说「章节级配置未移植」但章节 sheet 其实已经能配承接,'
        '那句注释是旧的,补这一格时要连注释一起改口。'
        '⑧ **节点营业时间**(1202,1 条)—— `PublishNode.businessTime` 模型字段在 App '
        '既不进 toJson 也没有录入面(publish_draft.dart:295 是空壳),照抄标题等于写一个背不了的控件。',
    'pages/merchant/marketing/ai-insight/index':
        '**部分已补 21/37**(自 17/37):标题「AI 店铺参谋」→「店铺参谋」、区块 '
        '「AI 经营解读」→「经营解读」、刷新提示「正在更新经营数据…」、空态 CTA '
        '「去合作中心看看」、AI 降级卡「智能解读暂不可用 /，上方经营数据不受影响」'
        '与动作「重新生成解读」均逐字取自该页 wxml。入口 tile 一并改名'
        '(merchant_marketing_page.dart,真源 pages/merchant/marketing/index.js)。'
        '剩余 16 条是**五个整块没实现 + 一个三态**,不是文案能关的:'
        '① **首屏归因价值卡**(位玩家到店 / 单核销)—— App 没有这张卡;'
        '② **店铺档案行**(先配置店铺档案 / 去配置店铺档案 / 编辑店铺档案 / 店铺档案)'
        '—— 小程序在 insight 页内引导配置档案,App 的档案编辑是独立页 '
        '/merchant/profile(自称「店铺资料」,merchant_edit_page.dart:37),入口不在这页;'
        '③ **最近到店玩家**;④ **打卡来自哪个主题**;'
        '⑤ **实体推荐**(为你推荐的主题 / 招商中 / 去申请承接 / 推荐联动的商家 / '
        '可联动 / 发起接洽)。'
        '⑥ **factState 三态**(基础数据暂未完整返回 / 不会用 0 代替缺失的到店、打卡或核销数据)'
        '—— 已核:后端下发 `facts.attribution.{visitors,checkins,redeems}` '
        '(小程序拿它算 unknown/empty/ready,index.js:114-121),且 `profile`、`valueCard` '
        '同属一份响应;App 的 MerchantInsightFacts 只解析 window/sampleMembers/lowSample/'
        'checkin/crowd/supply,所以只能按 crowd.members==0 猜空态,分不出「未知」与「明确为零」。'
        '①～⑥ 都是**数据已在响应里、App 模型没接** —— 要补模型字段 + 四块 UI,另立单项。'
        '⚠️ 顺带查出(不属本批):同一份响应的 `profile` 字段 App 也未解析,'
        '两端对档案页的叫法(小程序 店铺档案 / App 店铺资料)不一致,同物两名,另立单项。',
    'pages/play/index':
        '**文案批已收口(09-25),125/211 59% → 144/211 68%;补的 19 条里 12 条是'
        '读屏 aria,按 iOS 27 口径落成 semanticsLabel 不上屏**(身份胶囊「查看本局角色线索」、'
        '线索 sheet 关闭「关闭本局线索」、身份卡 scrim 与确认后键「关闭身份卡」、'
        '「重新同步/重试同步本局状态」「核对这次操作的服务端结果」「用原请求号重试这次操作/身份确认」、'
        '「填写本站任务文字凭证」「扫描本站现场任务码」「拍摄或选择本站任务照片」、'
        '底栏扫码键「扫码到达」),可见字 7 条:「夜深了,注意安全」(nightWarning 一直在模型里、'
        '从没渲染过)、「收下本站建议」(preference 结果页 CTA 原话)、'
        '「改成哪个结果」(preference 标签纠正 sheet 标题,原写自创「调整标签档位」)、'
        '队长动作键照工具行原文(「扫成员票核销」「整团结算」「解锁下一章节」)、'
        'P1 集合屏两态「队伍集合中」眉标 + meArrived 后「已签到」(后端一直下发、'
        'App 模型没解析,按钮永远停在「我到了」)。**剩余 67 条全是 App 没有那个面**:'
        '① 节点半屏族([ 节点实拍 ] / 这一关你已通关 / 开始任务 / 编辑此节点 / 看看别家 / '
        '查看本站优惠券 / · 扫码到达 / · 也可扫码到达 / 到店后出示核销码给商家扫 / '
        '进入门店 · 确认授权后出示核销码 / 进入当前门店并确认授权后出示核销码)—— '
        'App 的节点交互拆在行走条与节点列表,没有那层中央半屏;'
        '② 出发前准备 checklist(电量至少 50% / 穿舒适的鞋 / 先看天气)—— App 开场是 '
        'PackOpeningIntro,没有该面,且 50%/55 米是小程序侧常量,背不了;'
        '③ 章节选择弹层族(选择章节 / 切换章节 / 关闭章节选择 / 收起章节内容 / 展开本章剧情 / '
        '点一下看下一张 / 还有游戏数 / 出示二维码核验)—— App 章节自动呈现,无选章弹层;'
        '④ 结算面族(城市探索里程碑 / 已到达当前最高里程碑 / 我的旅途照片 / 附近下一程 / '
        '查看票价并购票 / 路线预览暂未生成 · 重试)—— 数据在响应里、App 模型没接,另立单项;'
        '⑤ 券与徽章仪式族(已放入卡券包 / 同时到账一张券,点击查看 / 松手收下 / 已收下 / '
        '现在核销！ / 现在核销，出示动态码)—— App 直落动态码页,无按住-松开仪式面;'
        '⑥ 奖励掉落卡族(已记在你的收藏里 / 查看收藏 / 继续)—— App 用奖励弹层,非常驻掉落卡;'
        '⑦ 自由探索工具抽屉行(我的权益 / 自动记录足迹 / 到点提醒 / 展示整团码 / '
        '这个主题是什么 / 没有顺序，随时可走 / 在地图上看这些商户 / 回到卡包 / '
        '收起，回到商家格 / 这一趟自动记下来的)—— App 精简为「更多」菜单与独立页;'
        '到点提醒=订阅消息 iOS 无等价物(playkit_timewindow_view 头注),整团码在俱乐部域,'
        '自动记录足迹两端漫游模型不同(同 pages/roam/index 判定口径);'
        '⑧ 陈旧-刷新横幅(网络状态暂未刷新 · 点击重试 / 重新加载当前状态)—— '
        'App 走下拉刷新+错误态,无横幅面;'
        '⑨ 剧本 tab 空态(这一场还没有打卡点 / 剧本会在点位就绪后出现)—— intro 里的 tab '
        'App 没有;节点空态真源是 index.js:2852「本场路线节点还在配置中，请稍后查看」,'
        'App 已逐字一致(运行时串不计入本工具);'
        '⑩ 杂项:锁站黑屏仪式两句(这扇门还没向你敞开。/先走完上一站,谜题自会指路。)、'
        '前路未知、商家 / 地点、已完成游戏(集合读数)—— ①⑦ 同族;「你 的 城 市 故 事」'
        '是小程序字距排版,App 用正字;关闭城市故事 / 关闭完成面板 / 关闭游戏 / 关闭面板 —— '
        'iOS 27 原生化由系统返回承载;关闭地点卡 / 当前地点信息 / 输入地址 —— App 走 '
        '/publish/poi 搜索页(「搜索地点名称」),措辞差异;查看题目大图 / 播放题目音频 —— '
        'gp2 题目子面,App 题目直接平铺。'
        '⚠️ 判据修正记录:曾按静态串把「这一场还没有打卡点」判给 play_empty_state 的空态, '
        '读 index.js:2846-2852 后确认那是 intro 剧本 tab 的态,节点空态 App 原文已一致 —— 未改。',
    'pages/merchant/citynode/create/index':
        '**已对齐 20/20 100%**(09-25 文案批):补 8 条 —— 权限闸三态(「正在核对经营团队权限…」/'
        '「当前岗位不能管理据点」+「请联系店主或店长调整经营团队岗位」/「商家权限加载失败」+重试),'
        '店址改选(「在地图上标店址」/「确认这个店址」/「重新选择店址」,复用 /publish/poi),'
        '草稿守卫(「放弃未提交草稿吗」+原文 content)。提交键 runtime 文案也照真源'
        '(「刷新审核状态」→「重新读取申请状态」)。',
}


def _systemic_reason(label: str):
    for k, why in _SYSTEMIC.items():
        if k in label:
            return why
    return None


# 通用骨架组件(空态/错误/加载/导航/按钮/弹层壳):被 80~127 页共用。
# ★ 它们的文案属于全仓共用语气,不属于任何一页 —— 逐页重复报送同一句,
#   会让 100+ 页因为同一条同时掉下去,噪音把真信号淹掉。
# ⇒ 跟页面自有组件时跳过;骨架自身的文案在 main() 末尾**单列一次**(不按页重复)。
#   实测这 12 个骨架合计只有 4 条中文(cy-sheet 3 条 + cy-nav-bar 1 条),
#   其余文本全是 `{{}}` 插值 —— 跳过几乎不损失覆盖面。
_CHROME = (
    'components/cy/toast/', 'components/cy/modal-host/', 'components/cy/loading-mask/',
    'components/cy/nav-bar/', 'components/cy/skeleton/', 'components/cy/empty/',
    'components/cy/error/', 'components/cy/icon/', 'components/cy/page-title/',
    'components/cy/inline-error/', 'components/cy/btn/', 'components/cy/sheet/',
)


# 页内**一条静态中文都抽不到**的页。★ 不是「看过了」,是写明为什么抽不到 ——
# 抽不到要么内容在数据里,要么是过渡壳;两种都不该留在「未比」黑箱里。
_NO_COPY = {
    'pages/agreement/index':
        '页内静态文案 0 条:标题/正文/生效日期全部来自 doc.*(协议文档由后端下发),'
        'wxml 里唯一的中文是 `生效日期：{{doc.updatedAt}}`,插值不算文案。'
        'App /legal/:type 同源渲染同一份文档 ⇒ 机械比对没有对象。',
    'pages/publish/topicadd/topicadd':
        '兼容重定向壳:整页只有一行注释,onLoad 直接 redirectTo /pages/publish/fabu/index'
        '(2026-10 起从 app.json 摘除)。App 没有这一跳,也没有文案可比。',
}


def labels(page: str) -> set:
    """这一页写死的中文文案(含它声明的自有业务组件)。

    ⚠️ `{{}}` 插值一律不算 —— 那是数据不是文案,
      拿它比会把「后端下发的主题名」当成 App 缺的文案。
    ★ 小程序把页面主体搬进了自有组件(`components/cy/scene-*`),页面 .wxml 只剩壳:
      不跟进去,18 个「文案 <3 条」的页里 14 个会被判成「没有文案可比」。
    ponytail: 只跟一层。实测嵌套的非骨架组件为 0 页,遇到再加深度。
    """
    out = set()
    own = _page_text(page, '.wxml')
    if own is not None:
        out |= _scan_copy(own)
    for rel in _declared_components(page):
        if any(rel.startswith(c) for c in _CHROME):
            continue
        text = _page_text(rel, '.wxml')
        if text is not None:
            out |= _scan_copy(text)
    return out


def _page_text(page: str, suffix: str):
    """小程序页/组件正文:`a/b{s}` 与 `a/b/index{s}` 两种布局都认。

    ★ 读 `BACKEND_REF` 的 Git 对象而不是共享工作树 —— 工作树被别的 worker
      切走后,同一次对账的答案会跟着旧树漂移(假降)。
    """
    name = page.strip('/')
    for base in (name, name + '/index'):
        text = E.xcx_file_text(base + suffix)
        if text is not None:
            return text
    return None


def _declared_components(page: str) -> list[str]:
    """页面 json 里 usingComponents 声明的组件(相对小程序根)。"""
    cfg = _page_text(page, '.json')
    if cfg is None:
        return []
    try:
        comps = (json.loads(cfg).get('usingComponents') or {}).values()
    except Exception:
        return []
    return [c.lstrip('/') for c in comps]


def _scan_copy(text: str) -> set:
    out = set()
    s = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    for m in re.finditer(r'>([^<>{}]+)<', s):
        t = m.group(1).strip()
        if t and re.search(r'[一-龥]', t) and len(t) <= 24:
            out.add(t)
    for m in re.finditer(r'(?:title|subtitle|placeholder|sub|retry|label|confirmText|cancelText)="([^"{}]+)"', s):
        t = m.group(1).strip()
        if t and re.search(r'[一-龥]', t):
            out.add(t)
    return out


def _exempt() -> set:
    """manifest 判过「App 由系统能力承载」的页(如选图走 iOS 相册)。"""
    return {e.get('miniPage', '') for e in P._manifest_entries() if e.get('kind') == 'system'}


def app_copy_corpus() -> str:
    """文案对账用的 App 语料:全部 `lib/**/*.dart`(剥注释)。

    ★ migration_plan 生成总表时也走这里 —— 同一页在两个工具里必须得到同一个数。
      语料口径不同会让「总表说 62%、裁判说 80%」这种鬼故事重现。
    """
    text = ' '.join(
        re.sub(r'//[^\n]*', '', q.read_text(errors='ignore'))
        for q in E.APP_LIB.rglob('*.dart'))
    assert len(text) > 200_000, 'App 语料读空了'
    # 自查:一句一定在的文案必须命中,否则是抽取或语料坏了。
    assert '提现记录' in text, '连「提现记录」都搜不到 —— 语料或抽取失效'
    return text


def verdict(page: str, app: str) -> tuple:
    """这一页的文案判据 —— 四选一,每个分支都写明为什么,不留「未比」黑箱。

    compared: 静态文案 ≥1 条,给出命中数;miss 是**线索**不是判决(见文件头)。
    judged  : 已逐页核过(_JUDGED,含判成什么),不重复报。
    no-copy : 页内静态文案 0 条(_NO_COPY 写明为什么抽不到)。
    system  : manifest 判过由系统能力承载,文案对账对它不适用。
    """
    key = page[:-len('/index')] if page.endswith('/index') else page
    if page in _exempt():
        return 'system', 0, 0, []
    if page in _JUDGED or key in _JUDGED:
        return 'judged', 0, 0, []
    L = labels(page)
    if not L:
        return 'no-copy', 0, 0, []
    miss = sorted(t for t in L if t not in app and _systemic_reason(t) is None)
    return 'compared', len(L) - len(miss), len(L), miss


def main() -> int:
    argv = sys.argv
    min_labels = 1
    if '--min' in argv:
        min_labels = int(argv[argv.index('--min') + 1])
    show_judged = '--judged' in argv

    app = app_copy_corpus()

    # `P.EXEMPT` 已在 d1a37c8 删除:它的语义现在由 manifest 里
    # `kind == "system"` 的条目承载(页面已判过「App 由系统能力承载」)。
    pages = P.xcx_pages()
    buckets = {'compared': [], 'judged': [], 'no-copy': [], 'system': []}
    for page in pages:
        state, hit, total, miss = verdict(page, app)
        buckets[state].append((hit, total, page, miss))
    # ★ 自查:每一页都必须落进一个判据,落不进去就是又长出黑箱了。
    assert sum(len(v) for v in buckets.values()) == len(pages), '有页没落进判据'
    # 判据里的幽灵:master 删页后 _JUDGED/_NO_COPY 会留在原地,
    # 把「已核 N 页」变成一句谎 —— 有空判据就当场说出来。
    stale = sorted(k for k in set(_JUDGED) | set(_NO_COPY)
                   if k not in pages and k + '/index' not in pages)
    rows = [r for r in buckets['compared'] if r[1] >= min_labels]
    thin = [r for r in buckets['compared'] if r[1] < min_labels]
    rows.sort(key=lambda r: (r[0] / r[1], -r[1]))
    judged, nocopy = buckets['judged'], buckets['no-copy']
    print(f'比对 {len(rows)} 页(文案 ≥{min_labels} 条的)· '
          f'命中率 <60% 的 {len([r for r in rows if r[0] / r[1] < 0.6])} 页 · '
          f'**已逐页核过 {len(judged)} 页**(见 _JUDGED,含判成什么)')
    print(f'覆盖面:{len(pages)} 页全部有判据 = 比对 {len(rows)}'
          + (f' + 文案 <{min_labels} 条 {len(thin)}' if thin else '')
          + f' + 无静态文案 {len(nocopy)}(见 _NO_COPY)· 已核 {len(judged)} · '
          + f'系统承载 {len(buckets["system"])} ⇒ **未比 0 页**')
    print('★ 这是线索不是判决:命中率低可能是「有意换了说法」或「运行时拼的」。')
    if stale:
        print(f'★ 判据里已失效的页 {len(stale)} 个(master 删页后残留,该清):'
              + ', '.join(stale))
    if _SYSTEMIC:
        print('★ 已剔除的系统性差异(多页共因,原因在 App 侧无解):')
        for k, why in _SYSTEMIC.items():
            print(f'    「{k}」{why}')
    print()
    for hit, total, page, miss in rows:
        low = '·' if total < 3 else ' '      # 文案 ≤2 条:一条差异就是 50%,低信噪比
        print(f'  {hit:>3}/{total:<3} {int(hit / total * 100):>3}%{low} {page}')
        if miss:
            print(f'          缺:{", ".join(miss[:6])}')
    if thin:
        print(f'\n文案 <{min_labels} 条的页(机械比对信噪比不够,列出来但不算命中率):')
        for _, total, page, _ in thin:
            print(f'  {total} 条  {page}')
    print(f'\n未纳入机械比对的页(每条都有判据,不是「没看」):')
    for _, _, page, _ in sorted(nocopy, key=lambda r: r[2]):
        why = _NO_COPY.get(page, '⚠️ 待判:静态文案抽不到,需人工写判据')
        print(f'  {page}\n      {why}')
    print(f'  已核 {len(judged)} 页({", ".join(sorted(p for _, _, p, _ in judged))})')
    if show_judged:
        print()
        for _, _, page, _ in sorted(judged, key=lambda r: r[2]):
            key = page[:-len('/index')] if page.endswith('/index') else page
            print(f'  {page}\n      {_JUDGED.get(page) or _JUDGED[key]}')
    # 骨架组件被从各页剔除(见 _CHROME),但它们的文案要**单列一次**核对,
    # 否则就成了另一处黑箱。
    print('\n通用骨架组件(被 80+ 页共用,单列一次、不按页重复报):')
    for c in _CHROME:
        text = _page_text(c, '.wxml')
        L = _scan_copy(text) if text is not None else set()
        if not L:
            continue
        miss = sorted(t for t in L if t not in app and _systemic_reason(t) is None)
        print(f'  {len(L) - len(miss):>3}/{len(L):<3} {c.rstrip("/")}'
              + (f'  缺:{", ".join(miss)}' if miss else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
