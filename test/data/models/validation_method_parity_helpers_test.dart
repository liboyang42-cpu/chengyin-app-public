// 跨端对账的解析/比较纯函数,以及「只认 github/master、不回退」的读取器。
//
// ★★ 这些用例**不依赖后端/小程序兄弟仓**,所以能在 CI(没有兄弟仓)里跑。
//    parity 用例本身带 needs-local-env(CI 排除),这里是它的第二道网:
//    码表怎么解析、逐码怎么比、ref 读不到会不会偷偷退回工作区 —— 都在 CI 里被钉死。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/backend_repo.dart';
import '../../support/validation_method_parity.dart';

void main() {
  group('parseXcxLabels', () {
    test('从真源字面量里抠出码表', () {
      expect(
        parseXcxLabels(
          "const VALIDATION_METHOD_LABELS = { 0: '无需验证', "
          "1: '文字作答', 7: '传感器挑战' };",
        ),
        <int, String>{0: '无需验证', 1: '文字作答', 7: '传感器挑战'},
      );
    });

    test('结构变了要显式失败,不返回空表', () {
      expect(
        () => parseXcxLabels('const OTHER = {};'),
        throwsA(isA<FormatException>()),
      );
    });

    test('块在但一个码都没解析出来也要失败', () {
      expect(
        () => parseXcxLabels('const VALIDATION_METHOD_LABELS = { };'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validationLabelDrift', () {
    test('逐码一致返回空表', () {
      expect(
        validationLabelDrift(
          <int, String>{0: '无需验证', 1: '文字作答'},
          <int, String>{0: '无需验证', 1: '文字作答'},
        ),
        isEmpty,
      );
    });

    test('只有一条改名也会被点名', () {
      expect(
        validationLabelDrift(
          <int, String>{0: '无需验证', 1: '文字作答'},
          <int, String>{0: '无需验证', 1: '文字暗号'},
        ),
        <String>['1: app=文字作答 xcx=文字暗号'],
      );
    });

    test('单边缺码也算漂移', () {
      expect(
        validationLabelDrift(<int, String>{1: '文字作答'}, <int, String>{}),
        <String>['1: app=文字作答 xcx=null'],
      );
    });
  });

  group('backendSourceAt:只认指定 ref,不回退 origin/工作区', () {
    late Directory repo;

    setUp(() {
      repo = Directory.systemTemp.createTempSync('backend_repo_strict_');
      Process.runSync('git', <String>[
        'init',
        '-q',
      ], workingDirectory: repo.path);
      File('${repo.path}/labels.js').writeAsStringSync("const X = '1';\n");
      Process.runSync('git', <String>[
        'add',
        'labels.js',
      ], workingDirectory: repo.path);
      Process.runSync('git', <String>[
        '-c',
        'user.email=t@t.t',
        '-c',
        'user.name=t',
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-qm',
        'init',
      ], workingDirectory: repo.path);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('ref 与文件都在 → 返回已提交内容', () {
      expect(
        backendSourceAt(repo.path, 'HEAD', 'labels.js'),
        "const X = '1';\n",
      );
    });

    test('ref 不存在 → null,不回退工作区', () {
      expect(backendSourceAt(repo.path, 'github/master', 'labels.js'), isNull);
    });

    test('只在工作区、没提交的文件 → null', () {
      File('${repo.path}/uncommitted.js').writeAsStringSync('x\n');
      expect(backendSourceAt(repo.path, 'HEAD', 'uncommitted.js'), isNull);
    });

    test('文件在 ref 里不存在 → null', () {
      expect(backendSourceAt(repo.path, 'HEAD', 'missing.js'), isNull);
    });
  });
}
