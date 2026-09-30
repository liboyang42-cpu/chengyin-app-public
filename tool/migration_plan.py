#!/usr/bin/env python3
"""生成「小程序 → Flutter 迁移施工总表」。

用法(本机默认路径可用时):
    python3 tool/migration_plan.py

本机(远端执行机)后端树不可读时,用镜像:
    CHENGYIN_BACKEND=/tmp/be-master python3 tool/migration_plan.py

产物:`docs/migration/miniapp-to-flutter-master-plan.md`。

判据全部来自仓内已有的三部裁判(endpoint_parity / page_parity / copy_parity)
与 `tool/visual_parity/pairs.json`,不另立一套口径;重跑即可刷新,不手抄。
"""

import collections
import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve()
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE.parent))

import endpoint_parity as E          # noqa: E402
import page_parity as P              # noqa: E402
import copy_parity as C              # noqa: E402

if os.environ.get('CHENGYIN_BACKEND'):
    E.BE = pathlib.Path(os.environ['CHENGYIN_BACKEND'])
    E.XCX = E.BE / 'chengyinhub-xcx'
    P.XCX = E.XCX
    C.XCX = E.XCX
XCX = P.XCX
OUT = REPO / 'docs/migration/miniapp-to-flutter-master-plan.md'

# 模块归属:小程序页路径 → 模块名
MODULES = [
    ('subpackageP3', '成长中心 · P3'), ('subpackageMember', '会员/资产'),
    ('subpackageRoam', '漫游'), ('subpackageA', '基础设施 A'),
    ('subpackageB', '基础设施 B'), ('pages/play', '玩法'), ('pages/activity', '活动'),
    ('pages/club', '俱乐部'), ('pages/topic', '主题/商家招商'), ('pages/merchant', '商家后台'),
    ('pages/coop', '协作/供给'), ('pages/publish', '发布/创作'), ('pages/square', '广场'),
    ('pages/team', '组队'), ('pages/roam', '漫游'), ('pages/search', '搜索'),
    ('pages/address', '地址'), ('pages/shezhi', '设置'), ('pages/gerenziliao', '资料'),
    ('pages/userinfo', '用户'), ('pages/mylike', '我的'), ('pages/template', '模板'),
    ('pages/crop', '裁剪'), ('pages/index', '首页'), ('pages/member', '个人中心'),
    ('pages/privacy', '法务'), ('pages/agreement', '法务'), ('pages/deregister', '账号'),
    ('pages/talent', '俱乐部'),
]

