import 'dart:convert';
import 'dart:io';

/// 后端真源的 ref:只用 `github/master`(Codeup 的 `origin/master` 是异步镜像,永远滞后)。
const String kBackendMasterRef = 'github/master';

/// 后端仓候选根,顺序固定:env `CHENGYIN_BACKEND` → `$HOME/Downloads/chengyin` → `/tmp/be-master`。
///
/// ★ 为什么是候选而不是一个写死的路径:两台机器的布局不一样 ——
///   主控机的 `~/Downloads/chengyin` 本身就是带 `.git` 的仓;执行机上同一路径是
///   同步下来的**快照,没有 `.git`**,能跑 git ref 的镜像在 `/tmp/be-master`。
///   写死任何一个,另一台机器上的门禁就变成假红或假绿(本文件此前正是如此)。
///
/// ★ 环境变量是**显式覆盖**:给了就不能回落到别的候选 —— 否则
///   「指了个错路径」会伪装成「跑通了」。
List<String> _backendRepoCandidates() {
  final String? configured = Platform.environment['CHENGYIN_BACKEND']?.trim();
  // 显式覆盖:给了就只认它,不回落到猜出来的候选。
  if (configured != null && configured.isNotEmpty) {
    return <String>[configured];
  }
  final String? home = Platform.environment['HOME'];
  return <String>[
    if (home != null && home.isNotEmpty) '$home/Downloads/chengyin',
    '/tmp/be-master',
  ];
}

ProcessResult _git(String repo, List<String> args) => Process.runSync(
  'git',
  <String>['-C', repo, ...args],
  stdoutEncoding: const Utf8Codec(),
  stderrEncoding: const Utf8Codec(),
);

/// 该候选为什么不能用;能用时返回 null。区分「目录不在」/「不是仓」/「没这个 ref」,
/// 因为三者的修法完全不同(建目录 / 指到带 .git 的那份 / fetch)。
String? _candidateProblem(String path, String ref) {
  if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
    return '不存在';
  }
  if (FileSystemEntity.typeSync('$path/.git') ==
      FileSystemEntityType.notFound) {
    return '不是 git 仓(没有 .git,读不了 ref)';
  }
  final ProcessResult r = _git(path, <String>[
    'rev-parse',
    '--verify',
    '$ref^{commit}',
  ]);
  if (r.exitCode != 0) {
    final String detail = (r.stderr as String).trim().split('\n').first;
    return '取不到 ref `$ref`($detail)';
  }
  return null;
}

/// 第一个**能真跑 git 读 ref**的后端仓根 + 该 ref 的 SHA。
///
/// 全都不行时抛 [StateError]:列出每个候选各自的失败原因和该怎么给 ——
/// 「查不了」和「查完是 0」长得一模一样才是最危险的,所以这里绝不静默返回空。
({String repo, String sha}) _resolveBackend({String ref = kBackendMasterRef}) {
  final List<String> tried = <String>[];
  for (final String candidate in _backendRepoCandidates()) {
    final String? problem = _candidateProblem(candidate, ref);
    if (problem == null) {
      final ProcessResult r = _git(candidate, <String>[
        'rev-parse',
        '--verify',
        '$ref^{commit}',
      ]);
      return (repo: candidate, sha: (r.stdout as String).trim());
    }
    tried.add('  · $candidate —— $problem');
  }
  throw StateError(
    '找不到能读 `$ref` 的后端仓,试过:\n${tried.join('\n')}\n'
    '修法(任选其一):\n'
    '  · export CHENGYIN_BACKEND=<后端 git 仓根>(仓在别处时的正解)\n'
    '  · git -C <候选> fetch <remote> master(仓在,只是缺 `$ref`)',
  );
}

/// 后端仓根:第一个能读 [kBackendMasterRef] 的候选。
String backendRepoPath() => _resolveBackend().repo;

