#!/usr/bin/env python3
"""端点一致性对账:小程序在用、而 App 没接的接口。

★ 判据是「小程序用不用」,不是「后端有没有」——
  用户的要求是**和小程序一致**,后端有而小程序也不用的接口不是缺口。
  只按后端端点算会得到 162 条,其中一半是后台/内部/回调,永远不该进 App。

★★ 2026-08-19 修正:App 侧原来只判「路径字符串在不在 lib/ 里」——
  可路径就写在 `lib/data/api/` 的客户端方法里,所以**有方法就恒算已接通**。
  实测 199 个 API 方法里 49 个**零调用方**:接口写好了,没有任何页面调它,
  用户点不到。这是把「回执」(方法存在)当成了「观测」(功能可达)。
  现在的判据:该路径所在的方法**必须有 API 层之外的调用方**才算接通。

★ 路径变量端点(`/{id}/click`)按**变量前的前缀**判:
  两端都是拼出来的,原样字符串在任何一边都匹配不到,
  按全串判会把它们全部误报成「两边都没有」。

平台专用端点不用静默 allowlist:只有当 App 端点在后端真实存在、
App 产品代码可达、后端语义证据仍存在时，才输出 documented equivalent。
任一证据丢失就回到 gap，并输出未成立原因。

★★ 2026-09-17 补:R10 收款模型(平台不打款)这类**产品层故意不接**的端点也登记
在这份清单里,形式是「app 元组为空 + App 侧替代实现的证据」(`⊘`)。空 app 却不带
证据 = 静默 allowlist,直接判红;App 替代实现被删、后端路由被删、小程序同口径
证据被删,一律回到 gap。

跑法:  python3 tool/endpoint_parity.py [--all]
"""
import re
import sys
import pathlib
import os
import subprocess
from dataclasses import dataclass
from typing import Optional

def _find_backend() -> pathlib.Path:
    """定位后端真源:能读 git ref 的那个后端仓。

    ★ `CHENGYIN_BACKEND=<路径>` 优先:远端执行机上 `~/Downloads/chengyin` 读不动
      (没有 `.git` 的快照;iCloud 卡死),镜像在 `/tmp/be-master`。没有这个开关时,三个裁判
      (endpoint/page/copy)在本机全是挂死,而不是报错 —— 挂死比红更难查。
    ★ 原来写死 `parents[3]/Downloads/chengyin` —— 那只在主仓
      `~/城瘾app/app` 下成立。在 git worktree 里(`~/orca/workspaces/app/xxx`)
      算出来的是 `~/orca/workspaces/Downloads/chengyin`,目录不存在 ⇒ 脚本 exit 1
      ⇒ `endpoint_reachability_test` 在**任何 worktree 里都是红的**,
      而它红的原因和端点一致性毫无关系。
    ★★ 2026-09-18 补:`~/Downloads/chengyin` 在部分机器上只是**小程序快照,没有
      `.git`**(git ref 读不了)。所以候选先按「有 chengyinhub-xcx **且** 有 .git」
      筛一遍,再退到只有目录的 —— 否则会挑中读不动 ref 的那份,把"能跑"变成"报错",
      而真正能读 ref 的镜像就在旁边的 `/tmp/be-master`。
    ★ 仍然 fail-closed:候选全都不存在时照旧报错退出,不静默当成"没缺口"。
    """
    override = os.environ.get('CHENGYIN_BACKEND', '').strip()
    if override:
        return pathlib.Path(override).expanduser()
    here = pathlib.Path(__file__).resolve()
    candidates = [
        p / 'Downloads' / 'chengyin' for p in here.parents
    ] + [
        pathlib.Path.home() / 'Downloads' / 'chengyin',
        pathlib.Path('/tmp/be-master'),
    ]
    for c in candidates:
        if (c / 'chengyinhub-xcx').is_dir() and (c / '.git').exists():
            return c
    for c in candidates:
        if (c / 'chengyinhub-xcx').is_dir():
            return c
    return here.parents[3] / 'Downloads' / 'chengyin'


BE = _find_backend()
_BACKEND_REF_ENV = os.environ.get('CHENGYIN_BACKEND_REF', '').strip()
BACKEND_REF = _BACKEND_REF_ENV or 'github/master'
API_CTRL_REL = 'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api'
# ★ 2026-09-19(b2):XCX 不再是判据来源，只是 migration_* 工具 monkey-patch
#   的兼容锚点。三个裁判(backend 路由/语义 · 小程序语料 · 页面清单)一律
#   固定读 BACKEND_REF 的 Git 对象，不碰共享语料仓的工作树。
XCX = BE / 'chengyinhub-xcx'
APP_LIB = pathlib.Path(__file__).resolve().parents[1] / 'lib'
APP_ROOT = APP_LIB.parent