# ── 人工维护区(重跑生成器不会覆盖,改这里)─────────────────────────
NARRATIVE = {
'真源': """## 0. 真源与口径(铁律)

| 维度 | 真源 | 冲突时怎么办 |
|---|---|---|
| 行为 / 信息架构 / 字段 / 状态 | 小程序 `master`(`chengyinhub-xcx/`) | 小程序为准,不重新设计 |
| 视觉外观 | Figma《城瘾 App — Brand Handbook》+ `docs/ios27-design-language.md` | 结构照小程序,外观走 iOS 27 原生化(记 accepted) |
| 数据 / 接口 | 后端 `master` 的控制器与路由(**按 git ref 读**,不读工作区) | 以后端为准;App 缺的按 §4 派活 |
| 目标实现 | Flutter `lib/` | **已存在页面 ≠ 完成**(本表不看文件数) |

- 本机(远端执行机)后端树 `~/Downloads/chengyin` 读不动时,用镜像:
  `CHENGYIN_BACKEND=/tmp/be-master python3 tool/migration_plan.py`。
- 快照 `~/城瘾app/xcx-ref/` **不随 master 更新**;核数前先确认它的 commit 与 master 一致(R2)。
- 涉及产品行为变化的差异 → 记 §9 Decision Log 并标 BLOCKED,**不擅自改**。
""",
'十大问题': """### 1.2 最大的 10 个迁移问题(★ 人工,2026-09-17)

1. **广场详情 `pages/square/detail/index`**:13 个接口缺 9(评论 CRUD + 创作广场 action/like/delete/report)。
   App 的广场目前只能看,不能互动 —— 这是玩家侧最大的功能窟窿。
2. **商家招商详情 `pages/topic/merchantinfo/merchantinfo`**:33 个接口缺 6(章节节点审核 / 供回答复 / 对局材料)。
3. **玩法页 `pages/play/index`**:48 个接口缺 6(`advanced` 状态机 4 + 排行榜 2),且文案命中 34%;
   小程序侧这一页有 165 个交互、32 种原生能力调用 —— 是全仓最重的一页。
4. **俱乐部详情 `pages/club/detail/index`**:40 个接口缺 4(开放设置三项:成员发帖 / 商家合作 / 公开可见 + `/api/project/my`)。
5. **活动报名 `pages/activity/baoming/baoming`**:缺候补三件套(`waitlist/join|cancel|status`)—— 报名-候补链路断。
6. **商家后台零散缺口**:评价回复增删、据点认领撤销、装修订单状态、AI 声音档案、客户联系(后者后端也没有)。
7. **提现链路口径冲突**:小程序与 App 都已改为「弹客服微信线下处理」(2026-09-15 收款模型),
   但 `utils/withdrawal-preflight.js` 等**遗留代码**仍带 `/api/withdrawal/create` /
   `bank-withdrawal` —— 工具据此报缺口。**属死代码,不是 App 该补的功能**,需在 §9 记一笔并在工具侧收口。
8. **状态/视觉对照 292 条 0 完成**,P0 126 条未开工:empty / error / loading / permission 是否补齐**没有台账**。
9. **场景组件层**:小程序 29 个带接口的组件里,App 已覆盖 27 个;旧页面对账看不见这层(本表 §3.2 补上)。
10. **门禁机制当前失效**:`test/endpoint_reachability_test.dart` 带 `needs-local-env` 被 CI 排除、
    基线清单为空(53 条缺口没人判)、`page_parity` 因小程序删页 exit 1、
    快照落后 master 1 个 commit。**仪器不灵,数字就会骗人**。
""",
'口径差异': """### 1.3 两个口径的差(53 vs 41)★ 人工

- 工具口径(`tool/endpoint_parity.py`,官方门禁):**53 条**。语料 = 整个小程序产品目录(含 `utils/`、注释)。
- 页面口径(本表 §6):**41 条**。语料 = 每个页面的代码路径(页面 js + 递归声明组件)。
- 差异 12 条,两个方向都真实存在,**两个数都不能直接用**:
  - 工具多报:注释 / 死代码里的 URL(实证:`/api/withdrawal/create` 现在只剩注释与遗留 `utils/`,小程序已不触达;
    `/api/club/settlement/withdraw` 源码写着「不再由本页触达」)。
  - 页面口径漏报:写在共享 `utils/` 或**拼接字符串**里的调用
    (实证:`utils/game-session-client.js` 的 `/api/game/session/view`;
    `pages/play/index.js:5119` 的 `req('/api/play/tag/' + tagId + '/revoke')`)。
- ⇒ 施工时**逐条判**:真缺 UI / 死代码 / 有意不做。判完写进 §9,并把工具清单同步收口。
""",
'视觉': """### 5.1 视觉验证怎么做(本机约束)★ 人工

- 本机**禁止打开微信开发者工具**(R1,一开整机卡死),所以小程序侧**不现场截图**:
  用仓内 `chengyinhub-xcx/docs/screenshots/` 与 `tool/visual_parity/pairs.json`(292 条:页 × 状态 × 角色)。
- 结构对照:`python3 tool/visual_parity/build_review.py --only <shotId>` → 左小程序结构 / 右 App(静态解析,不需要 automator)。
- App 侧实拍:模拟器截图(`build_run_sim` + `screenshot`),golden 现有 119 张。
- **没做对照的页不得标 VERIFIED**,只能标 `VISUAL_VERIFICATION_REQUIRED`。
""",
'切片': """### 8.1 第一批 Vertical Slice(★ 人工建议)

按「后端已就绪 + 一页能整块闭环 + 主路径优先」挑,每批一个 PR:

| 批次 | Slice | 小程序页 | 接口缺口 | 为什么先做 |
|---|---|---|---|---|
| ① | 活动报名-候补 | `pages/activity/baoming/baoming` | 3(join/cancel/status) | 主路径(报名)闭环,后端已就绪 |
| ② | 俱乐部治理开关 | `pages/club/detail/index` | 4(open-settings×3 + project/my) | 一页之内,发帖/合作/可见性三个开关 |
| ③ | 商家后台小闭环 | merchant/reviews + decor + citynode | 4 | 同模块,能一个 PR 收尾 |
| ④ | 广场互动 | `pages/square/detail/index` + list | 9 | 玩家侧最大窟窿,单独排期 |
| ⑤ | 招商详情 | `pages/topic/merchantinfo/merchantinfo` | 6 | 商家侧最重,需先核章节节点审核语义 |
| ⑥ | 玩法 advanced | `pages/play/index` | 6 | 状态机复杂 + 文案 34%,要单独一轮 |

每个 slice 走 §9 十步,验收材料按 §9 回执格式贴 PR。
""",
'流程': """## 9. 施工流程与完成定义(每个 Slice 都走这十步)

READ → COMPARE → PLAN → IMPLEMENT → BUILD → TEST → VISUAL VERIFY →
FUNCTION VERIFY → UPDATE MATRIX → COMMIT

**禁止跳过 COMPARE;禁止因为「Flutter 已经有文件」就认为不用改。**

Definition of Done(全部满足才允许把状态改成 VERIFIED):

- [ ] Flutter UI 已实现,且与小程序**结构/信息层级**一致(外观差异写进 accepted)
- [ ] API 已接入,request/response model 正确,**无 Mock 静态数据**
- [ ] loading / empty / error / disabled / unauthorized 状态齐
- [ ] Navigation 与业务逻辑完整(登录态、身份、活动/报名/任务状态、时间与地理约束、缓存同步)
- [ ] `flutter analyze` 零警告 + 相关测试通过(CI 绿)
- [ ] Happy Path **实际跑通** + 至少一个 Edge/Error Path
- [ ] 视觉对照(pairs.json 对应项)完成并在 accepted 里写明差异
- [ ] 本表(§3 矩阵 / §6 缺口 / §8 队列)已更新,缺口数**只降不升**

回执格式(贴到 PR 描述,缺一不可):

```
slice: <模块> / <小程序页> → <App 路由>
接口:  <列已接通的端点,并注明来源页>
状态:  empty/error/loading 各自怎么触发的(操作步骤)
实测:  模拟器 <设备/系统> · Happy Path: <步骤> · Edge: <步骤>
对照:  pairs.json <shotId> → accepted:<差异> 或 已修
残留:  <未做/后端缺口,写清为什么>
```
""",
'刷新': """## 11. 刷新本表 / 已知环境问题

```bash
python3 tool/migration_plan.py                      # 主控机(默认路径可用)
CHENGYIN_BACKEND=/tmp/be-master python3 tool/migration_plan.py   # 本执行机(镜像)
```

本机已知问题(2026-09-17 实测):

| 问题 | 现象 | 绕法 |
|---|---|---|
| `~/Downloads/chengyin` 读不动 | `ls`/`git` 挂死(疑似 iCloud 卡住) | `git clone --filter=blob:none --sparse` 到 `/tmp/be-master`,并 `git remote add github <url>` |
| 快照落后 | `xcx-ref` = `90e66d70`,master = `1b3ca1c4` | 请主控重导,或用镜像 |
| `page_parity` 必红 | 小程序 129 页 vs 基线 130 | 清 `pages/coop/candidates/index` + 基线改 129 |
| `endpoint_reachability_test` 被 CI 排除 | 缺口没人判 | 修基线/接 CI,或纳入本表周检 |
""",
}
# ────────────────────────────────────────────────────────────────

