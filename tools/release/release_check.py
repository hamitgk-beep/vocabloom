#!/usr/bin/env python3
"""Checks for the split between building (build.yml) and releasing
(release.yml). Nothing here talks to GitHub: the workflows fetch the JSON
with `gh api` and pass the files in, so every rule can be tested offline
(tools/release/test_release_check.py).

    release_check.py pick-run RUNS_JSON
    release_check.py check-run RUN_JSON
    release_check.py check-env ENV_JSON ACTOR
    release_check.py check-order LATEST_BODY BUILD [--allow-older]
    release_check.py check-body BODY BUILD VERSION
    release_check.py verify-dist DIST
    release_check.py check-workflows WORKFLOW_DIR

Each command exits 1 with a "::error::" line when a rule is broken."""
import hashlib, json, os, re, sys, tarfile, zipfile

BUILD_WORKFLOW = '.github/workflows/build.yml'
RELEASE_WORKFLOW = 'release.yml'
# A release is made only from a build of main itself, never from a pull
# request build (those carry the same artifact names).
RELEASE_EVENTS = ('push', 'workflow_dispatch')
FILES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'release_files.txt')


class Refused(Exception):
    pass


def _read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def release_files():
    return [l.strip() for l in _read(FILES).splitlines() if l.strip()]


def _load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def _is_release_build(run):
    return (run.get('path', '').split('@')[0] == BUILD_WORKFLOW and run.get('head_branch') == 'main'
            and run.get('event') in RELEASE_EVENTS and run.get('status') == 'completed'
            and run.get('conclusion') == 'success')


def pick_run(runs):
    """The newest finished, successful build.yml run of main (not a pull request)."""
    for run in runs.get('workflow_runs', []):
        if _is_release_build(run):
            return run
    raise Refused('No successful build.yml run of main was found. Push to main or start build.yml on main first.')


def check_run(run):
    """The build run a release would publish; returns its commit and build number."""
    problems = []
    if run.get('path', '').split('@')[0] != BUILD_WORKFLOW:
        problems.append('run %s is not a build.yml run (%s)' % (run.get('id'), run.get('path')))
    if run.get('head_branch') != 'main':
        problems.append('run %s built branch %r, not main' % (run.get('id'), run.get('head_branch')))
    if run.get('event') not in RELEASE_EVENTS:
        problems.append('run %s was started by %r; only push or workflow_dispatch builds of main are released'
                        % (run.get('id'), run.get('event')))
    if run.get('status') != 'completed' or run.get('conclusion') != 'success':
        problems.append('run %s is %s/%s, not completed/success (tests, voice gate and every platform must pass)'
                        % (run.get('id'), run.get('status'), run.get('conclusion')))
    if not re.fullmatch(r'[0-9a-f]{40}', run.get('head_sha') or ''):
        problems.append('run %s has no commit' % run.get('id'))
    if problems:
        raise Refused('; '.join(problems))
    return run['head_sha'], int(run['run_number'])


def check_env(env, actor):
    """The 'production' environment must really make someone approve."""
    rules = env.get('protection_rules') or []
    reviewers = [r for rule in rules if rule.get('type') == 'required_reviewers' for r in rule.get('reviewers') or []]
    if not reviewers:
        raise Refused("The 'production' environment has no required reviewers, so nobody would have to approve "
                      'the release. Settings > Environments > production > Required reviewers (see docs/RELEASING.md).')
    names = {(r.get('reviewer') or {}).get('login') or (r.get('reviewer') or {}).get('slug') for r in reviewers}
    self_block = any(rule.get('prevent_self_review') for rule in rules if rule.get('type') == 'required_reviewers')
    if self_block and names <= {actor}:
        raise Refused("'Prevent self-review' is on and %s is the only reviewer: the release could never be "
                      'approved. Add another reviewer or turn that option off.' % actor)
    policy = env.get('deployment_branch_policy')
    warnings = []
    if not policy:
        warnings.append("The 'production' environment accepts every branch; limit it to main (docs/RELEASING.md).")
    return sorted(n for n in names if n), warnings


BUILD_RE = re.compile(r'build[:\s]+(\d+)', re.I)  # the same pattern the app uses (lib/online/update_check.dart)
VERSION_RE = re.compile(r'Sürüm\s+([\d.]+)')
NOTES_RE = re.compile(r'<!--\s*vocabloom-notes\s*(\{.*?\})\s*-->', re.S)


def body_build(body):
    m = BUILD_RE.search(body or '')
    return int(m.group(1)) if m else 0


def check_order(latest_body, build, allow_older=False):
    """Installed apps only update to a higher build number."""
    current = body_build(latest_body)
    if build == current:
        raise Refused('Build %d is already the published release.' % build)
    if build < current and not allow_older:
        raise Refused('Build %d is older than the published build %d. Apps already on %d would not go back; '
                      'set "allow_older" only to roll back on purpose (docs/RELEASING.md).' % (build, current, current))
    return current


