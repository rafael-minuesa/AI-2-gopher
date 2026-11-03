import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';

class TextView extends StatefulWidget {
  final String content;
  final String? title;

  const TextView({super.key, required this.content, this.title});

  @override
  State<TextView> createState() => _TextViewState();
}

class _TextViewState extends State<TextView> {
  bool _wrap = true;

  @override
  Widget build(BuildContext context) {
    final text = SelectableText(
      widget.content,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? t.textDocument,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: t.copyToClipboard,
                  onPressed: () => _copyToClipboard(context),
                ),
                IconButton(
                  icon: const Icon(Icons.wrap_text),
                  tooltip: _wrap ? t.disableWordWrap : t.enableWordWrap,
                  isSelected: _wrap,
                  onPressed: () => setState(() => _wrap = !_wrap),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _wrap
                  ? text
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: text,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.copiedToClipboard),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
