import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import '../nlp/text.dart';
import 'expr_sheet.dart';

/// Every expression of one group (phrasal verbs, idioms …), searchable; a tap
/// opens the same panel as in the reader. Opened from the grammar lesson
/// that explains the group.
class ExpressionListPage extends StatefulWidget {
  final AppState app;
  final CategoryInfo cat;
  const ExpressionListPage({super.key, required this.app, required this.cat});

  @override
  State<ExpressionListPage> createState() => _ExpressionListPageState();
}

class _ExpressionListPageState extends State<ExpressionListPage> {
  String q = '';
  late final List<Expr> all = widget.app.dict.byCategory(widget.cat.id);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = q.isEmpty
        ? all
        : all.where((e) => e.phrase.contains(q) || displayPhrase(e.phrase).contains(q) || (e.trShown?.toLowerCase().contains(q) ?? false)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(uiEnglish ? widget.cat.name : '${widget.cat.tr} · ${widget.cat.name}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: L('${all.length} ifade içinde ara', 'Search ${all.length} entries')),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              final st = app.user.statuses[e.phrase];
              return ListTile(
                title: Text(displayPhrase(e.phrase), style: TextStyle(fontWeight: FontWeight.w600, color: widget.cat.color)),
                subtitle: Text([if (app.showTr && e.trShown != null) e.trShown!, if ((app.showEn || e.trShown == null) && e.en != null) e.en!].join('\n'), maxLines: 3),
                trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                onTap: () async {
                  await showExprSheet(context, app, e, null);
                  if (mounted) setState(() {});
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