/// `github/master` 的 SHA —— 也就是喂给 `tool/*.py` 的 `CHENGYIN_BACKEND_REMOTE_SHA`。
///
/// 顺序:env `CHENGYIN_BACKEND_REMOTE_SHA`(一次性预检注入,省一次联网)→ 候选仓的 git。
/// env 给了值就**必须是 40 位 SHA**:短 SHA / 空值会让「本地 github/master 已过期」
/// 这道门禁静默失效,而它失效的方向恰好是假绿。
String backendMasterSha({String ref = kBackendMasterRef}) {
  final String injected =
      (Platform.environment['CHENGYIN_BACKEND_REMOTE_SHA'] ?? '').trim();
  if (injected.isNotEmpty) {
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(injected)) {
      throw StateError(
        'CHENGYIN_BACKEND_REMOTE_SHA 必须是 40 位 commit SHA,当前是「$injected」',
      );
    }
    return injected.toLowerCase();
  }
  return _resolveBackend(ref: ref).sha;
}

/// 给 `tool/*.py`、`tool/*.sh` 子进程的环境。
///
/// ★ 把 `CHENGYIN_BACKEND` 钉到**同一个**仓根:不钉的话 Dart 这边认一个仓、
///   python 那边按自己的候选再挑一个,两台机器布局不同 —— 这是最容易漂的一条缝。
Map<String, String> backendEnvironment([Map<String, String>? extra]) =>
    <String, String>{
      'CHENGYIN_BACKEND': backendRepoPath(),
      'CHENGYIN_BACKEND_REMOTE_SHA': backendMasterSha(),
      ...?extra,
    };

/// 读后端仓库里某个文件的**已发布内容**(`github/master` 上那一份)。
///
/// ★ 为什么不能直接 `File(...).readAsString()`:后端仓库在本机是一个**可变检出**,
///   随时停在任意分支上。跨仓合同若读工作区,判据就变成「那台机器此刻恰好切在哪个分支」——
///   2026-09-09 实测踩到:后端 master 已经删掉 egg_shown,而 CI 机器上的
///   `~/Downloads/chengyin` 停在一个半年前的功能分支,合同照着旧分支把本 PR 判红。
///   反过来更危险:停在一个「碰巧还带着旧事件名」的分支上,漂了也照样绿。
///
/// ★ 也**不回退 `origin/master`**:那是 Codeup 异步镜像,永远滞后于 `github/master`。
///   实测 `chengyinhub-xcx/utils/validation-method-labels.js` 只存在于 `github/master`,
///   回退到 origin 只会读不到或读到旧版。
///
/// 读 `github/master` 还顺带把跨仓改动的**顺序**钉死:后端那一半没合进 master 之前,
/// App 这一半就该是红的 —— 这正是两仓协同要的先后。
///
/// 读不到(没有该 ref / 没有该文件)时返回 null,由调用方**显式失败**;
/// 连一个能读 ref 的后端仓都找不到时直接抛错(见 [backendRepoPath])。
String? backendSource(String relativePath) =>
    backendSourceAt(backendRepoPath(), kBackendMasterRef, relativePath);

/// 从 [repoPath] 的 [ref] 里读 [relativePath],**只认这一个 ref,没有任何回退**。
///
/// 抽出来是为了能在临时仓库上做单测:证明「ref 不存在 → null,不会退回工作区」。
/// 返回 null 的三种情形:仓库目录不存在、git 取不到该 ref/文件、内容为空。
String? backendSourceAt(String repoPath, String ref, String relativePath) {
  if (!Directory(repoPath).existsSync()) return null;

  final ProcessResult r = Process.runSync('git', <String>[
    '-C',
    repoPath,
    'show',
    '$ref:$relativePath',
  ], stdoutEncoding: const SystemEncoding());
  if (r.exitCode != 0) return null;
  final String out = r.stdout as String;
  return out.trim().isEmpty ? null : out;
}
