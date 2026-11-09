import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../services/find_state.dart';
import 'find_bar.dart';
import '../l10n/l10n.dart';

/// A document as the pieces the reader builds one at a time.
class ReaderPieces {
  final List<String> texts;

  /// True for a piece that goes on from the one before in the middle of a
  /// line. Every other piece but the first comes after a line end.
  final List<bool> continued;

  /// Where in the document each piece begins.
  final List<int> starts;

  const ReaderPieces(this.texts, this.continued, this.starts);

  static const none = ReaderPieces([''], [false], [0]);

  /// The document again.
  String join() {
    final out = StringBuffer();
    for (var i = 0; i < texts.length; i++) {
      if (i > 0 && !continued[i]) out.write('\n');
      out.write(texts[i]);
    }
    return out.toString();
  }
}

/// [text] cut into pieces: a paragraph with the blank lines after it, at most
/// [lines] lines where there are no blank lines, and at most [size]
/// characters. A line longer than that is cut inside, after a space where it
/// has one, and is then shown as several lines even unwrapped. Without this
/// one long line would be laid out whole, however long.
ReaderPieces readerPieces(String text, {int lines = 40, int size = 8000}) {
  final texts = <String>[];
  final continued = <bool>[];
  final starts = <int>[];
  var start = 0;
  var count = 0;
  var afterBlank = false;
  var goesOn = false;
  var at = 0;

  void close(int end) {
    texts.add(text.substring(start, end));
    continued.add(goesOn);
    starts.add(start);
    goesOn = false;
    count = 0;
  }

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
    if (count > 0 &&
        ((afterBlank && !blank) || count >= lines || end - start > size)) {
      close(at - 1);
      start = at;
    }
    while (end - start > size) {
      // Only ever a line by itself: anything before it was closed above.
      final cut = _cut(text, start, start + size);
      close(cut);
      start = cut;
      goesOn = true;
    }
    count++;
    afterBlank = blank;
    at = end + 1;
  }
  close(text.length);
  return ReaderPieces(texts, continued, starts);
}

/// Where to cut a line that is too long: after the last space in the second
/// half of what fits, or else at the limit, and never inside a character
/// made of two code units or between a letter and the mark on it.
int _cut(String text, int start, int limit) {
  for (var i = limit; i > start + (limit - start) ~/ 2; i--) {
    if (text.codeUnitAt(i - 1) == 0x20) return i;
  }
  var cut = limit;
  while (cut > start + 1 && _joinsBefore(text.codeUnitAt(cut))) {
    cut--;
  }
  return cut;
}