def check_body(body, build, version):
    if body_build(body) != build:
        raise Refused('The release text gives build %d, not %d: apps would read the wrong number.' % (body_build(body), build))
    m = VERSION_RE.search(body)
    if not m or m.group(1) != version:
        raise Refused('The release text gives version %r, not %s.' % (m and m.group(1), version))
    m = NOTES_RE.search(body)
    try:
        entries = json.loads(m.group(1))['entries'] if m else None
    except ValueError:
        entries = None
    if not isinstance(entries, list):
        raise Refused('The release text has no readable "what\'s new" list for the app.')


def _sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def _zip_names(path):
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            raise Refused('%s is damaged at %s' % (os.path.basename(path), bad))
        return z.namelist()


def _need(name, names, wanted):
    for w in wanted:
        if not any(n == w or n.startswith(w) for n in names):
            raise Refused('%s does not contain %s' % (name, w))


def verify_dist(dist):
    """Every release file is there, opens, and holds what the app and its updater expect."""
    sums = {}
    for name in release_files():
        path = os.path.join(dist, name)
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            raise Refused('%s is missing or empty' % name)
        sums[name] = _sha(path)
    win = _zip_names(os.path.join(dist, 'Storilex-Windows.zip'))
    _need('Storilex-Windows.zip', win, ['Storilex.exe', 'data/flutter_assets/'])
    legacy = _zip_names(os.path.join(dist, 'VocaBloom-Windows.zip'))
    _need('VocaBloom-Windows.zip', legacy, ['Storilex.exe', 'VocaBloom.exe', 'data/flutter_assets/'])
    _need('Storilex-Android.apk', _zip_names(os.path.join(dist, 'Storilex-Android.apk')), ['AndroidManifest.xml', 'classes.dex'])
    _need('Storilex-iOS-unsigned.ipa', _zip_names(os.path.join(dist, 'Storilex-iOS-unsigned.ipa')),
          ['Payload/Runner.app/', 'Payload/Runner.app/MLKitTranslate_resource.bundle/'])
    _need('Storilex-macOS.zip', _zip_names(os.path.join(dist, 'Storilex-macOS.zip')), ['Contents/Info.plist', 'Contents/MacOS/'])
    with tarfile.open(os.path.join(dist, 'Storilex-Linux.tar.gz')) as t:
        linux = [n[2:] if n.startswith('./') else n for n in t.getnames()]
    _need('Storilex-Linux.tar.gz', linux, ['storilex', 'data/flutter_assets/'])
    for kind in ('Android.apk', 'iOS-unsigned.ipa', 'macOS.zip', 'Linux.tar.gz'):
        if sums['Storilex-' + kind] != sums['VocaBloom-' + kind]:
            raise Refused('VocaBloom-%s differs from Storilex-%s; older apps would get another build' % (kind, kind))
    return sums


WRITE_LATEST = re.compile(r'gh\s+release\s+(create|delete|upload|edit)\b[^\n]*\blatest\b')
WRITE_RELEASE = re.compile(r'gh\s+release\s+(create|delete|upload|edit)\b')
DISPATCH_RELEASE = re.compile(r'workflow\s+run\s+["\']?release(\.yml)?\b|workflows/release\.yml/dispatches')


def check_workflows(folder):
    """Only release.yml may change the 'latest' release or start itself."""
    problems = []
    for name in sorted(os.listdir(folder)):
        if not name.endswith(('.yml', '.yaml')) or name == RELEASE_WORKFLOW:
            continue
        with open(os.path.join(folder, name), encoding='utf-8') as f:
            text = f.read()
        if WRITE_LATEST.search(text):
            problems.append("%s changes the 'latest' release" % name)
        if DISPATCH_RELEASE.search(text):
            problems.append('%s starts release.yml' % name)
        if name == 'build.yml':
            if WRITE_RELEASE.search(text):
                problems.append('build.yml creates, deletes, uploads or edits a release')
            if re.search(r'contents:\s*write', text):
                problems.append('build.yml asks for contents: write')
    if problems:
        raise Refused('; '.join(problems))


def main(argv):
    cmd, args = argv[1], argv[2:]
    try:
        if cmd == 'pick-run':
            print(pick_run(_load(args[0]))['id'])
        elif cmd == 'check-run':
            sha, build = check_run(_load(args[0]))
            print('sha=%s' % sha)
            print('build=%d' % build)
        elif cmd == 'check-env':
            names, warnings = check_env(_load(args[0]), args[1])
            for w in warnings:
                print('::warning::' + w)
            print('Release approval required from: %s' % ', '.join(names))
        elif cmd == 'check-order':
            body = _read(args[0]) if os.path.exists(args[0]) else ''
            current = check_order(body, int(args[1]), '--allow-older' in args)
            print('Published build now: %d; this release: %s' % (current, args[1]))
        elif cmd == 'check-body':
            check_body(_read(args[0]), int(args[1]), args[2])
            print('Release text gives build %s and version %s' % (args[1], args[2]))
        elif cmd == 'verify-dist':
            for name, sha in verify_dist(args[0]).items():
                print('%s  %s' % (sha, name))
        elif cmd == 'check-workflows':
            check_workflows(args[0])
            print("Only release.yml can change the 'latest' release.")
        else:
            raise Refused('unknown command %s' % cmd)
    except Refused as e:
        print('::error::%s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
