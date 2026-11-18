import re
EN_STOP = set('the and or of to with for from are was were which that who someone something '
              'person thing into onto upon about over under these those their there they its'.split())


def english_words(text):
    return [w for w in re.findall(r"[^\W\d_]+", (text or "").lower()) if w in EN_STOP]