bool _joinsBefore(int unit) =>
    (unit >= 0xDC00 && unit <= 0xDFFF) || // second half of a pair
    (unit >= 0x0300 && unit <= 0x036F) || // combining marks
    (unit >= 0x20D0 && unit <= 0x20FF) ||
    (unit >= 0xFE00 && unit <= 0xFE0F) || // variation selectors
    unit == 0x200D; // joiner

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
  ReaderPieces _pieces = ReaderPieces.none;
  String? _piecesOf;

  /// How wide the unwrapped text is. A guess from the longest lines, and each
  /// piece says so when it turns out wider.
  double _wide = 0;
  List<Object?> _wideFor = const [];
  bool _widening = false;

  /// One line of this text, to move each piece up by. See [_Block].
  double _line = 0;
  List<Object?> _lineFor = const [];

  /// Select all was the last thing done to the selection. Only the pieces
  /// near the window can hold a selection, so everything is then taken to be
  /// selected, built or not.
  bool _all = false;
  bool _selectingAll = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    final here =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<_TextViewState>() ==
        this;
    if (!here) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      // The key goes on to the selection, which says it changed.
      _all = true;
      _selectingAll = true;
      Future(() => _selectingAll = false);
    } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
      // The key goes on to the selection, which copies what its pieces
      // hold. This comes after it.
      final text = _selected();
      if (text != null) {
        Future(() => Clipboard.setData(ClipboardData(text: text)));
      }
    }
    return false;
  }

  void _selectionChanged(SelectedContent? content) {
    if (!_selectingAll) _all = false;
  }

  RenderParagraph? _paragraph(BuildContext piece) {
    RenderParagraph? paragraph;
    void look(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph) {
        paragraph = object;
      } else {
        object.visitChildren(look);
      }
    }

    piece.findRenderObject()?.visitChildren(look);
    return paragraph;
  }

  /// A piece that comes after a line end is shown starting with that line
  /// end, so a place in it is one further on than in the piece's own text.
  int _shift(int index) => index == 0 || _pieces.continued[index] ? 0 : 1;

  /// What is selected, taken from the document: from where the selection
  /// begins in its first piece to where it ends in its last. What the pieces
  /// hand over themselves has no line end where the selection runs off the
  /// end of a piece, so paragraphs would come out with no line between them.
  /// Null when nothing is selected.
  String? _selected() {
    if (_all) return widget.content;
    int? from;
    int? to;
    for (final (index, piece) in _finder.lines) {
      if (index >= _pieces.starts.length) continue;
      final paragraph = _paragraph(piece);
      if (paragraph == null) continue;
      final start = _pieces.starts[index] - _shift(index);
      // Flutter marks this for its tests only, and offers the same through
      // a listener widget around each piece, which is one more layer on every
      // piece to read two numbers.
      // ignore: invalid_use_of_visible_for_testing_member
      for (final selection in paragraph.selections) {
        if (selection.isCollapsed) continue;
        final first = start + selection.start;
        final last = start + selection.end;
        if (from == null || first < from) from = first;
        if (to == null || last > to) to = last;
      }
    }
    if (from == null || to == null) return null;
    final content = widget.content;
    return content.substring(
      from.clamp(0, content.length),
      to.clamp(0, content.length),
    );
  }

  Widget _menu(BuildContext context, SelectableRegionState region) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        for (final item in region.contextMenuButtonItems)
          if (item.type == ContextMenuButtonType.selectAll)
            item.copyWith(
              onPressed: () {
                item.onPressed?.call();
                _all = true;
              },
            )
          else if (item.type == ContextMenuButtonType.copy)
            item.copyWith(
              onPressed: () {
                final text = _selected();
                item.onPressed?.call();
                if (text != null) Clipboard.setData(ClipboardData(text: text));
              },
            )
          else
            item,
      ],
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _finder.stop();
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
    // The three longest lines. A line is never longer than a piece.
    final longest = <String>[];
    for (final piece in _pieces.texts) {
      var at = 0;
      while (at <= piece.length) {
        var end = piece.indexOf('\n', at);
        if (end < 0) end = piece.length;
        if (longest.length < 3 || end - at > longest.last.length) {
          longest.add(piece.substring(at, end));
          longest.sort((a, b) => b.length.compareTo(a.length));
          if (longest.length > 3) longest.removeLast();
        }
        at = end + 1;
      }
    }
    _wide = 0;
    for (final text in longest) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
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
    final text = _paragraph(piece);
    if (text == null || !_down.hasClients) return;
    final shift = _shift(match.line);
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
    if (!identical(_piecesOf, widget.content)) {
      _piecesOf = widget.content;
      _pieces = readerPieces(widget.content);
    }
    final blocks = _pieces.texts;
    final continued = _pieces.continued;
    final find = FindState.of(context);
    find?.report(blocks, continued: continued);
    _finder.follow(find);
    final whole = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final line = _lineHeight(whole, scaler);
    if (!_wrap) _measure(whole, scaler);
    final wrap = _wrap;

    Widget piece(BuildContext context, int index) {
      final found = foundSpan(find, blocks[index], index, null);
      final Widget text;
      if (index == 0 || continued[index]) {
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
          lift: index == 0 || continued[index] ? 0 : line,
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
              contextMenuBuilder: _menu,
              onSelectionChanged: _selectionChanged,
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
