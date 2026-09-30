// 跨端码表对账:App 的核验方式文案必须与小程序真源一致。
//
// ★ 不把小程序那份码表抄进测试 —— 抄一份进来,两边都改、两边都对,断言恒真。
//   这里**读**小程序仓的真源文件,从源码里解析出码表再逐码比。
//
// ★★ 真源只认**后端兄弟仓**里的
//   `git github/master:chengyinhub-xcx/utils/validation-method-labels.js`
//   (仓根由 support/backend_repo.dart 解析:env `CHENGYIN_BACKEND` →
//    `$HOME/Downloads/chengyin` → `/tmp/be-master`,换台机器不用改测试):
//   不回退 `origin/master`(Codeup 异步镜像,可能陈旧),也不读工作区
//   (会随开发者切分支漂移)。ref 或文件缺失时**显式失败**,绝不静默 skip。
//
// 依赖本机兄弟仓,CI 上按 needs-local-env 排除;解析/对账纯逻辑另有
// `validation_method_parity_helpers_test.dart` 在 CI 里跑(不依赖外仓)。
@Tags(<String>['needs-local-env'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/validation_method_labels.dart';

import '../../support/backend_repo.dart';
import '../../support/validation_method_parity.dart';

void main() {
  test('★ App 与小程序核验方式码表逐码一致', () {
    final String? source = backendSource(kXcxSourcePath);
    expect(
      source,
      isNotNull,
      reason:
          '读不到小程序真源 github/master:$kXcxSourcePath '
          '(本机没有能读 github/master 的后端仓,或该 ref/文件不存在;'
          'export CHENGYIN_BACKEND=<带 .git 的后端仓根> 可显式指定;'
          '不回退 origin/工作区)',
    );

    expect(
      validationLabelDrift(kValidationMethodLabels, parseXcxLabels(source!)),
      isEmpty,
    );
  });

  test('★ 负控:App 单方面把码 1 改回「扫码核销」,对账必须变红', () {
    final String? source = backendSource(kXcxSourcePath);
    expect(source, isNotNull, reason: '读不到小程序真源 github/master');
    final Map<int, String> drifted = Map<int, String>.from(
      kValidationMethodLabels,
    )..[1] = '扫码核销';

    final List<String> drift = validationLabelDrift(
      drifted,
      parseXcxLabels(source!),
    );
    expect(drift, isNotEmpty, reason: '单方面改码 1 没被对账抓到');
    expect(drift.single, contains('1:'));
  });
}
