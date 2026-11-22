#!/usr/bin/env bash
# Task 5E: the ONE run on the final sets (tools/nlp_research/build_final_5e.py), after every choice was made on the
# development sets (tuned.json, idiom_tuned.json). Systems: A (the engine as it is), G0 (the part that could ship:
# the engine + the EWT tagger) and G (G0 + the model's agreement gate + the idiom veto, research only).
# E (research only): G0 + a WSD model re-ranking the meanings, settings from dev_se07.
# usage: tools/nlp_research/run_final.sh FINAL_DIR WORK_DIR TAGGER_GZ GATE_MODEL IDIOM_MODEL [WSD_MODEL]
set -euo pipefail
F=$1 W=$2 TAG=$3 GATE=$4 IDIOM=$5 WSD=${6:-}
cd "$(dirname "$0")/../.."
sha256sum -c "$W/final5e_LOCKED.sha256"
mkdir -p "$W/final/dumpA" "$W/final/dumpG0" "$W/final/scores" "$W/final/pos"
SETS="final5e_wsd=$F/final5e_wsd.tsv"
MP="final5e_magpie=$F/final5e_magpie.tsv"
EWT="final5e_pos=$F/final5e_pos.jsonl"
NLP_SENSE=$SETS NLP_MAGPIE=$MP NLP_EWT=$EWT NLP_OUT=$W/final/dumpA flutter test tools/nlp_research/dump_engine_test.dart
NLP_TAGGER=$TAG NLP_SENSE=$SETS NLP_MAGPIE=$MP NLP_EWT=$EWT NLP_OUT=$W/final/dumpG0 flutter test tools/nlp_research/dump_engine_test.dart
for d in dumpA dumpG0; do
  python3 tools/nlp_research/score_senses.py "$GATE" "$W/final/$d" "$W/final/scores_$d" final5e_wsd
  python3 tools/nlp_research/score_senses.py "$IDIOM" "$W/final/$d" "$W/final/scores_$d" final5e_magpie
done
if [ -n "$WSD" ]; then python3 tools/nlp_research/score_senses.py "$WSD" "$W/final/dumpG0" "$W/final/scores_dumpG0" final5e_wsd; fi
python3 tools/nlp_research/pos_metrics.py "$W/final/dumpA/final5e_pos.engine.jsonl" "$W/final/dumpG0/final5e_pos.engine.jsonl"
python3 tools/nlp_research/spacy_eval.py "$F/final5e_pos.jsonl" "$W/final/dumpA/final5e_pos.engine.jsonl" 1 "$W/final/spacy_final.json"
python3 tools/nlp_research/final_report.py "$W" "$GATE" "$IDIOM" $WSD
