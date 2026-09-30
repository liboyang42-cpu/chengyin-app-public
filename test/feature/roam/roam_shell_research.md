# 漫游运行态底栏与安全区调研

## 结论

- 一级 Tab Bar 应保持稳定，但实时漫游是从“漫游”一级页进入的沉浸式任务，不是另一个顶级分区。按小程序真源，仅 `intro` 保留五项底栏，`starting/roaming/finishing/finished` 都全屏。
- 隐藏底栏后，地图背景可全出血，但“结束漫游”和地点卡片属于关键交互，必须加上 `MediaQuery.viewPadding.bottom` 避开 Home Indicator。
- 不引入新组件或第三方库。Flutter 官方 `go_router` 已提供覆盖 Shell 的 root navigator 模式，但当前漫游是同一路由内的实时状态切换；用壳层可观测属性小幅切换底栏，比新增路由和状态搬运更小、也不改默认落点。

## 一手来源

- Apple Human Interface Guidelines — Tab bars: <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- Apple Human Interface Guidelines — Layout / safe areas: <https://developer.apple.com/design/human-interface-guidelines/layout>
- Apple SwiftUI `ignoresSafeArea`: <https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)>
- Flutter 官方 `go_router` ShellRoute 示例: <https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/shell_route.dart>
- 小程序真源: `pages/roam/index.wxml` 第 624 行，`<tabBar wx:if="{{screen=='intro'}}" ... />`