def _git_text(*args: str) -> str:
    result = subprocess.run(
        ('git', '-C', str(BE), *args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            f'后端 Git 读取失败({BACKEND_REF} @ {BE}):{detail}'
            ';后端仓位置可用 CHENGYIN_BACKEND=<带 .git 的仓根> 指定'
        )
    return result.stdout


def _backend_commit() -> str:
    return _git_text('rev-parse', '--verify', f'{BACKEND_REF}^{{commit}}').strip()


def _full_commit_sha(value: str, label: str) -> str:
    value = value.strip().lower()
    if not re.fullmatch(r'[0-9a-f]{40}', value):
        raise RuntimeError(f'{label}不是 40 位 Git commit SHA:{value or "空"}')
    return value


def _remote_master_commit() -> str:
    """读 github/master 的远端自报 SHA。

    测试/一次性预检可注入刚刚从远端读回的 SHA，避免同一轮
    反复联网；该 seam 仍经严格格式检查，不接受空值或短 SHA。
    """
    injected = os.environ.get('CHENGYIN_BACKEND_REMOTE_SHA', '').strip()
    if injected:
        return _full_commit_sha(injected, 'CHENGYIN_BACKEND_REMOTE_SHA')
    output = _git_text('ls-remote', 'github', 'refs/heads/master').strip()
    if not output:
        raise RuntimeError('远端 github/master 没有返回 SHA')
    return _full_commit_sha(output.split()[0], '远端 github/master SHA')


def _verify_backend_ref_freshness(local_commit: str) -> None:
    local_commit = _full_commit_sha(local_commit, f'本地 {BACKEND_REF}')
    # 固定完整 commit 是可重现的审计快照，不需要联网。
    if _BACKEND_REF_ENV and re.fullmatch(r'[0-9a-fA-F]{40}', BACKEND_REF):
        expected = _full_commit_sha(BACKEND_REF, 'CHENGYIN_BACKEND_REF')
        if local_commit != expected:
            raise RuntimeError(
                f'固定后端 commit 解析不一致:{expected} != {local_commit}'
            )
        return
    if BACKEND_REF != 'github/master':
        raise RuntimeError(
            'CHENGYIN_BACKEND_REF 离线审计必须是 40 位 commit SHA'
        )
    remote_commit = _remote_master_commit()
    if local_commit != remote_commit:
        raise RuntimeError(
            '本地 github/master 已过期:'
            f'local={local_commit} remote={remote_commit};'
            '先 git fetch github master 再审计'
        )


_VERIFIED_BACKEND_COMMIT: Optional[str] = None


def verified_backend_commit() -> str:
    """返回已通过新鲜度门禁的 commit，每进程最多回读一次。"""
    global _VERIFIED_BACKEND_COMMIT
    if _VERIFIED_BACKEND_COMMIT is None:
        commit = _backend_commit()
        _verify_backend_ref_freshness(commit)
        _VERIFIED_BACKEND_COMMIT = commit
    return _VERIFIED_BACKEND_COMMIT


def _git_paths(prefix: str) -> list[str]:
    return [
        path for path in _git_text(
            'ls-tree', '-r', '--name-only', BACKEND_REF, '--', prefix
        ).splitlines()
        if path
    ]


def _git_blobs(paths: list[str]) -> dict[str, str]:
    """一次 cat-file 批量读取 ref 中的文件，不触碰 working tree。"""
    if not paths:
        return {}
    request = ''.join(f'{BACKEND_REF}:{path}\n' for path in paths).encode()
    result = subprocess.run(
        ('git', '-C', str(BE), 'cat-file', '--batch'),
        input=request,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f'后端 Git 批量读取失败({BACKEND_REF}):'
            f'{result.stderr.decode(errors="ignore").strip()}'
        )
    data = result.stdout
    cursor = 0
    blobs: dict[str, str] = {}
    for path in paths:
        header_end = data.find(b'\n', cursor)
        if header_end < 0:
            raise RuntimeError(f'后端 Git 批量输出不完整:{path}')
        header = data[cursor:header_end].decode(errors='ignore')
        cursor = header_end + 1
        if header.endswith(' missing'):
            raise RuntimeError(f'后端 ref 文件不存在:{path}')
        try:
            size = int(header.rsplit(' ', 1)[1])
        except (IndexError, ValueError) as error:
            raise RuntimeError(f'后端 Git 批量输出无法解析:{header}') from error
        blobs[path] = data[cursor:cursor + size].decode(errors='ignore')
        cursor += size + 1  # blob 后的换行
    return blobs


def _git_blob(path: str) -> Optional[str]:
    result = subprocess.run(
        ('git', '-C', str(BE), 'show', f'{BACKEND_REF}:{path}'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode(errors='ignore')


@dataclass(frozen=True)
class EndpointEquivalent:
    """A platform-equivalent contract backed by executable evidence.

    An entry is not an exemption. It is accepted only while every App endpoint
    exists in the backend, is reachable from non-API App code, and every
    backend evidence token remains present.

    ★ `app` 为空表示**产品层故意不接**(如 R10 收款模型:App 侧不发提现请求)。
      这种条目必须给出 App 侧替代实现的证据(`app_evidence`),否则判红 ——
      没有证据的空条目就是静默 allowlist。
    """

    mini: str
    app: tuple[str, ...]
    reason: str
    backend_evidence: tuple[tuple[str, tuple[str, ...]], ...]
    app_evidence: tuple[tuple[str, tuple[str, ...]], ...] = ()

    @property
    def display(self) -> str:
        if not self.app:
            return f'{self.mini} => (App 侧不发请求)'
        return f'{self.mini} => {" + ".join(self.app)}'


@dataclass(frozen=True)
class EndpointParityReport:
    gaps: list[str]
    documented: list[EndpointEquivalent]
    invalid: list[tuple[EndpointEquivalent, tuple[str, ...]]]


# Platform-specific protocols and aggregate reads. These are deliberately more
# than string mappings: classify_endpoints() re-reads backend routes, reachable
# App call sites, and the listed backend semantic evidence on every run.
_FUND_PREFLIGHT_CTRL = (
    'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/'
    'ApiFundActionPreflightController.java'
)
# R10:小程序侧的提现出口 —— 全仓唯一的客服微信号与弹窗(6 个入口都从这里取号)。
_R10_MINI_CS = ('chengyinhub-xcx/utils/withdraw-cs.js', (
    'WITHDRAW_CS_WECHAT_ID',
    'showWithdrawCsPopup',
))
# ★ 足迹分享快照(2026-09-18):令牌**只被微信小程序页面消费** ——
#   小程序分享的是 `onShareAppMessage` 的小程序 path,里面塞 `shareToken`,
#   出了微信打不开;App 侧分享的是**图**(系统分享面板 + PNG 足迹卡),
#   没有承载令牌的入站路由,所以 App 不发这两条请求。
_ROAM_SHARE_CTRL = (
    'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/'
    'ApiRoamShareController.java',
    ('@PostMapping("/snapshot")', '@PostMapping("/revoke")',
     '@GetMapping("/snapshot")', '漫游足迹分享快照'),
)
_ROAM_SHARE_MINI_PAGE = (
    'chengyinhub-xcx/subpackageRoam/session/index.js',
    ('options.shareToken', 'publishShareSnapshot', 'readShareSnapshot'),
)
_ROAM_SHARE_MINI_UTILS = (
    'chengyinhub-xcx/utils/roam-share-snapshot.js',
    ("url: '/api/roam/share/snapshot'", "url: '/api/roam/share/revoke'"),
)
# App 侧的替代实现 —— 分享出口就是这张 PNG 图本身。
_ROAM_SHARE_APP = ((
    'lib/feature/roam/roam_share_actions.dart',
    ('SharePlus.instance.share', 'XFile.fromData'),
), (
    'lib/feature/roam/roam_session_page.dart',
    ('roam-system-share', '_RoamShareSheet'),
))
# R10:App 侧的替代实现 —— 客服号弹窗本体 + 资产页提现入口。
_R10_WITHDRAWAL_DIALOG = ((
    'lib/feature/withdrawal/withdrawal_contact_dialog.dart',
    ('showWithdrawalContactDialog', 'kWithdrawalContactWechatId'),
), (
    'lib/feature/assets/assets_page.dart',
    ('assets-withdrawal-entry', 'showWithdrawalContactDialog'),
))
DOCUMENTED_EQUIVALENTS = (
    EndpointEquivalent(
        mini='/api/coop/deposit/create',
        app=(
            '/api/coop/deposit/create/app',
            '/api/coop/deposit/status',
        ),
        reason=(
            'same deposit preparation; App payment parameters differ and '
            'server status is the only payment terminal state'
        ),
        backend_evidence=((
            'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiCoopController.java',
            ('@PostMapping("/deposit/create")', 'prepareDeposit(',
             'createGenericOrder(', '@PostMapping("/deposit/create/app")',
             '@PostMapping("/deposit/status")', 'paymentStatus'),
        ),),
    ),
    EndpointEquivalent(
        mini='/api/getwxbindphone',
        app=('/api/sms/send', '/api/login/phone'),
        reason='Mini Program phone component is replaced by native SMS verification',
        backend_evidence=((
            'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiLoginController.java',
            ('@PostMapping("/getwxbindphone")', '@PostMapping("/sms/send")',
             '@PostMapping("/login/phone")', 'checkMscode('),
        ),),
    ),
    EndpointEquivalent(
        mini='/api/login/code',
        app=('/api/login/wechat/app',),
        reason='wx.login code is replaced by native WeChat Open Platform OAuth code',
        backend_evidence=((
            'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiLoginController.java',
            ('@PostMapping("/login/code")', '@PostMapping("/login/wechat/app")',
             '微信开放平台(原生App)'),
        ),),
    ),
    # ★ 非产品侧端点(2026-09-19 裁决,REPORT-a1-gap-close-verify-2 §四.1):
    #   小程序 github/master@3fa2b19 全历史零产品引用(唯一命中是 scripts/
    #   _verify_funnel.js 截图探针,被 _XCX_NON_PRODUCT 排除;tests/unit 那行
    #   反而是「产品不调 funnel」的负断言)⇒ 永不进等价候选集,本条目打印
    #   不出 `≡`,reachability 测试不得对它下 expect。保留本条是预验证据:
    #   若小程序将来真引用,合同即时生效;App 现经 marketing-home 聚合取
    #   funnel,兜底门禁见 test/blocked_by_backend_test.dart。
    EndpointEquivalent(
        mini='/api/merchant/funnel',
        app=('/api/merchant/marketing-home',),
        reason='marketing-home includes the same funnel payload',
        backend_evidence=(
            (
                'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java',
                ('@PostMapping("/funnel")', '@PostMapping("/marketing-home")',
                 'merchantAggregateReadService.marketingHome(memberId)'),
            ),
            (
                'chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantAggregateReadServiceImpl.java',
                ('result.put("funnel", funnel(memberId))',),
            ),
        ),
    ),
    EndpointEquivalent(
        mini='/api/registration/pay',
        app=('/api/registration/pay/app',),
        reason='same retry-payment service; only WeChat trade channel differs',
        backend_evidence=((
            'chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiRegistrationController.java',
            ('@PostMapping("/pay")', '@PostMapping("/pay/app")',
             'registrationCheckoutService.retryPayment('),
        ),),
    ),
    # ══════════════════════════════════════════════════════════════════
    # ★★ R10 收款模型(2026-09-15 定稿 §3 / 09-16 用户拍板):平台不打款。
    #    提现入口 = 弹客服微信号 + 「返回」「复制」;App 侧**不发任何提现请求**,
    #    也不做提现风险确认。下面 5 条是**故意不接**,不是缺口。
    #
    #    ⚠️ 为什么以前一直挂在缺口里:这一组两端都已废弃,但小程序的
    #    对账语料是**纯字符串命中** —— 小程序撤掉入口却把表单代码与注释留着
    #    (「暂留」),URL 就还在语料里。App 侧不接 = 和小程序**一致**,不是落后。
    #    证据:小程序 `txSheet.show` 只在 earnings/index.js 被置 false(无处置 true);
    #    后端这几条路由也都还在(下面逐条核对)—— 是产品决定,不是接口消失。
    # ══════════════════════════════════════════════════════════════════
    EndpointEquivalent(
        mini='/api/fund/preflight/bank-withdrawal',
        app=(),
        reason=(
            'R10:提现改弹客服微信号线下结算,App 侧不发提现请求;银行卡提现的'
            '风险确认(preflight)两端都已废(小程序 txSheet.show 只在 earnings/index.js '
            '被置 false,表单已无入口)'
        ),
        backend_evidence=(
            (_FUND_PREFLIGHT_CTRL, (
                '@RequestMapping("/api/fund/preflight")',
                '@PostMapping("/bank-withdrawal")',
                'service.prepareBankWithdrawal(',
            )),
            _R10_MINI_CS,
        ),
        app_evidence=_R10_WITHDRAWAL_DIALOG,
    ),
    EndpointEquivalent(
        mini='/api/fund/preflight/{challengeId}/confirm',
        app=(),
        reason='R10:同 bank-withdrawal —— 风险确认流程两端都已废,App 侧改弹客服微信号',
        backend_evidence=(
            (_FUND_PREFLIGHT_CTRL, (
                '@PostMapping("/{challengeId}/confirm")',
                'service.confirm(',
            )),
            _R10_MINI_CS,
        ),
        app_evidence=_R10_WITHDRAWAL_DIALOG,
    ),
    EndpointEquivalent(
        mini='/api/fund/preflight/{challengeId}/reject',
        app=(),
        reason='R10:同 bank-withdrawal —— 风险确认流程两端都已废,App 侧改弹客服微信号',
        backend_evidence=(
            (_FUND_PREFLIGHT_CTRL, (
                '@PostMapping("/{challengeId}/reject")',
                'service.reject(',
            )),
            _R10_MINI_CS,
        ),
        app_evidence=_R10_WITHDRAWAL_DIALOG,
    ),
    EndpointEquivalent(
        mini='/api/withdrawal/create',
        app=(),
        reason=(
            'R10:提现不在 App 内发起(只弹客服微信号线下结算),小程序也早已改弹客服微信'
            '(subpackageMember/tixian、components/cy/scene-route-content 都不再触达);'
            'App 只保留只读的 /api/withdrawal/list'
        ),
        backend_evidence=(
            ('chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiWithdrawalController.java', (
                '@PostMapping("/create")',
                'bankWithdrawalCommandService.submit(',
            )),
            _R10_MINI_CS,
        ),
        app_evidence=_R10_WITHDRAWAL_DIALOG,
    ),
    EndpointEquivalent(
        mini='/api/club/settlement/withdraw',
        app=(),
        reason=(
            'R10:俱乐部提现与会员提现同一出口(弹客服微信号),App 侧故意不封装'
            '(club_crm_api.dart 同一处注释);小程序 pages/club/settlement/index.js '
            '也注明不再由本页触达'
        ),
        backend_evidence=(
            ('chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiClubSettlementController.java', (
                '@PostMapping("/withdraw")',
                'withdrawal.fast-withdraw.enabled',
                'cashWithdrawService.withdraw(',
            )),
            ('chengyinhub-xcx/pages/club/settlement/index.js', (
                '不再由本页触达',
                'showWithdrawCsPopup',
            )),
        ),
        app_evidence=((
            'lib/feature/club/club_settlement_page.dart',
            # ★ R10 收口:这页不再自己写弹窗/自己存号 —— 「提现」直接调
            #   App 侧唯一出口(号与文案都在那个文件里)。
            ('showWithdrawalContactDialog', 'club-settlement-withdraw'),
        ),),
    ),
    # ══════════════════════════════════════════════════════════════════
    # ★ 足迹分享快照 · 平台差异(不是落后):令牌的**唯一消费者**是小程序页面。
    #   证据链:后端 `ApiRoamShareController` 只存/删/读快照;小程序
    #   `subpackageRoam/session/index.js` 从 `options.shareToken` 读,
    #   而 path 由 `onShareAppMessage` 出 —— 这条链路在微信之外打不开。
    #   App 侧分享走系统分享面板发 PNG 足迹卡(卡本身就是完整信息),
    #   既不产生服务端快照,也就没有要作废的东西。
    #   ⚠️ 将来若做「App 分享链接 → 落地页」,须先有 App 侧 shareToken
    #      入站路由,再把这两条从本清单移出并真正接上。
    # ══════════════════════════════════════════════════════════════════
    EndpointEquivalent(
        mini='/api/roam/share/snapshot',
        app=(),
        reason=(
            '小程序分享 path 专用:快照令牌只被 subpackageRoam/session 的 '
            'shareToken 入口消费(出微信打不开),App 分享的是系统面板里的 PNG '
            '足迹卡,不需要服务端快照,也没有承载令牌的入站路由'
        ),
        backend_evidence=(_ROAM_SHARE_CTRL, _ROAM_SHARE_MINI_PAGE,
                          _ROAM_SHARE_MINI_UTILS),
        app_evidence=_ROAM_SHARE_APP,
    ),
    EndpointEquivalent(
        mini='/api/roam/share/revoke',
        app=(),
        reason=(
            '同 snapshot:App 侧不发布服务端快照(分享出口是 PNG 图),'
            '没有快照可作废;小程序在「清空本机缓存」里作废自己发过的链接'
        ),
        backend_evidence=(_ROAM_SHARE_CTRL, _ROAM_SHARE_MINI_PAGE,
                          _ROAM_SHARE_MINI_UTILS),
        app_evidence=_ROAM_SHARE_APP,
    ),
)


def backend_endpoints() -> set:
    # page_parity.py 也直接调用本入口；验证必须放在共享边界，
    # 否则它会绕过 endpoint_parity.main() 对着过期 ref 报绿。
    verified_backend_commit()
    eps = set()
    paths = [path for path in _git_paths(API_CTRL_REL) if path.endswith('.java')]
    for s in _git_blobs(paths).values():
        m = re.search(r'@RequestMapping\("([^"]+)"\)', s)
        base = m.group(1) if m else ''
        for mm in re.finditer(r'@(?:Post|Get)Mapping\((?:value\s*=\s*)?"([^"]*)"', s):
            eps.add((base.rstrip('/') + '/' + mm.group(1).lstrip('/')).replace('//', '/'))
    return eps


def corpus(root: pathlib.Path, exts) -> str:
    return ' '.join(p.read_text(errors='ignore')
                    for e in exts for p in root.rglob('*' + e))


# ★★ 小程序语料里**不算**这几个目录:它们不是产品,只是验证工具。
#   2026-08-20 实证:`/api/official/invites` 被判成「小程序在用、App 没接」,
#   可小程序里**根本没有这个功能的界面** —— 唯一的调用方是
#   `scripts/_verify_today_e2e.js` 这个探测脚本。
#   照它去接,等于为一个两端都没有的功能做一套带资金条款的表单。
#   ⇒ 判「小程序在不在用」要看**产品代码**,不看它的测试与探针。
_XCX_NON_PRODUCT = ('/scripts/', '/tests/', '/docs/', '/node_modules/')

# ★★ 2026-09-19(b2)假降防御:小程序判据从「读共享工作树」改为「读 BACKEND_REF
#   的 Git 对象」。实证(#312 增量发现 1):/tmp/be-master 是共享仓,别的 worker
#   把它的**工作树**切到旧 release-0917 后,读工作树的判据就静默跟着旧树走 ——
#   cancel 三件套从缺口清单里隐身(19 而不是 22),page_parity 页面数基线也被
#   同因打红。后端判据早就钉死在 ref 上;小程序不该是唯一的例外。
_XCX_ROOT = 'chengyinhub-xcx'
_XCX_CORPUS_EXTS = ('.js', '.wxml', '.json')
_XCX_BLOBS: Optional[dict] = None


def xcx_blobs() -> dict:
    """BACKEND_REF 树里全部小程序产品代码(键 = 相对仓根路径)。

    一次性批量读(~7MB / 千余文件),同进程复用;与后端端点共用
    新鲜度门禁 —— 本地 github/master 过期时两边一起拒跑。
    """
    global _XCX_BLOBS
    if _XCX_BLOBS is None:
        verified_backend_commit()
        paths = [
            path for path in _git_paths(_XCX_ROOT)
            if path.endswith(_XCX_CORPUS_EXTS)
            and not any(seg in '/' + path for seg in _XCX_NON_PRODUCT)
        ]
        _XCX_BLOBS = _git_blobs(paths)
    return _XCX_BLOBS


def xcx_file_text(relative: str) -> Optional[str]:
    """读 ref 里单个小程序文件;`relative` 是相对 xcx 根的路径,不存在返回 None。"""
    return xcx_blobs().get(f'{_XCX_ROOT}/{relative}')


def xcx_product_corpus() -> str:
    """小程序**产品代码**语料,按 `BACKEND_REF` 读 blob —— **不读工作区**。

    ★★ 2026-09-17(P18):原来读工作区。本机镜像 checkout 在 release-0917
      (`7bdeb58d`),而新鲜度门禁认可的 `github/master` 是 release-0916
      (`1b3ca1c4`) —— 差两个 release commit,于是**同一次固定 commit 的对账,
      答案随 checkout 漂移**,两个方向各错一条:
        · 假红 `/api/club/lead/edit-ops`:只在工作区里有调用点,master 的
          `pages/club/topic-detail` 根本没调它 ⇒ 凭空多一条「缺口」,
          照着去接等于替一个未发布的改动作业。
        · 假绿 `/api/coop/candidates/reject`:master 的 `pages/coop/list`
          明明在调,工作区那条已不在 ⇒ 真缺口被藏掉。
      后端路由本来就是按 ref 读的;两端对同一个 commit,「可重现的审计快照」
      才成立(新鲜度门禁只校验 ref,校验不到 checkout)。
    """
    return ' '.join(xcx_blobs().values())


def _method_decls(src: str) -> list:
    """API 文件里的公开方法声明 → `[(名字, 方法体片段)]`(**不含接口声明**)。

    ★★ 2026-09-17(P18):`abstract interface class XGateway` 与
      `class XApi implements XGateway` 常写在**同一个文件**里,于是每个方法名
      出现两次、`dup[name]` 翻倍。而 dup 的用途是「同名方法会互相证明可达」——
      同名一多,判据就从「裸名匹配」升级成「必须带 receiver」,可 App 的调用点
      写的是**接口类型的字段**(`gateway.state(...)`、`_gateway.readReceipt(...)`、
      `gateway.leaderboard(...)`),receivers_of 认不出 ⇒ 真接通的端点被误报成缺口。
      实测 8 条: `/api/play/advanced/{start,action,state,leaderboard}` 与
      `/api/game/session/{view,command,receipt,merchant/entries}`。

      接口声明既没有 URL,也不可能是调用目标,没有资格参与 dup —— 剥掉。
    """
    declarations = list(re.finditer(r'^  Future(?:<.*?>)?\s+(\w+)\(', src, re.M))
    out = []
    for index, m in enumerate(declarations):
        if _is_bodyless(src, m.start()):
            continue
        end = (declarations[index + 1].start()
               if index + 1 < len(declarations) else len(src))
        out.append((m.group(1), re.sub(r'//[^\n]*', '', src[m.start():end])))
    return out


def _is_bodyless(src: str, start: int) -> bool:
    """参数表闭合后紧跟 `;` = 接口/抽象声明,没有方法体。"""
    depth = 0
    for index in range(start, len(src)):
        char = src[index]
        if char in '([':
            depth += 1
        elif char in ')]':
            depth -= 1
            if depth == 0:
                return src[index + 1:].lstrip().startswith(';')
    return False


def app_reachable_corpus() -> str:
    """只把「真有页面调得到」的 API 方法体拼进 App 语料。

    ★ 一个写好但没人调的客户端方法,对用户等于不存在。
      把它算成"已接通"会让对账表恒绿 —— 这是本项目反复出现的
      「闸放错层」:判的是代码存在性,该判的是可达性。

    ★★ 2026-08-20 补:可达是**传递**的。account_api 里
      `agreeSignupDataSharing` 被报名页调用,而它转调同文件的
      `recordConsent`(URL 就写在后者里)—— 只数「API 层之外的直接调用方」
      会把 /api/compliance/consents 误报成缺口。改成不动点迭代。

      ⚠️ 但传递的**起点必须是页面**:如果拿整个 blob 当判据,
      API 层内部互相调用会自己把自己证明成可达,和同名互证是一个病。
    """
    all_dart = {q: q.read_text(errors='ignore') for q in APP_LIB.rglob('*.dart')}
    blob = '\n'.join(all_dart.values())
    # 页面语料:API 层之外的全部代码(剥注释 —— 注释不是调用)。
    outer = '\n'.join(re.sub(r'//[^\n]*', '', v)
                      for k, v in all_dart.items() if '/data/api/' not in str(k))

    parts = []
    methods = []          # (owner_token, name, chunk)
    gateway_names = {}    # owner_token → 该 API 实现的接口名(同文件声明)
    for q, src in all_dart.items():
        if '/data/api/' not in str(q):
            # ★★ 非 API 文件也必须剥注释再计入。
            #   实测 models/points_statistics.dart 的文档注释里写着
            #   `/api/user/invite_list`,于是那条端点恒判「已接通」——
            #   而 App 里真正调它的方法零调用方。
            #   注释从来不是接通的证据,只有代码是。
            parts.append(re.sub(r'//[^\n]*', '', src))
            continue
        # ⚠️ 方法体不能用 `.*?\n  \}` 截 —— 命名参数块就长这样,
        #   非贪婪会停在签名里,把整个函数体(含 URL)切掉。
        #   切到下一个声明的起点,并剥注释(否则会带进下一个方法的 URL)。
        owner = re.sub(r'_(\w)', lambda k: k.group(1).upper(), q.name[:-len('.dart')])
        for name, chunk in _method_decls(src):
            methods.append((owner, name, chunk))
        # ★★ 2026-09-17(P18):页面拿到的往往是**接口类型**(`AdvancedPlayGateway
        #   gateway`、`GameSessionGateway? gateway`、`GameSessionGateway get _gateway`),
        #   而 receivers_of 只认具体类名 ⇒ `gateway.leaderboard(...)` 认不出 ⇒
        #   名字有歧义(start / leaderboard 各有多份实现)时判成缺口。记下同文件
        #   声明的接口名,和具体类名一起当 receiver 的类型证据。
        for m in re.finditer(r'abstract interface class (\w+)', src):
            gateway_names.setdefault(owner, set()).add(m.group(1))

    dup = {}
    for _, name, _c in methods:
        dup[name] = dup.get(name, 0) + 1

    def receivers_of(text: str, owner: str) -> list:
        """这段代码里,哪些标识符**就是**这个 API 的实例。

        ★★ 2026-08-20:光认 `xxxApiProvider).name(` 不够 ——
          实测 leaderboard_controller 写的是
              final api = ref.watch(growthApiProvider);
              ... api.leaderboard(...)
          归属正则认不出这个 receiver ⇒ **假缺口**。
          (方向和前两个毛病相反:那两个假绿,这个假红。
           假红同样有害 —— 它会让人去重建一个已经有的东西。)
        """
        # ★★ 2026-09-17:receiver 的**前缀**不一定是文件名。
        #   `advanced_play_api.dart` 派生出 owner `advancedPlayApi`,而 App 里
        #   真正的 provider 叫 `advancedPlayGatewayProvider`(providers.dart:232)
        #   —— 去掉 Api 后缀的那半截才是它。只认整词就漏 ⇒ play/advanced 四条
        #   明明接好了(advanced_play_controller.dart:75/152/185/238)却判成缺口。
        tokens = [owner]
        for suffix in ('Api', 'Gateway'):
            if owner.endswith(suffix) and len(owner) > len(suffix):
                tokens.append(owner[: -len(suffix)])
        # ⚠️ 大小写也要容忍:`merchantGameSessionApiProvider` 里那半截是
        #   `GameSessionApi`(首字母大写),而 owner 由文件名派生是小写的
        #   `gameSessionApi` —— 只认小写就把商家玩法节点页五条 game/session
        #   判成缺口,而它们真的接好了(_gateway.loadMerchantView 等)。
        head = ('(?i:(?:'
                + '|'.join(re.escape(t) for t in dict.fromkeys(tokens))
                + r')\w*)')
        # ⚠️ provider 名还会**带前缀**:`merchantGameSessionApiProvider`
        #   (merchant_game_node_page.dart:23)。锚在 `(` 后面就漏 ⇒
        #   商家玩法节点页五条 game/session 被判成缺口,而它用 getter 接得好好的
        #   (`GameSessionGateway get _gateway => ... ref.read(merchantGameSessionApiProvider)`,
        #    :78 —— 调用点在 :1390 那一串)。
        #   所以绑定正则一律容忍前后缀,只要求 owner token 出现在 provider 名里。
        bind = r'\w*' + head + r'\w*\s*\)'
        names = [head + r'\s*\)?']
        # ⚠️ 绑定模式要**贴着真实惯用法**写死,别用 `[^;]*` 兜 ——
        #   第一版就是那么写的,而 provider 声明本身直到很后面才有分号,
        #   于是 `final leaderboardProvider = FutureProvider(... ref.watch(growthApiProvider);`
        #   把外层的 leaderboardProvider 当成了 receiver,内层真正的 `api` 反而没收进来。
        # ★ 2026-09-17:写法收成一条 —— **锚在 provider 调用上再往回看绑定名**。
        #   两种惯用法都要认:`final api = ref.watch(x)` 与
        #   `XGateway get _api => widget.api ?? ref.read(x)`(实测 activity_waitlist_section
        #   就是这个写法,三条候补接口曾因此被误报成缺口)。
        #   反过来写(大正则逐字符扫整个语料)实测把一次对账从 60s 拖到 5.5 分钟。
        for m in re.finditer(
                r'(?:final|var)\s+(\w+)\s*=\s*(?:await\s+)?'
                r'ref\s*\.\s*(?:watch|read)\s*\(\s*'
                + bind, text):
            names.append(re.escape(m.group(1)))
        # ★★ 2026-09-17 补第三种:receiver 由 **getter** 绑定。
        #   实测 activity_waitlist_section 写的是
        #       ActivityWaitlistGateway get _api =>
        #           widget.api ?? ref.read(activityWaitlistApiProvider);
        #       ... _api.status(...)
        #   —— 既不是局部变量也不是 lambda 参数,前两种写法都认不出,
        #   于是 /api/club/event-ops/waitlist/* 三条被判成「页面够不着」。
        #   而这个页面就是「候补区」本身:照那条假红去接,等于重造一个已经有的东西。
        for m in re.finditer(
                r'get\s+(\w+)\s*=>[^;]{0,400}?'
                r'ref\s*\.\s*(?:watch|read)\s*\(\s*'
                + bind, text, re.S):
            names.append(re.escape(m.group(1)))
        # ★★ 2026-09-17 再补第四种:receiver 由**构造命名参数**绑定。
        #   实测 play_session_page 写的是
        #       AdvancedPlayController(gateway: ref.read(advancedPlayGatewayProvider), ...)
        #   而 controller 里写的是 `gateway.start(...)` / `gateway.state(...)`。
        #   绑定发生在**另一处、另一个文件**的命名参数上,前三路都认不出 ⇒ 假红。
        #   ⚠️ 这比「重造已经有的东西」更贵:play/advanced 四条**真的接好了**
        #      (advanced_play_controller.dart:75/152/185/238),照假红重新接一遍
        #      等于把整条玩法链改成两套。
        for m in re.finditer(
                r'(\w+)\s*:\s*(?:await\s+)?ref\s*\.\s*(?:watch|read)\s*\(\s*'
                + bind, text):
            names.append(re.escape(m.group(1)))
        # ★★ 2026-09-17 再补第五种(main #99 的 lookback):绑定名**紧贴**在 provider 调用前,
        #   不限 final/var/get —— 兜住 `late X _api = ref.read(...)` 这类漏网写法。
        for m in re.finditer(
                r'ref\s*\.\s*(?:watch|read|listen)\s*\(\s*'
                + head + r'\s*\)', text):
            head_txt = text[max(0, m.start() - 120):m.start()]
            bind = re.search(
                r'(?:get\s+)?(\w+)\s*(?:=>|=)\s*'
                r'(?:widget\s*\.\s*\w+\s*\?\?\s*)?(?:await\s*)?$', head_txt)
            if bind:
                names.append(re.escape(bind.group(1)))
        # ★★ 2026-08-20 再补一种:receiver 由**类型标注**绑定。
        #   实测 template_edit_page 写的是
        #       _run((TemplateApi a) => a.publish(_draft), okMsg: '已发布')
        #   —— a 是 lambda 参数,不是 ref.watch 出来的。
        #   和局部变量那次同一个病:归属只认一种写法,别的写法就假红。
        cls = owner[0].upper() + owner[1:]          # templateApi → TemplateApi
        # `X? name`(可空字段)、`X get _api`(widget 覆盖的 getter)、`X name` 三种绑定。
        for type_name in sorted({cls, *gateway_names.get(owner, ())}):
            for m in re.finditer(
                    r'\b' + re.escape(type_name) + r'\b\??\s*(?:get\s+)?(\w+)',
                    text):
                names.append(re.escape(m.group(1)))
        return names

    def called_in(text: str, owner: str, name: str) -> bool:
        if name.startswith('_'):
            return True                       # 私有辅助:随宿主一起算
        if dup[name] > 1:
            # ★★ 同名方法会互相证明可达。实测 `inviteList` 在 coop_api
            #   和 registration_api 各一份,只有前者被调用,裸名匹配算成
            #   两份都通,/api/user/invite_list 就此从清单里消失。
            #   歧义名一律要求调用点自报归属(`xxxApi.name(`)。
            return any(
                re.search(r'\b' + recv + r'\s*\.\s*' + re.escape(name)
                          + r'\s*\(', text)
                for recv in receivers_of(text, owner))
        return re.search(r'\b' + re.escape(name) + r'\s*\(', text) is not None

    reached = {i for i, (o, n, _c) in enumerate(methods) if called_in(outer, o, n)}
    # 不动点:已可达方法体里调到的,也可达。
    while True:
        frontier = '\n'.join(methods[i][2] for i in reached)
        grown = {i for i, (o, n, _c) in enumerate(methods)
                 if i not in reached and called_in(frontier, o, n)}
        if not grown:
            break
        reached |= grown

    parts.extend(methods[i][2] for i in sorted(reached))
    return ' '.join(parts)


# App 侧那条路径是拼出来的:`'/api/club/open-settings/$pathTail'`。
# 端点表里是拼完的 `/api/club/open-settings/member-post`,字面量对不上 —— 于是
# 「俱乐部三个开放开关」被判成「App 里压根没有」,**而它的客户端与页面都在**
# (club_topic_ops_api.dart:238 / club_detail_page.dart:1123)。
# 照那条假红去接 = 重造一个已经有的东西(和 getter 那次同一个病)。
_INTERP_LITERAL = re.compile(r'["\'`](/api/[^"\'`]*\$[^"\'`]*)["\'`?]')


def _matches_interpolated(ep: str, text: str) -> bool:
    for m in _INTERP_LITERAL.finditer(text):
        rx = re.escape(m.group(1))
        rx = re.sub(r'\\\$\\\{[^}]*\\\}|\\\$\w+', '[^/]+', rx)
        if re.fullmatch(rx, ep):
            return True
    return False


def hit(ep: str, text: str) -> bool:
    """Return whether corpus contains this exact or interpolated endpoint.

    A plain substring is insufficient: a child endpoint must not prove its
    parent, and a variable parent must not prove every sibling action.
    """
    if '{' not in ep:
        for match in re.finditer(re.escape(ep), text):
            following = text[match.end():match.end() + 1]
            if following not in ('/',) and not following.isalnum():
                return True
        return _matches_interpolated(ep, text)
    head = ep.split('{')[0].rstrip('/')
    if head not in text:
        return False
    tail = [segment for segment in ep.split('}')[-1].split('/') if segment]
    if not tail:
        return True
    for match in re.finditer(re.escape(head), text):
        window = text[match.start():match.start() + 200]
        if all(segment in window for segment in tail):
            return True
    return _matches_interpolated(ep, text)


def _equivalent_failures(
        spec: EndpointEquivalent,
        endpoints: set[str],
        app: str) -> tuple[str, ...]:
    failures = []
    for endpoint in spec.app:
        if endpoint not in endpoints:
            failures.append(f'backend route missing:{endpoint}')
        if not hit(endpoint, app):
            failures.append(f'App call site unreachable:{endpoint}')
    for relative_path, tokens in spec.backend_evidence:
        source = _git_blob(relative_path)
        if source is None:
            failures.append(f'backend evidence file missing:{relative_path}')
            continue
        for token in tokens:
            if token not in source:
                failures.append(f'backend evidence missing:{token}')
    if not spec.app and not spec.app_evidence:
        failures.append('absence without App-side evidence')
    for relative_path, tokens in spec.app_evidence:
        path = APP_ROOT / relative_path
        if not path.is_file():
            failures.append(f'App evidence file missing:{relative_path}')
            continue
        source = path.read_text(errors='ignore')
        for token in tokens:
            if token not in source:
                failures.append(f'App evidence missing:{token}')
    return tuple(failures)


def classify_endpoints(
        endpoints: set[str],
        app: str,
        xcx: str,
        equivalents=DOCUMENTED_EQUIVALENTS,
        backend_endpoints: Optional[set[str]] = None) -> EndpointParityReport:
    """Classify Mini-only endpoints without silently allowlisting them."""
    candidates = sorted(
        endpoint for endpoint in endpoints
        if not hit(endpoint, app) and hit(endpoint, xcx)
    )
    by_mini = {spec.mini: spec for spec in equivalents}
    gaps = []
    documented = []
    invalid = []
    for endpoint in candidates:
        spec = by_mini.get(endpoint)
        if spec is None:
            gaps.append(endpoint)
            continue
        failures = _equivalent_failures(
            spec,
            backend_endpoints if backend_endpoints is not None else endpoints,
            app,
        )
        if failures:
            gaps.append(endpoint)
            invalid.append((spec, failures))
        else:
            documented.append(spec)
    return EndpointParityReport(gaps, documented, invalid)

def main() -> int:
    try:
        backend_commit = verified_backend_commit()
        eps = backend_endpoints()
        xcx = xcx_product_corpus()
    except RuntimeError as error:
        # ★ 查不了就报错,不是「跳过」——
        #   静默返回 0 会让「缺口 0 条」和「压根没查」长得一模一样。
        print(error, file=sys.stderr)
        return 2
    app = app_reachable_corpus()

    # ★ 语料下限:读空了会让「缺口 0 条」看起来像做完了。
    assert len(eps) > 300, f'只解析到 {len(eps)} 个端点 —— 控制器目录变了?'
    assert len(xcx) > 1_000_000, f'小程序语料只有 {len(xcx)} 字节 —— 路径错了?'
    assert '/api/user/info' in xcx, '小程序语料里连 /api/user/info 都没有 —— 解析失效'
    # ★ App 语料同样要有下限:可达性过滤写错了会把语料滤空,
    #   那时「缺口=全部」和「缺口=0」都不是真相,而是解析坏了。
    assert len(app) > 300_000, f'App 可达语料只有 {len(app)} 字节 —— 可达性过滤失效?'
    assert '/api/im/messages' in app, 'App 语料里连聊天接口都没有 —— 过滤把真接通的也滤掉了'

    report = classify_endpoints(eps, app, xcx)
    absences = [spec for spec in report.documented if not spec.app]
    print(
        f'总端点 {len(eps)} · 未解释缺口 {len(report.gaps)} 条'
        f' · documented equivalent {len(report.documented) - len(absences)} 条'
        f' · documented absence {len(absences)} 条'
        f' · 等价合同未成立 {len(report.invalid)} 条'
        f' · backend {BACKEND_REF}@{backend_commit[:12]}'
    )
    for e in report.gaps:
        print(' ', e)
    for spec in report.documented:
        mark = '≡' if spec.app else '⊘'
        print(f'  {mark} {spec.display} · {spec.reason}')
    for spec, failures in report.invalid:
        print(f'  ! {spec.display} · {"; ".join(failures)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
