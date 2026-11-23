"""Language analysis adapters.

English and Turkish adapters are independent: each language has its own base class (english.EnglishAnalyzer,
turkish.TurkishAnalyzer) and neither imports the other. They only share the plain data classes in `types`.
Optional engines (spaCy ...) are imported lazily, so the pipeline and its tests run with the Python standard
library alone. See LICENSE_REPORT.md before adding an engine.
"""
