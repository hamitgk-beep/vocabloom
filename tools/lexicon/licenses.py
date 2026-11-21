"""Licence policy for candidate sources.

A declared licence is only a claim. A source can become *shareable* (its reviewed candidates may later be
proposed for the shared dictionary) only when all of these hold:
  - its declared licence is on the permissive allow list below,
  - it is not a user's own imported book,
  - a named person has recorded a verification of that licence (store.approve_source, with evidence).
Everything else stays private on the machine where it was extracted. Share-alike, copyleft, non-commercial and
unknown licences cannot be verified with this tool at all: they need a separate decision by the project owner
and a code change to the allow list.
"""

# Normalised licence id -> human readable name. Permissive: attribution at most.
PERMISSIVE = {
    'public-domain': 'Public domain',
    'cc0-1.0': 'CC0 1.0',
    'cc-by-4.0': 'CC BY 4.0',
    'cc-by-2.0-fr': 'CC BY 2.0 FR',
    'mit': 'MIT',
    'apache-2.0': 'Apache-2.0',
    'bsd-3-clause': 'BSD-3-Clause',
    'storilex': 'Storilex original content',
}

# Known licences that need a separate decision (kept private until then).
NEEDS_APPROVAL = {
    'cc-by-sa-4.0': 'CC BY-SA 4.0',
    'cc-by-sa-3.0': 'CC BY-SA 3.0',
    'cc-by-nc-4.0': 'CC BY-NC 4.0',
    'cc-by-nc-sa-3.0': 'CC BY-NC-SA 3.0',
    'cc-by-nc-sa-4.0': 'CC BY-NC-SA 4.0',
    'gpl-2.0': 'GPL-2.0',
    'gpl-3.0': 'GPL-3.0',
    'agpl-3.0': 'AGPL-3.0',
    'gfdl': 'GFDL',
}

_ALIASES = {
    'public domain': 'public-domain', 'pd': 'public-domain', 'cc0': 'cc0-1.0',
    'cc by 4.0': 'cc-by-4.0', 'cc by-sa 4.0': 'cc-by-sa-4.0', 'cc by 2.0 fr': 'cc-by-2.0-fr',
    'apache 2.0': 'apache-2.0', 'apache license 2.0': 'apache-2.0', 'storilex original content': 'storilex',
}

SOURCE_KINDS = ('public_domain_text', 'open_license_text', 'user_book', 'manual', 'existing_dictionary')


def normalise(licence):
    s = (licence or '').strip().lower()
    s = _ALIASES.get(s, s)
    return s.replace(' ', '-')


# Licence class of a source, decided once from its declared licence and kind (stored on the source, which is
# immutable). It is *not* a permission: a declared licence is only a claim. A source becomes shareable only after
# a separate, recorded verification (store.approve_source), and only a `permissive` source can be verified.
LICENCE_CLASSES = ('permissive', 'needs_approval', 'unknown', 'private_only')

# Effective usage permission, derived from the licence class and the approval log (never typed in):
#   allowed               permissive licence, verified by a named person: may be exported after review
#   pending_verification  permissive licence declared, not yet verified
#   needs_approval        known share-alike / copyleft / non-commercial licence: owner decides first, the tool
#                         cannot verify it
#   unknown               licence missing or not recognised
#   private_only          the user's own imported book: never shared
PERMISSIONS = ('allowed', 'pending_verification', 'needs_approval', 'unknown', 'private_only')


def classify(licence, kind):
    """Returns (licence_id, licence_class, note)."""
    if kind not in SOURCE_KINDS:
        raise ValueError(f'unknown source kind: {kind}')
    lid = normalise(licence)
    if kind == 'user_book':
        # Copyrighted books the user imported: never shared, whatever licence is claimed.
        return lid or 'unknown', 'private_only', 'user-imported book: candidates stay private'
    if kind == 'existing_dictionary':
        return lid or 'unknown', 'private_only', 'shipped dictionary: read-only reference, not a candidate source'
    if lid in PERMISSIVE:
        return lid, 'permissive', 'declared permissive licence: needs a recorded verification before sharing'
    if lid in NEEDS_APPROVAL:
        return lid, 'needs_approval', f'{NEEDS_APPROVAL[lid]} needs a separate approval before sharing'
    if not lid:
        return 'unknown', 'unknown', 'licence unknown: needs review'
    return lid, 'unknown', f'licence "{licence}" not on the allow list: needs review'
