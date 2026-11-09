import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../services/find_state.dart';
import 'find_bar.dart';
import '../l10n/l10n.dart';

/// [text] cut at line ends into the pieces the reader builds one at a time: a
/// paragraph with the blank lines after it, or [most] lines where there are no
/// blank lines. Joined with a line end they are [text] again.
List<String> readerBlocks(String text, {int most = 40}) {
  final blocks = <String>[];
  var start = 0;
  var lines = 0;
  var afterBlank = false;
  var at = 0;
  while (at <= text.length) {
    var end = text.indexOf('\n', at);
    if (end < 0) end = text.length;
    var blank = true;
    for (var i = at; i < end; i++) {
      if (text.codeUnitAt(i) > 0x20) {
        blank = false;
        break;
      }
    }
    if (lines > 0 && ((afterBlank && !blank) || lines >= most)) {
      blocks.add(text.substring(start, at - 1));
      start = at;
      lines = 0;
    }
    lines++;
    afterBlank = blank;
    at = end + 1;
  }
  blocks.add(text.substring(start));
  return blocks;
}

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
  final GlobalKey _list = GlobalKey();
  late final ListFinder _finder = ListFinder(_down, show: _show);
  bool _wrap = true;

  /// A long document as one piece of text is laid out whole, which takes
  /// hundreds of megabytes for each megabyte of text. In pieces, only what is
  /// near the window is.
  List<String> _blocks = const [];
  String? _blocksOf;

  /// How wide the unwrapped text is. A guess from the longest lines, and each
  /// piece says so when it turns out wider.
  double _wide = 0;
  List<Object?> _wideFor = const [];
  bool _widening = false;

  /// One line of this text, to move each piece up by. See [_Block].
  double _line = 0;
  List<Object?> _lineFor = const [];

  @override
  void dispose() {
    _down.dispose();
    _across.dispose();
    super.dispose();
  }

  double _lineHeight(TextStyle style, TextScaler scaler) {
    if (_lineFor.length == 2 && _lineFor[0] == style && _lineFor[1] == scaler) {
      return _line;
    }
    final painter = TextPainter(
      text: TextSpan(text: '\n', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    _lineFor = [style, scaler];
    _line = painter.computeLineMetrics().first.height;
    painter.dispose();
    return _line;
  }

  void _measure(TextStyle style, TextScaler scaler) {
    final same =
        _wideFor.length == 3 &&
        identical(_wideFor[0], widget.content) &&
        _wideFor[1] == style &&
        _wideFor[2] == scaler;
    if (same) return;
    _wideFor = [widget.content, style, scaler];
    final content = widget.content;
    // Start and end of the three longest lines.
    final longest = <(int, int)>[];
    var at = 0;
    while (at <= content.length) {
      var end = content.indexOf('\n', at);
      if (end < 0) end = content.length;
      if (longest.length < 3 || end - at > longest.last.$2 - longest.last.$1) {
        longest.add((at, end));
        longest.sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
        if (longest.length > 3) longest.removeLast();
      }
      at = end + 1;
    }
    _wide = 0;
    for (final (start, end) in longest) {
      final painter = TextPainter(
        text: TextSpan(text: content.substring(start, end), style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      _wide = math.max(_wide, painter.width);
      painter.dispose();
    }
  }

  void _wider(double width) {
    if (width <= _wide) return;
    _wide = width;
    if (_widening) return;
    _widening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widening = false;
      if (mounted) setState(() {});
    });
  }

  /// The piece is built and laid out, so where the match is in it is known
  /// without laying anything out again.
  void _show(BuildContext piece, FindMatch match) {
    RenderParagraph? paragraph;
    void look(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph) {
        paragraph = object;
      } else {
        object.visitChildren(look);
      }
    }

    final root = piece.findRenderObject();
    if (root == null || !_down.hasClients) return;
    look(root);
    final text = paragraph;
    if (text == null) return;
    // Every piece but the first starts with the line end before it.
    final shift = match.line == 0 ? 0 : 1;
    final boxes = text.getBoxesForSelection(
      TextSelection(
        baseOffset: match.start + shift,
        extentOffset: match.end + shift,
      ),
    );
    if (boxes.isEmpty) return;
    final rect = boxes.first.toRect();
    final list = RenderAbstractViewport.of(text);
    _down.jumpTo(
      list
          .getOffsetToReveal(text, 0.3, rect: rect)
          .offset
          .clamp(0.0, _down.position.maxScrollExtent),
    );
    final outer = RenderAbstractViewport.maybeOf((list as RenderObject).parent);
    if (!_wrap && outer != null && _across.hasClients) {
      _across.jumpTo(
        outer
            .getOffsetToReveal(text, 0.3, rect: rect)
            .offset
            .clamp(0.0, _across.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      color: Theme.of(context).colorScheme.onSurface,
    );
    if (!identical(_blocksOf, widget.content)) {
      _blocksOf = widget.content;
      _blocks = readerBlocks(widget.content);
    }
    final blocks = _blocks;
    final find = FindState.of(context);
    find?.report(blocks);
    _finder.follow(find);
    final whole = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final line = _lineHeight(whole, scaler);
    if (!_wrap) _measure(whole, scaler);
    final wrap = _wrap;

    Widget piece(BuildContext context, int index) {
      final found = foundSpan(find, blocks[index], index, null);
      final Widget text;
      if (index == 0) {
        text = found == null
            ? Text(blocks[index], style: style, softWrap: wrap)
            : Text.rich(found, style: style, softWrap: wrap);
      } else {
        text = Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '\n'),
              found ?? TextSpan(text: blocks[index]),
            ],
          ),
          style: style,
          softWrap: wrap,
        );
      }
      return _finder.keep(
        index,
        _Block(
          lift: index == 0 ? 0 : line,
          wrap: wrap,
          onWidth: _wider,
          child: text,
        ),
      );
    }

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
            child: SelectionArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final list = ListView.builder(
                    key: _list,
                    controller: _down,
                    padding: const EdgeInsets.all(_margin),
                    itemCount: blocks.length,
                    itemBuilder: piece,
                  );
                  if (wrap) return list;
                  // The list is as wide as the text, so its own bar would be
                  // out of sight at the far right.
                  return Scrollbar(
                    controller: _down,
                    notificationPredicate: (notification) =>
                        notification.depth == 1 &&
                        notification.metrics.axis == Axis.vertical,
                    child: SingleChildScrollView(
                      controller: _across,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(
                          constraints.maxWidth,
                          _wide + 2 * _margin,
                        ),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: list,
                        ),
                      ),
                    ),
                  );
                },
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

