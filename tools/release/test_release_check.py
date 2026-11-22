#!/usr/bin/env python3
"""Offline tests for release_check.py and package.sh: python3 -I tools/release/test_release_check.py"""
import io, json, os, shutil, subprocess, sys, tarfile, tempfile, unittest, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import release_check as rc  # noqa: E402

SHA = 'a' * 40


def run(**kw):
    r = {'id': 7, 'path': '.github/workflows/build.yml', 'head_branch': 'main', 'event': 'push',
         'status': 'completed', 'conclusion': 'success', 'head_sha': SHA, 'run_number': 360}
    r.update(kw)
    return r


def env(reviewers=('hamit',), prevent_self=False, policy=True):
    rules = [{'type': 'branch_policy'}]
    if reviewers is not None:
        rules.append({'type': 'required_reviewers', 'prevent_self_review': prevent_self,
                      'reviewers': [{'type': 'User', 'reviewer': {'login': r}} for r in reviewers]})
    return {'protection_rules': rules,
            'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True} if policy else None}


BODY = ('Sürüm 8.3 · Build: 355. Windows: ...\n\n<!-- vocabloom-notes {"entries": [{"id": "x", "area": "app", '
        '"tr": "a", "en": "b", "build": 355}]} -->\n')


class RunChoice(unittest.TestCase):
    def test_newest_main_build_is_picked(self):
        runs = {'workflow_runs': [run(id=9, event='pull_request', head_branch='feature'), run(id=8, conclusion='failure'),
                                  run(id=6), run(id=5)]}
        self.assertEqual(rc.pick_run(runs)['id'], 6)

    def test_dispatched_build_of_main_counts(self):
        self.assertEqual(rc.pick_run({'workflow_runs': [run(id=4, event='workflow_dispatch')]})['id'], 4)

    def test_nothing_to_publish(self):
        with self.assertRaises(rc.Refused):
            rc.pick_run({'workflow_runs': [run(event='pull_request')]})

    def test_good_run(self):
        self.assertEqual(rc.check_run(run()), (SHA, 360))

    def test_refused_runs(self):
        for bad in [run(event='pull_request'), run(head_branch='claude/x'), run(conclusion='failure'),
                    run(status='in_progress', conclusion=None), run(path='.github/workflows/quality.yml'),
                    run(head_sha='')]:
            with self.subTest(bad=bad), self.assertRaises(rc.Refused):
                rc.check_run(bad)


class Approval(unittest.TestCase):
    def test_reviewer_required(self):
        self.assertEqual(rc.check_env(env(), 'hamit'), (['hamit'], []))

    def test_no_reviewer_means_no_release(self):
        for e in [env(reviewers=None), env(reviewers=()), {}]:
            with self.subTest(e=e), self.assertRaises(rc.Refused):
                rc.check_env(e, 'hamit')

    def test_self_review_block_with_only_reviewer(self):
        with self.assertRaises(rc.Refused):
            rc.check_env(env(prevent_self=True), 'hamit')
        self.assertEqual(rc.check_env(env(reviewers=('hamit', 'other'), prevent_self=True), 'hamit')[0], ['hamit', 'other'])

    def test_any_branch_is_a_warning(self):
        self.assertEqual(len(rc.check_env(env(policy=False), 'hamit')[1]), 1)


class Order(unittest.TestCase):
    def test_newer_build(self):
        self.assertEqual(rc.check_order(BODY, 360), 355)

    def test_same_or_older_refused(self):
        for b in (355, 300):
            with self.subTest(b=b), self.assertRaises(rc.Refused):
                rc.check_order(BODY, b)

    def test_rollback_on_purpose(self):
        self.assertEqual(rc.check_order(BODY, 300, allow_older=True), 355)
        with self.assertRaises(rc.Refused):
            rc.check_order(BODY, 355, allow_older=True)

    def test_no_release_yet(self):
        self.assertEqual(rc.check_order('', 1), 0)


class Body(unittest.TestCase):
    def test_real_release_notes_output(self):
        with tempfile.TemporaryDirectory() as d:
            prev = os.path.join(d, 'prev.md')
            with open(prev, 'w', encoding='utf-8') as f:
                f.write(BODY)
            out = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'release_notes.py'), '--version', '8.4', '--build', '361',
                                  '--prev-body', prev, '--notes', os.path.join(HERE, '..', '..', 'release_notes.json')],
                                 check=True, capture_output=True, text=True).stdout
        rc.check_body(out, 361, '8.4')
        with self.assertRaises(rc.Refused):
            rc.check_body(out, 362, '8.4')
        with self.assertRaises(rc.Refused):
            rc.check_body(out, 361, '8.5')

    def test_no_notes(self):
        with self.assertRaises(rc.Refused):
            rc.check_body('Sürüm 8.4 · Build: 361.', 361, '8.4')


