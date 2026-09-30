#!/usr/bin/env python3
"""Mini Program 128-page -> App carrier parity gate.

Every page registered in the Mini Program ``app.json`` must have one explicit
manifest entry. A route carrier binds route, source file and Widget class; a
component carrier binds a sheet/component source and marker. The only platform
exception is the standalone Mini Program crop page.

Endpoint evidence is supplementary: every endpoint unique to one Mini Program
page must be reachable in the App or have an explicit platform-equivalent
endpoint. One reachable endpoint can never prove its siblings.
"""

import json
import pathlib
import re
import sys
from typing import Optional

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import endpoint_parity as E

XCX = E.XCX  # 兼容锚点(migration_* 工具);判据一律走 E.xcx_* 的 ref 读法
APP_LIB = E.APP_LIB
ROUTER = APP_LIB / "core/router/app_router.dart"
MANIFEST = pathlib.Path(__file__).with_name("page_parity_manifest.json")

# App 把小程序单页拆成多条可深链子路由(例:/ticket/:id 承载 orderinfo 的
# 票券详情、/club-feed 承载 talent/list 的帖文 tab)。这类路由过去没有
# 登记位 —— manifest 以小程序页为主键,母页条目已被落点占用,硬加一行会
# 撞「重复绑定/未在 app.json 注册」两条红(b1-sim-club-2 N2;先例判定见
# REPORT-sim-official.md §6)。kind="appRoute" 给它们一个**被校验**的登记位:
# miniPage 必须是 app.json 真实在册的母页,route 必须存在于 app_router 且
# 当场构造 marker 类,reason 必须写明它从母页拆出了什么。
APP_ROUTE_KIND = "appRoute"

def xcx_pages() -> list[str]:
    """小程序页面清单,**按 `BACKEND_REF` 读 `app.json`** —— 不读工作区。

    ★★ 2026-09-17(P18):原来读工作区。本机镜像 checkout 在 release-0917
      (`7bdeb58d`,128 页),而 `github/master` 是 release-0916
      (`1b3ca1c4`,129 页,`pages/topic/pricing/partner/index` 还没删)——
      于是同一次对账,页面数随 checkout 漂移:门禁报「128(基线 129)」加
      「manifest 里已消失的页面 1 个」,而基线 129 与 manifest 都是 master 口径
      (#99 实测写的就是 129)。后端路由本来就是按 ref 读的,页面清单必须同源,
      否则「可重现的审计快照」是句空话(新鲜度门禁只校验 ref,校验不到 checkout)。
    """
    cfg = json.loads(E._git_blob("chengyinhub-xcx/app.json"))
    out = list(cfg.get("pages", []))
    for package in cfg.get("subPackages", []) or cfg.get("subpackages", []) or []:
        root = package["root"].rstrip("/")
        out += [root + "/" + page for page in package.get("pages", [])]
    return out


def endpoints_of(page: str) -> set[str]:
    """Endpoints called by a page and its directly-declared scene components."""
    endpoints: set[str] = set()
    for base in (page, page + "/index"):
        source = E.xcx_file_text(base + ".js")
        if source is None:
            continue
        texts = [source]
        config = E.xcx_file_text(base + ".json")
        if config is not None:
            try:
                components = (json.loads(config).get("usingComponents") or {}).values()
                for component in components:
                    component_base = component.lstrip("/")
                    for candidate in (
                        component_base + ".js",
                        component_base + "/index.js",
                    ):
                        text = E.xcx_file_text(candidate)
                        if text is not None:
                            texts.append(text)
            except Exception:
                pass
        for text in texts:
            endpoints |= set(re.findall(r"'(/api/[a-zA-Z0-9_/{}-]+)'", text))
        break
    return endpoints


def _manifest_entries() -> list[dict[str, str]]:
    raw = json.loads(MANIFEST.read_text())
    if not isinstance(raw, list):
        raise AssertionError("page parity manifest must be a JSON list")
    return raw


