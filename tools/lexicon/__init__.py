"""Storilex lexicon candidate pipeline (developer tool, offline).

Extracts word, sense, phrasal verb, idiom and example *candidates* from texts, compares them read-only with
the two shipped dictionaries (assets/dict.db, assets/tr_en.db) and keeps them in a separate candidate
database. Nothing here writes to the shipped dictionaries or is used by the app at runtime.
"""

SCHEMA_VERSION = 2
