import 'package:flutter/material.dart';

import '../l10n.dart';
import 'panel.dart';
import 'tap_text.dart';
import 'theme.dart';

/// Small building blocks of the word and expression panels, so English and
/// Turkish can be told apart at a glance: every line carries an "EN" or "TR"
/// tag, Turkish is big and bold, English is smaller and blue.

/// "EN" (blue) or "TR" (gold) tag in front of a line.
class LangTag extends StatelessWidget {
  final bool en;

  /// On the gold meaning box the tag takes the box's text colour.
  final Color? onColor;
  const LangTag.en({super.key, this.onColor}) : en = true;
  const LangTag.tr({super.key, this.onColor}) : en = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final fg = onColor ?? (en ? enColor(t) : (dark ? Brand.goldLight : const Color(0xFF8E6421)));
    final bg = onColor != null
        ? onColor!.withValues(alpha: 0.16)
        : en
            ? enColor(t).withValues(alpha: dark ? 0.16 : 0.11)
            : (dark ? Brand.goldLight.withValues(alpha: 0.2) : const Color(0xFFF1E2C2));
    return Container(
      height: 19,
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(en ? 'EN' : 'TR', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: fg, height: 1)),
    );
  }
}

/// A tagged line: the tag, then the text (and an optional button at the end).
class LangLine extends StatelessWidget {
  final bool en;
  final Widget child;
  final Widget? trailing;
  const LangLine({super.key, required this.en, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2, right: 10), child: en ? const LangTag.en() : const LangTag.tr()),
        Expanded(child: child),
        ?trailing,
      ]);
}

/// Section heading with a thin line after it ("KİTAPTAKİ CÜMLE ———"). Give
/// it in capitals: Dart's toUpperCase does not know Turkish i → İ.
class PanelHeading extends StatelessWidget {
  final String text;
  const PanelHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 9),
      child: Row(children: [
        Text(text, style: t.textTheme.labelMedium?.copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w700, color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: t.colorScheme.outlineVariant)),
      ]),
    );
  }
}

/// A rounded card in the panel's surface colour.
class PanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PanelCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(14, 13, 12, 13)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0x0EFFECCD) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? const Color(0x1CFFE6BE) : const Color(0xFFEDE3D0)),
      ),
      child: child,
    );
  }
}

/// Thin line between the English and the Turkish of a card.
class LangDivider extends StatelessWidget {
  const LangDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(36, 10, 0, 10), child: Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant));
}

TextStyle panelEnStyle(ThemeData t, {double size = 15.5}) => TextStyle(color: enColor(t), fontSize: size, height: 1.42);
TextStyle panelTrStyle(ThemeData t, {double size = 15.5, FontWeight weight = FontWeight.w600}) =>
    TextStyle(color: t.colorScheme.onSurface, fontSize: size, height: 1.42, fontWeight: weight);

/// The gold box at the top of a panel: the Turkish meaning, big, and the
/// English definition under it, small.
class MeaningBox extends StatelessWidget {
  final String label;
  final String? tr;
  final Key? trKey;
  final String? en;
  final String? note;
  final List<Widget> extra;
  const MeaningBox({super.key, required this.label, required this.tr, this.trKey, this.en, this.note, this.extra = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = onGold(t);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      decoration: BoxDecoration(gradient: Brand.goldGradient, borderRadius: BorderRadius.circular(22)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: fg.withValues(alpha: 0.75))),
          if (tr != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr!, key: trKey, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, color: fg)),
            ),
          if (note != null && note!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 3), child: Text(note!, style: TextStyle(fontSize: 14, color: fg.withValues(alpha: 0.85)))),
          if (en != null && en!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 1, right: 8), child: LangTag.en(onColor: fg)),
                Expanded(child: TapText(en!, style: TextStyle(fontSize: 13.5, height: 1.35, color: fg.withValues(alpha: 0.85)))),
              ]),
            ),
          ...extra,
        ]),
      ),
    );
  }
}

/// One meaning in the "other meanings" list: number, part of speech, the
/// Turkish big, the English definition small, then an example with its Turkish.
class SenseTile extends StatelessWidget {
  final int number;
  final String? pos;
  final String tr;
  final String? en;
  final String? exEn;
  final String? exTr;
  final bool divider;
  const SenseTile({super.key, required this.number, this.pos, required this.tr, this.en, this.exEn, this.exTr, this.divider = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final gold = t.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: t.colorScheme.outlineVariant)) : null),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: goldSoft(t), shape: BoxShape.circle),
          child: Text('$number', style: TextStyle(color: gold, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (pos != null && pos!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(pos!, style: TextStyle(fontSize: 12, color: gold, fontWeight: FontWeight.w600))),
            Text(tr, style: panelTrStyle(t, size: 17.5, weight: FontWeight.w700)),
            if (en != null && en!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 1, right: 7), child: LangTag.en()),
                  Expanded(child: TapText(en!, style: panelEnStyle(t, size: 13.5))),
                ]),
              ),
            if (exEn != null && exEn!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: goldSoft(t), width: 3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TapText(exEn!, style: panelEnStyle(t, size: 14)),
                  if (exTr != null && exTr!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(exTr!, style: panelTrStyle(t, size: 14, weight: FontWeight.w500))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A pill button for the panels (outlined, gold icon).
class PanelPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? fill;
  const PanelPill({super.key, required this.icon, required this.label, this.onPressed, this.color, this.fill});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: color ?? t.colorScheme.onSurface,
        backgroundColor: fill,
        side: fill != null ? BorderSide.none : BorderSide(color: t.colorScheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
      ),
      icon: Icon(icon, size: 19, color: color ?? t.colorScheme.primary),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Part of speech in Turkish for the own dictionary's labels and WordNet codes.
String posLabel(String? pos) {
  if (pos == null) return '';
  const codes = {'n': ('isim', 'noun'), 'v': ('fiil', 'verb'), 'a': ('sıfat', 'adjective'), 's': ('sıfat', 'adjective'), 'r': ('zarf', 'adverb')};
  final c = codes[pos];
  return c == null ? pos : L(c.$1, c.$2);
}