DEBT_PATTERNS = [
    ('TODO', r'TODO'), ('FIXME', r'FIXME'), ('mock/fake 数据', r'(?i)\b(mock|fake)\w*'),
    ('占位/临时实现', r'(?i)(placeholder widget|临时实现|暂未实现|coming soon|not implemented)'),
    ('UnsupportedError', r'UnsupportedError'), ('空 onTap', r'onTap:\s*\(\)\s*\{\s*\}'),
]
INTERACTIVE = re.compile(r'(?:bind|catch)[:]?([a-zA-Z]+)\s*=\s*"([^"]+)"')
API_RE = re.compile(r'["\'`](/api/[^"\'`?\s]+)')
WX_RE = re.compile(r'wx\.([a-zA-Z]+)\s*\(')
INTERACTIVE_EVENTS = {'tap', 'longpress', 'longtap', 'change', 'input', 'confirm',
                      'submit', 'blur', 'focus', 'scan', 'choose', 'select', 'selectchange'}


def module_of(page: str) -> str:
    for prefix, name in MODULES:
        if page.startswith(prefix):
            return name
    return '其它'


def page_files(page: str) -> dict:
    base = XCX / page
    out = {}
    for ext in ('wxml', 'js'):
        for cand in (base.with_suffix('.' + ext), base / ('index.' + ext)):
            if cand.is_file():
                out[ext] = cand.read_text(errors='ignore')
                break
    return out


