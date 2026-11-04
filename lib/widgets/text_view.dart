import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/find_state.dart';
import '../l10n/l10n.dart';

class TextView extends StatefulWidget {
  final String content;
  final String? title;

  const TextView({super.key, required this.content, this.title});

  @override
  State<TextView> createState() => _TextViewState();
}

class _TextViewState extends State<TextView> {
  static const _margin = 16.0;

  final ScrollController _down = ScrollController();
  final ScrollController _across = ScrollController();
  bool _wrap = true;
  int _seen = 0;
  double _width = 0;

  /// Laying a long document out is the slow part of going to a match, and it
  /// only changes with the document, the width or the size.
  TextPainter? _layout;
  List<Object?> _layoutFor = const [];

  @override
  void dispose() {
    _down.dispose();
    _across.dispose();
    _layout?.dispose();
    super.dispose();
  }

  TextPainter _laidOut(TextStyle style, TextScaler scaler) {
    final width = _wrap ? _width : double.infinity;
    final wanted = [widget.content, width, scaler, style];
    final same =
        _layout != null &&
        identical(_layoutFor[0], widget.content) &&
        _layoutFor[1] == width &&
        _layoutFor[2] == scaler &&
        _layoutFor[3] == style;
    if (same) return _layout!;
    _layout?.dispose();
    _layoutFor = wanted;
    return _layout = TextPainter(
      text: TextSpan(text: widget.content, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: width);
  }

  void _goTo(FindMatch match, TextStyle style, TextScaler scaler) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_down.hasClients) return;
      final boxes = _laidOut(style, scaler).getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      if (boxes.isEmpty) return;
      final view = _down.position.viewportDimension;
      _down.jumpTo(
        (boxes.first.top + _margin - view * 0.3).clamp(
          0.0,
          _down.position.maxScrollExtent,
        ),
      );
      if (!_wrap && _across.hasClients) {
        final wide = _across.position.viewportDimension;
        _across.jumpTo(
          (boxes.first.left - wide * 0.3).clamp(
            0.0,
            _across.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final find = FindState.of(context);
    find?.report([widget.content]);
    if (find != null && find.revision != _seen) {
      _seen = find.revision;
      final match = find.current;
      if (match != null) {
        _goTo(
          match,
          DefaultTextStyle.of(context).style.merge(style),
          MediaQuery.textScalerOf(context),
        );
      }
    }
    final found = foundSpan(find, widget.content, 0, style);
    final text = found == null
        ? SelectableText(widget.content, style: style)
        : SelectableText.rich(found);
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                _width = constraints.maxWidth - 2 * _margin;
                return SingleChildScrollView(
                  controller: _down,
                  padding: const EdgeInsets.all(_margin),
                  child: _wrap
                      ? text
                      : SingleChildScrollView(
                          controller: _across,
                          scrollDirection: Axis.horizontal,
                          child: text,
                        ),
                );
              },
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
