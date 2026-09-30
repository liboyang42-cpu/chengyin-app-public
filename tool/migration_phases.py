#!/usr/bin/env python3
"""生成迁移的三个分册(Phase 2/3/4)。

- docs/migration/02-feature-matrix.md     功能级映射矩阵(模块→页→功能→接口/导航/测试→状态)
- docs/migration/03-page-gap-analysis.md  逐页 A–F 六维 gap 分析
- docs/migration/04-ui-reference.md       UI 对照(token / 组件 / 视觉元素)

用法:
    python3 tool/migration_phases.py
    CHENGYIN_BACKEND=/tmp/be-master python3 tool/migration_phases.py   # 执行机镜像

★ 抽取是**静态证据**,不是实测:凡是靠读代码判不出来的维度一律写「待对照」,
  不写「已一致」。实测回执只有跑起来才能给。
"""

import collections
import json
import os
import pathlib
import re
import sys
from typing import Optional

HERE = pathlib.Path(__file__).resolve()
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE.parent))

import endpoint_parity as E          # noqa: E402
import migration_plan as M           # noqa: E402

if os.environ.get('CHENGYIN_BACKEND'):
    E.BE = pathlib.Path(os.environ['CHENGYIN_BACKEND'])
    E.XCX = E.BE / 'chengyinhub-xcx'
XCX = E.XCX
DOCS = REPO / 'docs/migration'

API_RE = re.compile(r'["\'`](/api/[^"\'`?\s]*)')
BIND_RE = re.compile(r'(?:bind|catch)[:]?([a-zA-Z]+)\s*=\s*"([^"]+)"')
WX_RE = re.compile(r'wx\.([a-zA-Z]+)\s*\(')
NAV_RE = re.compile(r"wx\.(navigateTo|redirectTo|switchTab|reLaunch)\s*\(\s*\{\s*url:\s*['\"]([^'\"]+)")
METHOD_RE = re.compile(r'^\s{2,4}([a-zA-Z_$][\w$]*)\s*\([^)]*\)\s*\{', re.M)
CN_RE = re.compile(r'[\u4e00-\u9fa5]')
ANCHOR = re.compile(r'<([a-zA-Z-]+)([^>]*?)>')
# App 侧状态检测(静态证据:有这些写法 ≠ 状态齐,但「没有」几乎一定是缺)
APP_STATE = {
    'loading': r'CupertinoActivityIndicator|CircularProgressIndicator|isLoading|_loading|loading:',
    'empty': r"'暂无|'还没有|'没有|空列表|EmptyState|CyEmpty|暂无数据",
    'error': r"'加载失败|'失败|'出错|重试|retry|error",
    'permission': r'请先登录|登录后|permission|Unauthorized|未登录',
    'refresh': r'CupertinoSliverRefreshControl|RefreshIndicator|onRefresh',
    'pagination': r'loadMore|nextPage|hasMore|page \+ 1|page\+1',
}
MINI_STATE = {
    'loading': r'loading|Loading|wx\.showLoading',
    'empty': r'空|暂无|没有',
    'error': r'失败|出错|错误',
    'refresh': r'onPullDownRefresh|stopPullDownRefresh',
    'pagination': r'loadMore|onReachBottom|page\s*\+',
}


def read(page: str, ext: str) -> str:
    base = XCX / page
    for cand in (base.with_suffix('.' + ext), base / ('index.' + ext)):
        if cand.is_file():
            return cand.read_text(errors='ignore')
    return ''


def label_near(wxml: str, handler: str) -> str:
    """取绑定了该 handler 的元素内文本,当作用户可见动作名。"""
    for m in re.finditer(r'="' + re.escape(handler) + r'"', wxml):
        head = wxml.rfind('<', 0, m.start())
        tail = wxml.find('>', m.end())
        if head < 0 or tail < 0:
            continue
        seg = wxml[head:tail + 120]
        texts = [t.strip() for t in re.findall(r'>([^<>{}]+)<', seg) if CN_RE.search(t)]
        if texts:
            return texts[0][:14]
    return ''