def _zip(path, names):
    with zipfile.ZipFile(path, 'w') as z:
        for n in names:
            z.writestr(n, 'x')


def fake_build(dist):
    """The five artifacts as build.yml uploads them, with tiny stand-in files."""
    def put(rel, data='x'):
        p = os.path.join(dist, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(data)
    put('Storilex-Windows/Storilex.exe'); put('Storilex-Windows/data/flutter_assets/a')
    os.makedirs(os.path.join(dist, 'Storilex-Android'))
    _zip(os.path.join(dist, 'Storilex-Android/app-release.apk'), ['AndroidManifest.xml', 'classes.dex'])
    os.makedirs(os.path.join(dist, 'Storilex-iOS'))
    _zip(os.path.join(dist, 'Storilex-iOS/Storilex-unsigned.ipa'),
         ['Payload/Runner.app/Runner', 'Payload/Runner.app/MLKitTranslate_resource.bundle/x'])
    put('Storilex-macOS/Contents/Info.plist'); put('Storilex-macOS/Contents/MacOS/Storilex')
    put('Storilex-Linux/storilex'); put('Storilex-Linux/data/flutter_assets/a')


@unittest.skipUnless(shutil.which('zip') and shutil.which('bash'), 'needs zip and bash')
class Packaging(unittest.TestCase):
    def setUp(self):
        self.dist = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dist)
        fake_build(self.dist)

    def package(self):
        subprocess.run(['bash', os.path.join(HERE, 'package.sh'), self.dist], check=True)

    def test_ten_files_that_check_out(self):
        self.package()
        sums = rc.verify_dist(self.dist)
        self.assertEqual(sorted(sums), sorted(rc.release_files()))
        with zipfile.ZipFile(os.path.join(self.dist, 'VocaBloom-Windows.zip')) as z:
            self.assertIn('VocaBloom.exe', z.namelist())

    def test_runs_twice(self):
        self.package()
        self.package()
        rc.verify_dist(self.dist)

    def test_missing_artifact(self):
        shutil.rmtree(os.path.join(self.dist, 'Storilex-iOS'))
        with self.assertRaises(subprocess.CalledProcessError):
            self.package()

    def test_ipa_without_translation_bundle(self):
        _zip(os.path.join(self.dist, 'Storilex-iOS/Storilex-unsigned.ipa'), ['Payload/Runner.app/Runner'])
        self.package()
        with self.assertRaises(rc.Refused):
            rc.verify_dist(self.dist)

    def test_empty_file(self):
        self.package()
        open(os.path.join(self.dist, 'Storilex-Linux.tar.gz'), 'w').close()
        with self.assertRaises(rc.Refused):
            rc.verify_dist(self.dist)


class Workflows(unittest.TestCase):
    def test_repository_workflows(self):
        rc.check_workflows(os.path.join(HERE, '..', '..', '.github', 'workflows'))

    def check(self, name, text):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, name), 'w') as f:
                f.write(text)
            rc.check_workflows(d)

    def test_refused(self):
        for name, text in [('x.yml', 'run: gh release delete latest --yes'),
                           ('x.yml', 'run: gh release upload latest a.zip --clobber'),
                           ('x.yml', 'run: gh workflow run release.yml --ref main'),
                           ('build.yml', 'run: gh release create foo'),
                           ('build.yml', 'permissions:\n  contents: write')]:
            with self.subTest(text=text), self.assertRaises(rc.Refused):
                self.check(name, text)

    def test_allowed(self):
        self.check('x.yml', 'run: gh release upload voice-models a.zip --clobber\nrun: gh workflow run build.yml --ref main')
        self.check('release.yml', 'run: gh release delete latest --yes')


if __name__ == '__main__':
    unittest.main()