def _balanced_go_route_end(router: str, start: int) -> Optional[int]:
    """Return the exclusive end of one balanced ``GoRoute(...)`` call."""
    open_paren = router.find("(", start)
    if open_paren < 0:
        return None
    depth = 0
    quote: Optional[str] = None
    escaped = False
    for index in range(open_paren, len(router)):
        char = router[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return None


def _go_route_blocks(router: str) -> list[tuple[str, str]]:
    """Return ``(full_path, block)`` pairs, resolving relative child paths."""
    route_constants = router + "\n" + (ROUTER.parent / "route_paths.dart").read_text()
    constants = dict(
        re.findall(r"const\s+String\s+(\w+)\s*=\s*'([^']+)'", route_constants)
    )
    calls: list[dict[str, object]] = []
    for match in re.finditer(r"\bGoRoute\s*\(", router):
        end = _balanced_go_route_end(router, match.start())
        if end is None:
            continue
        block = router[match.start():end]
        path_match = re.search(
            r"\bpath:\s*(?:'([^']+)'|([A-Za-z_]\w*))",
            block,
        )
        if path_match is None:
            continue
        literal, constant = path_match.groups()
        raw_path = literal if literal is not None else constants.get(constant or "")
        if raw_path is None:
            continue
        calls.append(
            {
                "start": match.start(),
                "end": end,
                "block": block,
                "raw_path": raw_path,
                "full_path": None,
            }
        )

    for call in calls:
        raw_path = str(call["raw_path"])
        if raw_path.startswith("/"):
            call["full_path"] = raw_path
            continue
        parents = [
            candidate
            for candidate in calls
            if int(candidate["start"]) < int(call["start"])
            and int(candidate["end"]) > int(call["end"])
            and candidate["full_path"] is not None
        ]
        if not parents:
            continue
        parent = max(parents, key=lambda candidate: int(candidate["start"]))
        call["full_path"] = f"{str(parent['full_path']).rstrip('/')}/{raw_path.lstrip('/')}"

    return [
        (str(call["full_path"]), str(call["block"]))
        for call in calls
        if call["full_path"] is not None
    ]


def _route_block(router: str, route: str) -> Optional[str]:
    """Return the balanced GoRoute call that registers ``route``."""
    for full_path, block in _go_route_blocks(router):
        if full_path == route:
            return block
    return None


def _class_name(marker: str) -> Optional[str]:
    match = re.fullmatch(r"class\s+([A-Za-z_]\w*)", marker)
    return match.group(1) if match else None


def _validate_bindings(
    pages: list[str],
    entries: list[dict[str, str]],
    router: str,
    removed_page: Optional[str],
) -> tuple[int, list[tuple[str, list[str]]]]:
    # appRoute 是「App 把某个小程序页拆出的可深链子路由」(见 APP_ROUTE_KIND
    # 注释):它不占用母页的落点位,所以母页判据把它整类排除在外,
    # 由 _validate_app_routes 单独收严。
    page_entries = [
        entry for entry in entries if entry.get("kind") != APP_ROUTE_KIND
    ]
    manifest_pages = [entry.get("miniPage", "") for entry in page_entries]
    duplicate_pages = {page for page in manifest_pages if manifest_pages.count(page) > 1}
    by_page = {
        entry.get("miniPage", ""): entry
        for entry in page_entries
        if entry.get("miniPage") and entry.get("miniPage") != removed_page
    }
    missing: list[tuple[str, list[str]]] = []

    for page in pages:
        reasons: list[str] = []
        entry = by_page.get(page)
        if entry is None:
            missing.append((page, ["没有 manifest 绑定"]))
            continue
        if page in duplicate_pages:
            reasons.append("manifest 重复绑定")

        kind = entry.get("kind")
        if kind == "system":
            if page != "pages/crop/index":
                reasons.append("只有 pages/crop/index 可以是 system 例外")
            if not entry.get("reason", "").strip():
                reasons.append("system 例外没有理由")
        elif kind in ("route", "component"):
            source = entry.get("source", "")
            marker = entry.get("marker", "")
            source_path = APP_LIB / source
            if not source or not source_path.is_file():
                reasons.append(f"App 源码不存在:{source}")
            elif not marker or marker not in source_path.read_text(errors="ignore"):
                reasons.append(f"App 承载件不存在:{marker}")

            if kind == "route":
                route = entry.get("route", "")
                block = _route_block(router, route) if route else None
                if block is None:
                    reasons.append(f"App 路由不存在:{route}")
                else:
                    class_name = _class_name(marker)
                    if class_name is None:
                        reasons.append("route 承载件 marker 必须是 class")
                    elif not re.search(
                        r"\b" + re.escape(class_name) + r"\s*\(",
                        block,
                    ):
                        reasons.append(f"路由没有构建声明的页面类:{class_name}")
        else:
            reasons.append(f"未知承载类型:{kind}")

        if reasons:
            missing.append((page, reasons))

    for extra in sorted(set(manifest_pages) - set(pages)):
        missing.append((extra, ["manifest 页面未在小程序 app.json 注册"]))
    verified = len(pages) - sum(1 for page, _ in missing if page in pages)
    return verified, missing


def _validate_app_routes(
    pages: list[str],
    entries: list[dict[str, str]],
    router: str,
) -> list[tuple[str, list[str]]]:
    """appRoute 条目的独立判据。缺一条红一条,不与母页绑定互相顶包。"""
    problems: list[tuple[str, list[str]]] = []
    bound_routes = {
        entry.get("route", "")
        for entry in entries
        if entry.get("kind") == "route" and entry.get("route")
    }
    seen: set[str] = set()
    for entry in entries:
        if entry.get("kind") != APP_ROUTE_KIND:
            continue
        route = entry.get("route", "")
        label = f"[appRoute] {entry.get('miniPage', '')} -> {route}"
        reasons: list[str] = []
        parent = entry.get("miniPage", "")
        if parent not in pages:
            reasons.append(f"母页不在小程序 app.json:{parent or '(缺 miniPage)'}")
        if not entry.get("reason", "").strip():
            reasons.append("appRoute 没写它从母页拆出了什么(reason)")
        if not route or route in bound_routes or route in seen:
            reasons.append(f"route 为空或与既有登记重复:{route}")
        seen.add(route)
        source = entry.get("source", "")
        source_path = APP_LIB / source
        marker = entry.get("marker", "")
        if not source or not source_path.is_file():
            reasons.append(f"App 源码不存在:{source}")
        elif not marker or marker not in source_path.read_text(errors="ignore"):
            reasons.append(f"App 承载件不存在:{marker}")
        block = _route_block(router, route) if route else None
        if route and block is None:
            reasons.append(f"App 路由不存在:{route}")
        else:
            class_name = _class_name(marker)
            if class_name is None:
                reasons.append("appRoute 承载件 marker 必须是 class")
            elif not re.search(r"\b" + re.escape(class_name) + r"\s*\(", block):
                reasons.append(f"路由没有构建声明的页面类:{class_name}")
        if reasons:
            problems.append((label, reasons))
    return problems


def _endpoint_equivalent(
    endpoint: str,
    app_corpus: str,
    backend_endpoints: set[str],
) -> bool:
    """Reuse the executable endpoint contract gate for one page endpoint."""
    report = E.classify_endpoints(
        {endpoint},
        app_corpus,
        endpoint,
        backend_endpoints=backend_endpoints,
    )
    return not report.gaps


# 2026-09-17:小程序把「候选池」收编进 pages/coop/list/index,删了
# pages/coop/candidates/index —— 129 页。App 侧的独立路由
# /coop/candidates/:topicId 暂留(合作模块施工时再决定收编还是保留),
# 但 manifest 不再登记这条已删页的落点。
# 2026-09-19(release-0917 #1079 收页):小程序删
# pages/topic/pricing/partner/index —— 128 页。App 侧路由
# /topic/pricing/partner 与页面暂留(同 coop/candidates 先例,收编还是
# 删除留给施工时拍板),manifest 不再登记这条已删页的落点。
# 2026-09-22(gap-new-pages):master 快照(130 页)两页入账 ——
# pages/topic/pricing/partner/index 回潮(App 侧早已按真源落好,这次正式
# 登记),新增 subpackagePrefab/index《预制人生》(App 侧 /play/prefab,
# 由 play 会话首载命中 isPrefabLifeTopic 换轨)。coop/candidates 仍不登记。
EXPECTED_XCX_PAGE_COUNT = 130


def _page_count_report(pages: list[str], entries: list[dict[str, str]]) -> str:
    """页面数对不上时,直接说清多了哪几页、少了哪几页。

    ★★ 2026-09-17(P18):数不对**不再提前 return**。上游负控
      (`endpoint_reachability_test` 「切到旧 ref 必须变红」)断言的是
      stdout 里有那条缺失的端点路由;旧 ref 的页面数是 116,提前 return 会让
      门禁**指着页面数报红、端点结论一个字都不打** —— 正好撞回本函数下面
      那段注记骂的老毛病:「门禁红了却指错方向,比不红好不了多少」。
      现在页面数与端点结论一起出,退出码仍然非 0。

    ★ 2026-08-25 实证:这里原先是 `assert len(pages) == 113`,小程序涨到 120
      页时它在**打印任何东西之前**就退出,stdout 是空的。上游
      endpoint_reachability_test 断言的是「stdout 含 /api/coop/deposit/create」,
      于是报出来的是「Expected: contains '/api/coop/deposit/create' / Actual: ''」
      —— 指着保证金端点,而真因是小程序多了 7 个页面。
      门禁红了却指错方向,比不红好不了多少。
    """
    known = {entry.get("miniPage", "") for entry in entries}
    added = [page for page in pages if page not in known]
    removed = [page for page in known if page and page not in pages]
    lines = [
        f"小程序页面数变了:{len(pages)}(基线 {EXPECTED_XCX_PAGE_COUNT})",
    ]
    if added:
        lines.append(f"manifest 里没有的新页面 {len(added)} 个:")
        lines += [f"  + {page}" for page in added]
    if removed:
        lines.append(f"manifest 里已消失的页面 {len(removed)} 个:")
        lines += [f"  - {page}" for page in removed]
    lines.append(
        "判完之后:补 App 落点并登记进 page_parity_manifest.json,"
        f"再把 EXPECTED_XCX_PAGE_COUNT 改成 {len(pages)}。"
    )
    return "\n".join(lines)


def main() -> int:
    pages = xcx_pages()
    entries = _manifest_entries()
    page_count_ok = len(pages) == EXPECTED_XCX_PAGE_COUNT
    if not page_count_ok:
        print(_page_count_report(pages, entries))
    router = ROUTER.read_text(errors="ignore")
    app_corpus = E.app_reachable_corpus()
    backend_endpoints = E.backend_endpoints()
    assert len(app_corpus) > 200_000, "App 语料读空了"
    assert len(backend_endpoints) > 300, "后端端点读空了"

    removed_page: Optional[str] = None
    if "--negative-binding-control" in sys.argv:
        index = sys.argv.index("--negative-binding-control")
        removed_page = sys.argv[index + 1] if index + 1 < len(sys.argv) else pages[0]

    verified, binding_missing = _validate_bindings(
        pages,
        entries,
        router,
        removed_page,
    )
    binding_missing += _validate_app_routes(pages, entries, router)

    endpoint_users: dict[str, set[str]] = {}
    page_endpoints: dict[str, set[str]] = {}
    for page in pages:
        endpoints = endpoints_of(page)
        page_endpoints[page] = endpoints
        for endpoint in endpoints:
            endpoint_users.setdefault(endpoint, set()).add(page)

    endpoint_missing: list[tuple[str, list[str]]] = []
    for page in pages:
        distinctive = {
            endpoint
            for endpoint in page_endpoints[page]
            if len(endpoint_users[endpoint]) == 1
        }
        if "--negative-endpoint-control" in sys.argv and page == pages[0]:
            distinctive.add("/api/__page_parity_missing__")
        missing = sorted(
            endpoint
            for endpoint in distinctive
            if not _endpoint_equivalent(endpoint, app_corpus, backend_endpoints)
        )
        if missing:
            endpoint_missing.append((page, missing))

    print(
        f"小程序 {len(pages)} 页 · 页面绑定:已验证 {verified} · 缺失 {len(binding_missing)} "
        f"· 独有接口未逐条等价 {len(endpoint_missing)} 页"
    )
    if binding_missing:
        print("\n页面绑定缺失:")
        for page, reasons in binding_missing:
            print(f"  {page} -> {'; '.join(reasons)}")
    if endpoint_missing:
        print("\n独有接口未逐条等价:")
        for page, endpoints in endpoint_missing:
            print(f"  {page}")
            for endpoint in endpoints:
                print(f"      {endpoint}")

    return 1 if (binding_missing or endpoint_missing or not page_count_ok) else 0


if __name__ == "__main__":
    sys.exit(main())
