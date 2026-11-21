// Storilex lexicon tool: line protocol between Python and Zemberek-NLP (Apache-2.0). Reads one sentence per
// line from stdin; for each, writes one line per word token and then an empty line:
//   surface <TAB> lemma <TAB> primary POS <TAB> secondary POS <TAB> flags
// flags: "unk" when Zemberek could not analyse the word, "runtime" when the root was guessed (not in its
// lexicon). Tabs and line breaks never occur in a field. No network, no files: stdin and stdout only.
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import zemberek.morphology.TurkishMorphology;
import zemberek.morphology.analysis.SentenceAnalysis;
import zemberek.morphology.analysis.SentenceWordAnalysis;
import zemberek.morphology.analysis.SingleAnalysis;
import zemberek.morphology.lexicon.DictionaryItem;

public class ZemberekBridge {
  private static String clean(String s) {
    return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
  }

  public static void main(String[] args) throws Exception {
    TurkishMorphology morphology = TurkishMorphology.createWithDefaults();
    BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
    BufferedWriter out = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8));
    out.write("ready\n");
    out.flush();
    String line;
    while ((line = in.readLine()) != null) {
      if (!line.isBlank()) {
        SentenceAnalysis result = morphology.analyzeAndDisambiguate(line);
        for (SentenceWordAnalysis swa : result) {
          String surface = swa.getWordAnalysis().getInput();
          SingleAnalysis best = swa.getBestAnalysis();
          String lemma = "", pos = "", spos = "", flags = "";
          if (best.isUnknown()) {
            flags = "unk";
          } else {
            DictionaryItem item = best.getDictionaryItem();
            lemma = item.lemma;
            pos = best.getPos().shortForm;
            spos = item.secondaryPos == null ? "" : item.secondaryPos.shortForm;
            if (best.isRuntime()) {
              flags = "runtime";
            }
          }
          out.write(clean(surface) + "\t" + clean(lemma) + "\t" + clean(pos) + "\t" + clean(spos) + "\t" + flags + "\n");
        }
      }
      out.write("\n");
      out.flush();
    }
  }
}
