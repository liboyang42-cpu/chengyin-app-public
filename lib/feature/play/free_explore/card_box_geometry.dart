// 卡盒的转角几何。**全是纯函数** —— 这几件事最容易「看着对、其实算错」,
// 必须能脱离 widget 树断言。数值逐字照搬小程序 pages/play/index.js:1464-1496。

/// 拖动时的角度累加:横向位移 × 0.8(手指划过整屏约转 300°,跟手但不过头)。
double dragRy(double startRy, double dx) => startRy + dx * 0.8;

/// 松手吸附到最近的一面。
///
/// ★ 为什么必须吸附:停在 40° 这类角度上只能看见一条厚度,既不是正面也不是背面 ——
///   卡片会像是「卡住了」。样机松手也是吸附到正/背面。
double snapRy(double ry) => (ry / 180).round() * 180.0;

/// 归一化到 [0, 360)。
double _norm360(double ry) => ((ry % 360) + 360) % 360;

/// 这一帧该画背面吗?
///
/// ⚠️ **Flutter 没有 CSS 的 `backface-visibility: hidden`**:两个面都画的话,
///   背对观察者的那个会**镜像着透出来**。所以必须自己按角度选面,只画朝前的那一个。
bool showsBack(double ry) {
  final double a = _norm360(ry);
  return a > 90 && a < 270;
}

/// 是否处在「只看得见厚度」的角度(小程序 `turnedAt`:归一化到 180 后 8°..172°)。
/// 侧脊只在这个区间里渲染 —— 正对时渲染它会在卡片边缘糊出一条硬线(小程序实拍抓到过)。
bool edgeOn(double ry) {
  final double a = ((ry % 180) + 180) % 180;
  return a > 8 && a < 172;
}

/// 正文上滚时卡片的收缩曲线。四个量与小程序**逐条同源**(index.js:1502-1512):
/// 0→220px 映射到 p 0→1;缩到 0.12;越过 0.85 顶栏接管;越过 0.92 淡出。
///
/// ★ [faded] 是**布尔切换**不是连续淡出:样机 `.is-faded{opacity:0}` 在 p>0.92
///   那一下整张关掉,同时 `pointer-events:none`。写成 `opacity: 1 - p` 会让卡片
///   一路半透明地糊在正文上,而且到最后仍然是个吃手势的透明热区。
///
/// ⚠️ 缩放的原点在调用方(`Alignment.topLeft`,对齐样机 `transform-origin:0 0`),
///   且**只缩不移**(样机 `sx = 0`):0 0 的收缩方向本来就朝卡片左上角,也就是
///   顶栏缩略图那一侧,再叠一个横移会把它推出屏幕。
({double scale, bool faded, bool barTakesOver}) cardCollapse(double scrollTop) {
  final double p = (scrollTop / 220).clamp(0.0, 1.0);
  return (
    scale: 1.0 - p * 0.88, // 1 → 0.12
    faded: p > 0.92,
    barTakesOver: p > 0.85,
  );
}
