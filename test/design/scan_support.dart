/// `test/design/**` 静态门禁的共用扫描工具。
///
/// ★ 与 `test/support/source_text.dart` 的 `codeOf` 是同一套剥注释语义
///   (整行 `//`、行尾 `//`)。区别:这里作用于**字符串**,门禁才能拿合成源码
///   做负控;`codeOf` 只接受磁盘路径。
///   两边的剥法必须一致 —— 剥过头会把真违规当注释放过(假绿),
///   剥不够会把注释里的反例当成违规(假红)。
library;

import 'dart:io';

String stripComments(String source) {
  return source
      .split('\n')
      .map((String line) {
        final String inner = line.trimLeft();
        if (inner.startsWith('//')) return '';
        final int at = line.indexOf('//');
        return at >= 0 ? line.substring(0, at) : line;
      })
      .join('\n');
}

/// 读文件并剥注释,路径相对仓库根(与测试工作目录一致)。
String codeOfFile(String path) => stripComments(File(path).readAsStringSync());