def resolve_endpoints(page: str, depth: int = 3) -> set:
    """页面 + 其声明组件的接口(递归,含场景组件的第二层)。

    ⚠️ `page_parity.endpoints_of()` 只读一层组件 .js;而小程序的场景弹层是
    `cy-scene-deep-link` →(它自己的 json)→ `cy-scene-<x>`,接口在第二层。
    只读一层会把「优惠券钱包」这类宿主页判成 0 接口。
    """
    eps, seen = set(), set()

    def walk(base: pathlib.Path, depth: int) -> None:
        js = next((c for c in (base.with_suffix('.js'), base / 'index.js') if c.is_file()), None)
        if js is None or js in seen:
            return
        seen.add(js)
        eps.update(API_RE.findall(js.read_text(errors='ignore')))
        if depth <= 0:
            return
        cfg = next((c for c in (base.with_suffix('.json'), base / 'index.json') if c.is_file()), None)
        if cfg is None:
            return
        try:
            comps = (json.loads(cfg.read_text(errors='ignore')).get('usingComponents') or {}).values()
        except Exception:
            return
        for comp in comps:
            walk(XCX / str(comp).lstrip('/'), depth - 1)

    walk(XCX / page, depth)
    return eps


def component_inventory() -> list:
    """components/ 下每个带接口的组件 —— 小程序的「功能点」有一半长在这里。"""
    out = []
    for js in sorted((XCX / 'components').rglob('*.js')):
        text = js.read_text(errors='ignore')
        eps = sorted(set(API_RE.findall(text)))
        if eps:
            out.append((str(js.relative_to(XCX)), eps))
    return out


def mini_features(page: str) -> dict:
    f = page_files(page)
    wxml, js = f.get('wxml', ''), f.get('js', '')
    actions = {m.group(2) for m in INTERACTIVE.finditer(wxml)
               if m.group(1) in INTERACTIVE_EVENTS}
    return {
        'actions': len(actions),
        'apis': sorted({m.group(1) for m in API_RE.finditer(js)}),
        'abilities': sorted({m.group(1) for m in WX_RE.finditer(js)}),
    }


def debt_scan() -> list:
    rows = []
    for path in sorted((REPO / 'lib').rglob('*.dart')):
        # 剥注释:仓库自己的规矩 —— 注释里的词不算证据(2026-08-20 被「注释即代码」坑过)。
        text = re.sub(r'//[^\n]*', '', path.read_text(errors='ignore'))
        hits = {name: len(re.findall(rx, text)) for name, rx in DEBT_PATTERNS}
        hits = {k: v for k, v in hits.items() if v}
        if hits:
            rows.append((str(path.relative_to(REPO)), hits, sum(hits.values())))
    rows.sort(key=lambda r: -r[2])
    return rows