/// One piece of the document in the list. What is selected across pieces is
/// copied as their texts one after the other, with nothing between. So every
/// piece but the first starts with the line end that comes before it, and is
/// moved up by that one empty line, onto the last line of the piece above.
/// Unwrapped, the piece is as wide as its longest line and says how wide.
class _Block extends SingleChildRenderObjectWidget {
  final double lift;
  final bool wrap;
  final ValueChanged<double> onWidth;

  const _Block({
    required this.lift,
    required this.wrap,
    required this.onWidth,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlock(lift, wrap, onWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderBlock renderObject) {
    renderObject
      ..lift = lift
      ..wrap = wrap
      ..onWidth = onWidth;
  }
}

class _RenderBlock extends RenderShiftedBox {
  _RenderBlock(this._lift, this._wrap, this.onWidth) : super(null);

  ValueChanged<double> onWidth;

  double _lift;
  set lift(double value) {
    if (value == _lift) return;
    _lift = value;
    markNeedsLayout();
  }

  bool _wrap;
  set wrap(bool value) {
    if (value == _wrap) return;
    _wrap = value;
    markNeedsLayout();
  }

  BoxConstraints _inner(BoxConstraints outer) =>
      _wrap ? outer : BoxConstraints(minWidth: outer.minWidth);

  Size _outer(BoxConstraints constraints, Size inner) => constraints.constrain(
    Size(inner.width, math.max(0.0, inner.height - _lift)),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _outer(constraints, child!.getDryLayout(_inner(constraints)));

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(_inner(constraints), parentUsesSize: true);
    size = _outer(constraints, child.size);
    (child.parentData! as BoxParentData).offset = Offset(0, -_lift);
    if (child.size.width > size.width) onWidth(child.size.width);
  }
}
