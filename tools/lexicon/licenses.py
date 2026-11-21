"""Licence policy for candidate sources.

A source is *shareable* (its candidates may later be proposed for the shared dictionary) only when its licence
is on the permissive allow list and it is not a user's own imported book. Everything else stays private on
the machine where it was extracted. Share-alike, copyleft, non-commercial and unknown licences are never
shareable automatically: they need a separate, explicit decision by the project owner.
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


# Usage permission, stored separately from the licence itself.
PERMISSIONS = ('allowed', 'needs_approval', 'unknown', 'private_only')


def classify(licence, kind):
    """Returns (licence_id, permission, shareable, review_note).

    permission: allowed        permissive licence, may be proposed for the shared dictionary after review
                needs_approval known share-alike / copyleft / non-commercial licence: owner decides first
                unknown        licence missing or not recognised
                private_only   the user's own imported book, or a shipped dictionary"""
    if kind not in SOURCE_KINDS:
        raise ValueError(f'unknown source kind: {kind}')
    lid = normalise(licence)
    if kind == 'user_book':
        # Copyrighted books the user imported: never shared, whatever licence is claimed.
        return lid or 'unknown', 'private_only', False, 'user-imported book: candidates stay private'
    if kind == 'existing_dictionary':
        return lid or 'unknown', 'private_only', False, 'shipped dictionary: read-only reference, not a candidate source'
    if lid in PERMISSIVE:
        return lid, 'allowed', True, ''
    if lid in NEEDS_APPROVAL:
        return lid, 'needs_approval', False, f'{NEEDS_APPROVAL[lid]} needs a separate approval before sharing'
    if not lid:
        return 'unknown', 'unknown', False, 'licence unknown: needs review'
    return lid, 'unknown', False, f'licence "{licence}" not on the allow list: needs review'