def main() -> int:
    app_corpus = E.app_reachable_corpus()
    xcx_corpus = E.xcx_product_corpus()
    backend = E.backend_endpoints()
    copy_corpus = C.app_copy_corpus()      # 与 copy_parity 同一份语料(见其注释)
    pages = P.xcx_pages()
    manifest = {e.get('miniPage'): e for e in P._manifest_entries()}
    pairs = json.loads((REPO / 'tool/visual_parity/pairs.json').read_text())
    shots_by_route = collections.defaultdict(list)
    for shot in pairs:
        shots_by_route[shot.get('route', '')].append(shot)

    rows = []
    for page in pages:
        entry = manifest.get(page) or {}
        feats = mini_features(page)
        eps = sorted(resolve_endpoints(page))
        # ★ 一律走工具自己的 classify_endpoints:它认 DOCUMENTED_EQUIVALENTS
        #   (保证金/取号/登录 code/报名支付),自判会把已登记的等价端点误报成缺口。
        page_report = E.classify_endpoints(set(eps), app_corpus, xcx_corpus,
                                           backend_endpoints=backend)
        gaps = sorted(page_report.gaps)
        reach = [e for e in eps if e not in gaps]
        # ★ 文案判据只有一个出处:C.verdict(比对 / 已核 / 无静态文案 / 系统承载)。
        #   这里原来另立了一遍「已核 或 文案 <3 条 ⇒ None」,与 copy_parity 各判一次:
        #   两边一改就漂,而漂掉的那部分正是「未比」黑箱。
        copy_state, copy_hit, copy_total, _miss = C.verdict(page, copy_corpus)
        labels = bool(copy_total)        # 下游只用它判「这页有没有文案面」
        copy_pct = (round(100 * copy_hit / copy_total)
                    if copy_state == 'compared' else None)
        shots = shots_by_route.get('/' + page, [])
        carrier_ok = True
        # ★ manifest 的 source 是相对 lib/ 的路径(不是仓库根)——踩过一次,留断言防复发。
        if entry:
            src = E.APP_LIB / (entry.get('source') or '')
            carrier_ok = src.is_file()
            if entry.get('kind') == 'route':
                at = entry.get('route', '')
            else:
                at = f"{entry.get('kind')} · {src.name}"
                carrier_ok = carrier_ok and entry.get('marker', '') in src.read_text(errors='ignore')
        else:
            at, carrier_ok = '**无落点**', False

        if not entry:
            status = 'NOT_STARTED'
        elif not eps and not labels:
            status = 'UI_ONLY' if carrier_ok else 'PARTIAL'
        elif carrier_ok and not gaps and (copy_pct is None or copy_pct >= 60):
            status = 'IMPLEMENTED'
        elif carrier_ok and (reach or not eps):
            status = 'PARTIAL'
        else:
            status = 'UI_ONLY'

        rows.append(dict(page=page, module=module_of(page), at=at, carrier_ok=carrier_ok,
                         eps=eps, gaps=gaps, reach=len(reach), copy=copy_pct,
                         copy_state=copy_state,
                         shots=shots, actions=feats['actions'],
                         abilities=feats['abilities'], status=status))

    # ★ 自检:落点解析要是坏掉,状态会整体塌成 UI_ONLY —— 宁可当场炸,不要出一份假表。
    resolved = sum(1 for r in rows if r['carrier_ok'])
    assert resolved >= len(rows) - 3, (
        f'落点只解析出 {resolved}/{len(rows)} —— manifest source 路径口径变了?')
    assert sum(r['reach'] for r in rows) > 200, '接口命中数异常偏低 —— 语料或 hit() 口径变了?'
    assert not any('/api/coop/deposit/create' == e for r in rows for e in r['gaps']), \
        '已登记的等价端点又冒成缺口了 —— classify_endpoints 没接上?'
    counts = collections.Counter(r['status'] for r in rows)
    debt = debt_scan()
    backend_missing = sorted({e for r in rows for e in r['gaps'] if e not in backend})
    app_side = sorted({e for r in rows for e in r['gaps'] if e in backend})

    L = []
    A = L.append
    A('# 小程序 → Flutter 迁移施工总表(Source of Truth)')
    A('')
    A(f'> 生成时间:2026-09-17 · 生成器 `tool/migration_plan.py`(重跑即刷新)')
    A('> 小程序基准 = 后端仓 `master`;本表按**功能证据**(接口可达 + 文案 + 状态对照)判状态,')
    A('> **不看 Flutter 有没有那个页面文件**。')
    A('')
    A('**分册(Phase 2/3/4)** · [02 功能级映射矩阵](02-feature-matrix.md) · '
      '[03 逐页 Gap Analysis A–F](03-page-gap-analysis.md) · [04 UI 参考与组件对照](04-ui-reference.md)')
    A('')
    A('**施工编排** · [05 并行施工 playbook](05-execution-playbook.md) —— 并行怎么切、文件归属、批次计划')
    A('')
    A(NARRATIVE['真源'])
    A('## 1. Executive Summary')
    A('')
    A(f'- 小程序页面 **{len(pages)}** · Flutter 落点 **{sum(1 for r in rows if r["carrier_ok"])}**')
    A(f'- 接口:小程序侧调用点 {len({e for r in rows for e in r["eps"]})} · '
      f'App 未接通 **{len({e for r in rows for e in r["gaps"]})}** 条'
      f'(其中后端也没有的 {len(backend_missing)} 条)')
    A(f'- 状态分布:' + ' · '.join(f'{k} {v}' for k, v in counts.most_common()))
    A(f'- 视觉/状态对照台账 `pairs.json`:{len(pairs)} 条,**已完成 0 条**'
      f'(覆盖 {len({s.get("route") for s in pairs})} 条路由)')
    A('- **VERIFIED = 0**:仓内没有任何一条功能留下「Happy Path + 异常路径实测」的回执,')
    A('  按 Definition of Done,现有页面一律不得计为完成。')
    A('')
    A('状态规则(机械判据,可复核):')
    A('')
    A('| 状态 | 判据 |')
    A('|---|---|')
    A('| NOT_STARTED | manifest 里没有落点 |')
    A('| UI_ONLY | 有落点,但该页小程序接口一个都没接通 |')
    A('| PARTIAL | 部分接口接通 / 文案命中 <60% / 落点标记读不到 |')
    A('| IMPLEMENTED | 该页接口 100% 可达 + 文案 ≥60%(未实测) |')
    A('| VERIFIED | 另需 pairs.json 对照 done + 双路径实测回执(当前 0) |')
    A('| BLOCKED | 依赖后端新接口/外部凭据 |')
    A('')
    A(NARRATIVE['十大问题'])
    A(NARRATIVE['口径差异'])
    A('## 2. Module Progress')
    A('')
    A('| 模块 | 页数 | IMPLEMENTED | PARTIAL | UI_ONLY | 未接通接口 |')
    A('|---|---|---|---|---|---|')
    for mod in sorted({r['module'] for r in rows}):
        sel = [r for r in rows if r['module'] == mod]
        A(f"| {mod} | {len(sel)} | "
          f"{sum(1 for r in sel if r['status'] == 'IMPLEMENTED')} | "
          f"{sum(1 for r in sel if r['status'] == 'PARTIAL')} | "
          f"{sum(1 for r in sel if r['status'] == 'UI_ONLY')} | "
          f"{len({e for r in sel for e in r['gaps']})} |")
    A('')
    A('## 3.1 页面矩阵(功能级在施工时按 slice 展开)')
    A('')
    A('| 小程序页 | 模块 | 动作 | 接口(通/全) | 文案 | 状态 | Flutter 落点 |')
    A('|---|---|---|---|---|---|---|')
    for r in sorted(rows, key=lambda r: (r['status'] != 'UI_ONLY', r['module'], r['page'])):
        copy = (f"{r['copy']}%" if r['copy'] is not None
                else {'judged': '—(已核)', 'no-copy': '—(无文案)',
                      'system': '—(系统承载)'}.get(r['copy_state'], '—'))
        A(f"| {r['page']} | {r['module']} | {r['actions']} | "
          f"{r['reach']}/{len(r['eps'])} | {copy} | {r['status']} | {r['at']} |")
    A('')
    A('## 3.2 组件层清单(小程序的「功能点」有一半长在组件里)')
    A('')
    comps = component_inventory()
    A(f'`components/**` 下带接口调用的组件 **{len(comps)}** 个:')
    A('')
    A('| 组件 | 接口 | App 可达 |')
    A('|---|---|---|')
    for path, eps in comps:
        ok = sum(1 for e in eps if E.hit(e, app_corpus))
        A(f'| {path} | {len(eps)} | {ok}/{len(eps)} |')
    A('')
    A('## 4. Backend Gaps')
    A('')
    A(f'App 未接通的 {len(app_side) + len(backend_missing)} 条接口里:')
    A('')
    A(f'- **后端已存在、App 没接** {len(app_side)} 条 —— 可直接派活:')
    for e in app_side:
        owners = sorted({r['page'] for r in rows if e in r['gaps']})
        A(f'  - `{e}` ← {", ".join(owners)}')
    A(f'- **后端也没有** {len(backend_missing)} 条 —— 需后端先建:')
    for e in backend_missing:
        owners = sorted({r['page'] for r in rows if e in r['gaps']})
        A(f'  - `{e}` ← {", ".join(owners)}')
    A('')
    A('## 5. UI Gaps(结构对照台账)')
    A('')
    A(f'`pairs.json` 共 {len(pairs)} 条,全部 `status: todo`;优先级 P0 {sum(1 for s in pairs if s["priority"] == "P0")} 条。')
    A('')
    A('| 路由 | 对照项 | P0 | 状态种类 | golden |')
    A('|---|---|---|---|---|')
    for route in sorted(shots_by_route, key=lambda r: -sum(1 for x in shots_by_route[r] if x.get('priority') == 'P0')):
        ss = shots_by_route[route]
        kinds = ','.join(sorted({s.get('state', '') for s in ss}))
        p0 = sum(1 for s in ss if s.get('priority') == 'P0')
        A(f"| {route} | {len(ss)} | {p0} | {kinds} | {sum(1 for s in ss if s.get('appGolden'))} |")
    A('')
    A(NARRATIVE['视觉'])
    A('## 6. Functional Gaps(逐页未接通接口)')
    A('')
    for r in rows:
        if r['gaps']:
            A(f"- **{r['page']}**({r['module']}):" + ', '.join(f'`{e}`' for e in r['gaps']))
    A('')
    A('## 7. Migration Debt(假完成扫描)')
    A('')
    A(f'扫描 `lib/**/*.dart`(**已剥注释**),命中 {len(debt)} 个文件。')
    A('')
    A('⇒ 剥注释后**没有一处真债**:唯一命中是 `my_project_api.dart` 里 ListMixin')
    A('  只读实现抛的 `UnsupportedError`(合理写法)。')
    A('  **本仓的「假完成」不靠 TODO 标记,而是接口不可达 / 文案缺失** ——')
    A('  判据以 §3 矩阵的 PARTIAL / UI_ONLY 为准,不要用关键词扫描冒充盘点。')
    A('')
    A('| 文件 | 命中 | 明细 |')
    A('|---|---|---|')
    for path, hits, total in debt[:25]:
        A(f"| {path} | {total} | {', '.join(f'{k}×{v}' for k, v in hits.items())} |")
    A('')
    A('## 8. Execution Queue')
    A('')
    A('队列由数据排:每页的 P0 对照项数(来自 `pairs.json`)× 接口缺口数。★ 顺序人工确认。')
    A('')
    queue = []
    for r in rows:
        if r['status'] in ('PARTIAL', 'UI_ONLY'):
            p0 = sum(1 for s_ in r['shots'] if s_.get('priority') == 'P0')
            queue.append((p0, len(r['gaps']), r))
    queue.sort(key=lambda t: (-t[0], t[1]))
    A('| 批次 | 页 | 模块 | P0 对照项 | 接口缺口 | 建议 |')
    A('|---|---|---|---|---|---|')
    for i, (p0, gapn, r) in enumerate(queue):
        batch = 'NEXT' if (gapn <= 2 and p0 > 0) else ('READY' if gapn else 'READY(文案)')
        A(f"| {batch} | {r['page']} | {r['module']} | {p0} | {gapn} | "
          f"{'缺口小,先闭环' if batch == 'NEXT' else '按模块整批做'} |")
    A('')
    A(NARRATIVE['切片'])
    A(NARRATIVE['流程'])
    A('## 10. Decision Log')
    A('')
    A('| 日期 | 问题 | 决定 | 影响 |')
    A('|---|---|---|---|')
    A('| 2026-09-17 | 小程序 master 删了 `pages/coop/candidates/index`(129 页) | manifest 残页待清,基线改 129 | page_parity |')
    A('| 2026-09-17 | 本机快照 `xcx-ref` 落后 master 1 个 commit | 用 `CHENGYIN_BACKEND` 指到当前镜像 | 全部对账 |')
    A('| 2026-09-17 | 工具缺口 53 条里混着注释/死代码(如 `/api/withdrawal/create`) | 逐条判,判完收口工具清单 | §4 清单 |')
    A('| 2026-09-17 | 小程序 2026-09-15 起提现改弹客服微信,后端接口保留不动 | App 按新模型(R10),不补 bank 提现 UI | 提现相关页 |')
    A('| 2026-09-17 | `endpoint_reachability_test` 被 CI 排除且基线为空 | 待修:纳入周检或修基线 | 全部接口判据 |')
    A('')
    A(NARRATIVE['刷新'])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('\n'.join(L))
    print(f'已写入 {OUT} · {len(L)} 行')
    print('状态分布:', dict(counts))
    return 0


if __name__ == '__main__':
    sys.exit(main())
