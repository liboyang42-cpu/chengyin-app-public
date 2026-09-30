import subprocess
from pathlib import Path


root = Path(__file__).resolve().parent.parent
files = sorted(str(path.relative_to(root)) for path in (root / 'test').rglob('*_test.dart') if 'golden' not in path.relative_to(root / 'test').parts)
if not files:
    raise SystemExit('No public tests found')
print(f'Running {len(files)} non-golden test files. needs-local-env is excluded; visual baselines require separate verification.', flush=True)
raise SystemExit(subprocess.run(['flutter', 'test', '--exclude-tags', 'needs-local-env', '--concurrency=2', '--reporter=expanded', *files], cwd=root).returncode)