def handler_bodies(js: str) -> dict:
    """按大括号配对切出每个方法体 —— 正则切不出嵌套,必须数括号。"""
    out = {}
    for m in METHOD_RE.finditer(js):
        name = m.group(1)
        i = js.find('{', m.end() - 1)
        if i < 0:
            continue
        depth, j = 0, i
        while j < len(js):
            if js[j] == '{':
                depth += 1
            elif js[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.setdefault(name, js[i:j + 1])
    return out


def comment_above(js: str, name: str) -> str:
    m = re.search(r'^\s{2,4}' + re.escape(name) + r'\s*\(', js, re.M)
    if not m:
        return ''
    head = js[:m.start()].rstrip().split('\n')
    lines = []
    for line in reversed(head[-3:]):
        s = line.strip()
        if s.startswith('//'):
            lines.insert(0, s[2:].strip())
        elif s.startswith('*'):
            lines.insert(0, s.lstrip('* ').strip())
        else:
            break
    text = ' '.join(lines)
    return text[:40]


LIFECYCLE = {
    'onLoad': ('enter', '进页面/加载详情'),
    'onShow': ('show', '回到页面/刷新'),
    'onPullDownRefresh': ('pull', '下拉刷新'),
    'onReachBottom': ('reach', '触底加载下一页'),
}


def features_of(page: str) -> list:
    wxml, js = read(page, 'wxml'), read(page, 'js')
    bodies = handler_bodies(js)
    out = []
    pairs = list(dict.fromkeys(BIND_RE.findall(wxml)))
    pairs += [(LIFECYCLE[h][0], h) for h in LIFECYCLE if h in bodies]
    for event, handler in pairs:
        body = bodies.get(handler, '')
        apis = sorted(set(API_RE.findall(body)))
        navs = [u for _, u in NAV_RE.findall(body)]
        abilities = sorted({a for a in WX_RE.findall(body)
                            if a not in ('navigateBack', 'getSystemInfoSync', 'nextTick')})
        if not (apis or navs or abilities):
            continue
        if event not in ('tap', 'change', 'input', 'confirm', 'submit', 'longpress',
                         'scan', 'cta', 'enter', 'show', 'pull', 'reach'):
            continue
        action = (LIFECYCLE[handler][1] if handler in LIFECYCLE else
                  label_near(wxml, handler) or comment_above(js, handler) or handler)
        out.append(dict(handler=handler, event=event, action=action, apis=apis,
                        navs=navs, abilities=abilities))
    return out


def app_source(entry: dict) -> Optional[pathlib.Path]:
    src = entry.get('source') or ''
    p = E.APP_LIB / src
    return p if p.is_file() else None


def app_state_hits(path: Optional[pathlib.Path]) -> dict:
    if path is None:
        return {}
    text = path.read_text(errors='ignore')
    return {k: len(re.findall(rx, text)) for k, rx in APP_STATE.items() if re.search(rx, text)}


def mini_state_hits(page: str) -> dict:
    text = read(page, 'js') + read(page, 'wxml')
    return {k: len(re.findall(rx, text)) for k, rx in MINI_STATE.items() if re.search(rx, text)}


def test_coverage(page: str, route: str) -> str:
    keys = [route] if route else []
    keys.append('/' + page)
    for t in (REPO / 'test').rglob('*.dart'):
        text = t.read_text(errors='ignore')
        if any(k and k in text for k in keys):
            return t.name
    return ''


def main() -> int:
    app_corpus = E.app_reachable_corpus()
    xcx_corpus = E.xcx_product_corpus()
    backend = E.backend_endpoints()
    pages = M.__dict__['P'].xcx_pages()
    manifest = {e.get('miniPage'): e for e in M.P._manifest_entries()}

    rows = []
    fid = 0
    for page in pages:
        entry = manifest.get(page) or {}
        route = entry.get('route', '')
        src = app_source(entry)
        feats = features_of(page)
        for f in feats:
            fid += 1
            gaps = [e for e in f['apis']
                    if E.classify_endpoints({e}, app_corpus, xcx_corpus,
                                            backend_endpoints=backend).gaps]
            rows.append(dict(fid=f'F{fid:04d}', page=page, module=M.module_of(page),
                             action=f['action'], handler=f['handler'], event=f['event'],
                             apis=f['apis'], gaps=gaps, navs=f['navs'],
                             abilities=f['abilities'], route=route, src=src,
                             app_states=app_state_hits(src), mini_states=mini_state_hits(page),
                             test=test_coverage(page, route)))

    DOCS.mkdir(parents=True, exist_ok=True)
    write_matrix(rows)
    write_gap_analysis(rows)
    write_ui_reference()
    print(f'功能条目 {len(rows)}')
    st = collections.Counter('PARTIAL' if r['gaps'] else 'IMPLEMENTED' for r in rows)
    print('功能级状态:', dict(st))
    return 0


def write_matrix(rows: list) -> None:
    route_of = {r['page']: r['route'] for r in rows if r['route']}
    L = []
    A = L.append
    total = len(rows)
    with_gap = sum(1 for r in rows if r['gaps'])
    A('# Phase 2 · 小程序 → Flutter 功能级映射矩阵')
    A('')
    A(f'> 由 `tool/migration_phases.py` 生成 · 真实来源 = 小程序 {len({r["page"] for r in rows})} 页的')
    A('> 交互绑定(handler)与代码路径。**一行 = 一个用户可触发的功能**,不是页面。')
    A('')
    A('列口径:')
    A('')
    A('| 列 | 怎么来的 |')
    A('|---|---|')
    A('| 小程序功能 | 绑定了该 handler 的控件文案;取不到就用函数上方注释;再取不到用函数名 |')
    A('| Flutter 页面 | `tool/page_parity_manifest.json` 的落点(route / 组件 / system) |')
    A('| UI | 静态判不出「一致」——只有实测能判,故一律 `待对照` |')
    A('| API | 该 handler 代码路径里的端点;`未接` = 工具判为缺口 |')
    A('| Logic / State | 小程序侧状态词 vs App 落点文件里的状态词(**静态证据**,不是验证) |')
    A('| Navigation | 该 handler 跳的小程序页 → App 是否已有落点 |')
    A('| Test | `test/**` 里检索该页/路由的覆盖文件名(空 = 无) |')
    A('| 状态 | 有未接接口 → PARTIAL;否则 IMPLEMENTED(证据齐);全部**未实测** |')
    A('')
    A(f'**功能条目 {total} 条 · 含未接接口 {with_gap} 条 · 其余 {total - with_gap} 条证据齐**')
    A('')
    A('## 按模块统计')
    A('')
    A('| 模块 | 功能 | 未接接口的功能 | 页数 |')
    A('|---|---|---|---|')
    mods = collections.defaultdict(list)
    for r in rows:
        mods[r['module']].append(r)
    for mod in sorted(mods):
        sel = mods[mod]
        A(f"| {mod} | {len(sel)} | {sum(1 for r in sel if r['gaps'])} | "
          f"{len({r['page'] for r in sel})} |")
    A('')
    A('## 功能矩阵')
    A('')
    cur = None
    for r in rows:
        if r['page'] != cur:
            cur = r['page']
            A('')
            A(f"### {r['page']}({r['module']}) → {r['route'] or '—'}")
            A('')
            A('| ID | 小程序功能 | 事件/处理器 | API | Logic/State(小程序→App) | Navigation | Test | 状态 |')
            A('|---|---|---|---|---|---|---|---|')
        api = ('未接 ' + ', '.join(f'`{g}`' for g in r['gaps'])) if r['gaps'] else (
            ', '.join(f'`{a}`' for a in r['apis']) if r['apis'] else '—')
        states = f"{len(r['mini_states'])}→{len(r['app_states'])}"
        navs = [n.split('?')[0].lstrip('/') for n in r['navs']]
        nav = ', '.join(f"{n} → {route_of.get(n, '**无落点**')}" for n in navs[:3]) \
            or ('-' if not r['abilities'] else '/'.join(r['abilities'][:2]))
        A(f"| {r['fid']} | {r['action']} | {r['event']}:{r['handler']} | {api} | {states} | "
          f"{nav} | {r['test'] or '—'} | {'PARTIAL' if r['gaps'] else 'IMPLEMENTED'} |")
    A('')
    (DOCS / '02-feature-matrix.md').write_text('\n'.join(L))


def write_gap_analysis(rows: list) -> None:
    by_page = collections.defaultdict(list)
    for r in rows:
        by_page[r['page']].append(r)
    manifest = {e.get('miniPage'): e for e in M.P._manifest_entries()}
    pages = M.P.xcx_pages()
    L = []
    A = L.append
    A('# Phase 3 · 逐页 Gap Analysis(A–F)')
    A('')
    A('> 由 `tool/migration_phases.py` 生成。**A–F 六个维度逐页过一遍**,')
    A('> 能静态判的写结论,判不出的写 `待对照` —— 不写「应该没问题」。')
    A('')
    A('| 维度 | 判据 |')
    A('|---|---|')
    A('| A 视觉 | 小程序 wxss 关键值 + 结构元素;App 侧对应文件与组件。**是否一致必须实测** |')
    A('| B 交互 | 小程序控件动作清单 vs App 落点文件的交互(静态计数,含缺口) |')
    A('| C 状态 | 小程序状态词(loading/empty/error/refresh/pagination)vs App 落点文件里的同类写法 |')
    A('| D 接口 | 该页接口 通/全 + 未接清单(工具判据) |')
    A('| E 业务逻辑 | 登录/权限/时间/地理/缓存:小程序侧出现的约束 vs App 落点 |')
    A('| F 导航 | 该页出边(跳去哪)与该页入边(从哪来) |')
    A('')
    for page in pages:
        entry = manifest.get(page) or {}
        src = app_source(entry)
        rows_ = by_page.get(page, [])
        gaps = sorted({g for r in rows_ for g in r['gaps']})
        apis = sorted({a for r in rows_ for a in r['apis']})
        wxml, wxss, js = read(page, 'wxml'), read(page, 'wxss'), read(page, 'js')
        struct = len(set(re.findall(r'<([a-z-]+)', wxml)))
        radii = sorted(set(re.findall(r'border-radius:\s*([0-9]+rpx|[0-9]+px)', wxss)))[:4]
        navs = sorted({n for r in rows_ for n in r['navs']})
        app_states = app_state_hits(src)
        mini_states = mini_state_hits(page)
        login = bool(re.search(r'login|token|未登录|请先登录', js))
        geo = bool(re.search(r'getLocation|chooseLocation|openLocation', js))
        cache = bool(re.search(r'getStorageSync|setStorageSync', js))
        A(f'## {page}')
        A('')
        A(f"落点:`{entry.get('route') or entry.get('kind', '—')}`"
          f"{' · `' + str(src.relative_to(REPO)) + '`' if src else ' · **无源码**'}")
        A('')
        A('| 维度 | 小程序侧证据 | App 侧现状 | 判定 |')
        A('|---|---|---|---|')
        A(f"| A 视觉 | 结构元素 {struct} 种 · 圆角 {', '.join(radii) or '—'} | "
          f"{'组件 ' + src.name if src else '无落点'} | 待对照 |")
        A(f"| B 交互 | 功能条目 {len(rows_)} 条(动作 "
          f"{', '.join(r['action'] for r in rows_[:6]) or '—'}…) | 落点文件需逐条对齐 | 待对照 |")
        A(f"| C 状态 | {'/'.join(mini_states) or '—'} | {'/'.join(app_states) or '—'} | "
          f"{'App 缺 ' + ', '.join(k for k in mini_states if k not in app_states) if [k for k in mini_states if k not in app_states] else '待对照'} |")
        A(f"| D 接口 | {len(apis)} 个 | 未接 {len(gaps)} 个"
          f"{'(' + ', '.join('`' + g + '`' for g in gaps[:6]) + ')' if gaps else ''} | "
          f"{'PARTIAL' if gaps else '证据齐'} |")
        A(f"| E 业务逻辑 | 登录 {int(login)} · 地理 {int(geo)} · 缓存 {int(cache)} | 需逐条核 | 待对照 |")
        A(f"| F 导航 | 出边 {len(navs)}:"
          f"{', '.join(n.split('?')[0] for n in navs[:4]) or '—'} | 入边见页面矩阵 | 待对照 |")
        A('')
    (DOCS / '03-page-gap-analysis.md').write_text('\n'.join(L))


def write_ui_reference() -> None:
    wxss = (XCX / 'style/tokens.wxss').read_text(errors='ignore')
    tokens = re.findall(r'(--[a-z0-9-]+)\s*:', wxss)
    allow = (REPO / 'tool/token_allowlist.txt').read_text(errors='ignore').split('\n')
    allow = [a.strip() for a in allow if a.strip() and not a.startswith('#')]
    app_widgets = sorted((REPO / 'lib/core/widgets').glob('*.dart'))
    usage = {}
    lib = list((REPO / 'lib').rglob('*.dart'))
    for w in app_widgets:
        stem = w.stem
        usage[stem] = 0
    for f in lib:
        text = f.read_text(errors='ignore')
        for stem in usage:
            if f.stem == stem:
                continue
            if re.search(r'\b' + re.escape(stem) + r'\b', text):
                usage[stem] += 1
    comps = sorted((XCX / 'components').rglob('*.js'))
    comp_names = sorted({c.parent.name if c.name == 'index.js' else c.stem for c in comps})

    L = []
    A = L.append
    A('# Phase 4 · UI 参考与整体 UI 对照')
    A('')
    A('> 由 `tool/migration_phases.py` 生成。**不重做设计系统**:token 链已有')
    A('> (`tool/gen_tokens.py` + `tool/token_allowlist.txt`,真源是小程序 `style/tokens.wxss`)。')
    A('')
    A('## 4.1 Design token 对照')
    A('')
    A(f'- 小程序 `style/tokens.wxss`:**定义行 {len(tokens)} 行 · 唯一变量名 {len(set(tokens))} 个**'
      '(含 `--cy-*` 语义色与商家浅色值)。')
    A(f'- App 侧允许清单 `tool/token_allowlist.txt` 收录 **{len(allow)}** 条,由 `gen_tokens.py`')
    A('  生成到 `lib/core/theme/cy_tokens.g.dart`(禁手改)。')
    A('- 页面取色一律 `CyPalette.of(context)`(随暗/浅切换);`CyTokens` 颜色常量是暗色编译期常量。')
    A('')
    A('⇒ **token 不是缺口,缺口在「用了没 / 用对没」**:')
    A('  禁硬编码颜色的门禁在 `test/`(theme 相关),新页面接入时按 `docs/design-tokens.md` 走。')
    A('')
    A('## 4.2 组件对照(小程序 → App)')
    A('')
    A(f'小程序 `components/` 下 **{len(comp_names)}** 个组件;App 侧公共组件 **{len(app_widgets)}** 个:')
    A('')
    A('| App 公共组件 | 被引用次数 | 覆盖的小程序侧视觉元素 |')
    A('|---|---|---|')
    covers = {
        'cy_confirm': 'wx.showModal / cy-modal', 'cy_native_action_sheet': 'wx.showActionSheet',
        'cy_native_notice': 'wx.showToast', 'cy_system_date_picker': 'picker mode=date',
        'cy_system_text_input_alert': 'input 弹窗', 'cy_tabs': 'components/cy/tabs',
        'cy_native_sheet': '半屏弹层', 'cy_net_image': 'image + 占位/失败',
        'cy_search_field': '搜索框', 'status_view': '空/错/加载态',
        'cy_native_button': '主按钮', 'upload_hints': '上传引导',
        'unsaved_guard': '离开确认', 'cy_image_source_sheet': '选图(相机/相册)',
        'cy_cupertino_range_slider': '区间滑块', 'cy_native_progress': '进度',
        'cy_widgets': '通用小件', 'ai_generated_note': 'AI 内容标注',
    }
    for w in app_widgets:
        A(f"| `{w.name}` | {usage[w.stem]} | {covers.get(w.stem, '—')} |")
    A('')
    A('## 4.3 小程序侧组件清单(核对用)')
    A('')
    A(', '.join(f'`{c}`' for c in comp_names[:60]))
    A('')
    A('## 4.4 重复实现热点(「禁止每页自造一套相似组件」的机械扫描)')
    A('')
    A('口径:扫描 `lib/feature/**` 里**没用公共组件、自己写**的常见元素次数。')
    A('数字高 ≠ 有问题(有的确需自绘),但**这些文件是「该不该收口到公共组件」的复核清单**。')
    A('')
    rollup = {
        '自绘卡片(Container+BoxDecoration)': r'Container\(\s*[\s\S]{0,200}?BoxDecoration',
        '自绘 loading': r'CupertinoActivityIndicator\(',
        '自绘空态(暂无/还没有)': r"'暂无|'还没有|'没有",
        '自绘错误态(失败/重试)': r"'加载失败|'操作失败|重试",
        '自绘按钮(CupertinoButton)': r'CupertinoButton\(',
        '自绘列表行(CupertinoListTile)': r'CupertinoListTile\(',
    }
    per_file = []
    for f in sorted((REPO / 'lib/feature').rglob('*.dart')):
        text = f.read_text(errors='ignore')
        hits = {k: len(re.findall(rx, text)) for k, rx in rollup.items()}
        hits = {k: v for k, v in hits.items() if v}
        if hits:
            per_file.append((str(f.relative_to(REPO)), sum(hits.values()), hits))
    per_file.sort(key=lambda x: -x[1])
    total = {k: 0 for k in rollup}
    for _, _, hits in per_file:
        for k, v in hits.items():
            total[k] += v
    A('| 元素 | 全仓自绘次数 |')
    A('|---|---|')
    for k, v in sorted(total.items(), key=lambda kv: -kv[1]):
        A(f'| {k} | {v} |')
    A('')
    A(f'按文件排序(共 {len(per_file)} 个文件命中):')
    A('')
    A('| 文件 | 合计 | 明细 |')
    A('|---|---|---|')
    for path, n, hits in per_file[:15]:
        A(f"| `{path}` | {n} | {', '.join(f'{k}×{v}' for k, v in hits.items())} |")
    A('')
    A('## 4.5 UI 缺口(静态可判的部分)')
    A('')
    A('1. **状态三件套没有统一入口**:App 侧有 `status_view.dart`,但页面是否都用它、')
    A('   empty/error/loading 是否三态齐全,只能逐页核(见分册 03 的 C 行)。')
    A('2. **小程序自绘组件在 App 侧是「原生替代」**,不是 1:1:tabBar / 导航栏 / 半屏 sheet')
    A('   走 `native_liquid_glass` + `mjn_liquid_ui`,差异按 iOS 27 原生化 accepted。')
    A('3. **视觉一致性无法静态判**:必须走 `tool/visual_parity/`(pairs.json 292 条,当前 0 完成)。')
    A('')
    A('## 4.6 怎么用这三份分册')
    A('')
    A('- 施工前:读 02 找目标功能 → 读 03 读该页 A–F → 读 04 确认组件/token 不另起炉灶。')
    A('- 施工后:回填 02 的状态列、03 的判定列、pairs.json 的对照结论,并更新总表统计。')
    A('')
    (DOCS / '04-ui-reference.md').write_text('\n'.join(L))


if __name__ == '__main__':
    sys.exit(main())
