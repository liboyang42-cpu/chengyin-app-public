/// 读源码做断言时的共用工具。
///
/// ★ 为什么需要它:凡是「代码里不许出现 X」的门禁,
///   被禁写法**必然**会出现在解释它的注释里(注释正是在说"别这么写")。
///   照全文扫 = 把"写了注释说明"当成"犯了那个错"。
///   本轮两条门禁连续栽在这上面,所以抽出来。
library;

import 'dart:io';

/// 读文件并剥掉注释,只留可执行代码。
///
/// 剥两种:整行 `//` 注释、以及 `/// ` 文档注释。
/// 行尾注释(`code(); // 说明`)也剥掉尾巴那段。
/// **不处理** `/* */` 块注释与字符串里的 `//`(本仓没有这两种用法;
/// 真出现了这个函数会剥过头,那时应该在这里补,而不是在各个门禁里绕)。
String codeOf(String path) {
  return File(path)
      .readAsLinesSync()
      .map((String line) {
        final String t = line.trimLeft();
        if (t.startsWith('//')) return '';
        final int at = line.indexOf('//');
        return at >= 0 ? line.substring(0, at) : line;
      })
      .join('\n');
}
