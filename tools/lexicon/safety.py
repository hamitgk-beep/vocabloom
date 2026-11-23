"""Guards that keep the shipped dictionaries and user data out of reach of this tool."""
import os
import sqlite3

# File names the tool must never create, open for writing or overwrite.
PROTECTED_NAMES = {'dict.db', 'tr_en.db'}


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))


def check_writable_target(path):
    """Raises ValueError when `path` would put candidate data into the app's assets or onto a shipped
    dictionary. Candidate databases belong outside assets/ (default: build/lexicon/)."""
    real = os.path.realpath(path)
    if os.path.basename(real) in PROTECTED_NAMES:
        raise ValueError(f'refusing to write to a protected dictionary file: {path}')
    assets = os.path.realpath(os.path.join(repo_root(), 'assets'))
    if real == assets or real.startswith(assets + os.sep):
        raise ValueError(f'refusing to write inside assets/: {path}')
    return real


def open_readonly(path):
    """Opens an existing SQLite database strictly read-only (SQLite refuses every write)."""
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    uri = 'file:' + os.path.abspath(path).replace('?', '%3f').replace('#', '%23') + '?mode=ro'
    db = sqlite3.connect(uri, uri=True)
    db.execute('PRAGMA query_only = ON')
    return db
