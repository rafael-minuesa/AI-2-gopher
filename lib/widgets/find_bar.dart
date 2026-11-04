import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/find_state.dart';
import '../l10n/l10n.dart';

/// The row Ctrl+F opens above the page: the words, how many, up, down, close.
class FindBar extends StatefulWidget {
  const FindBar({super.key});

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final TextEditingController _box = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _typing;
  int _focusRequests = 0;

  /// Where the keyboard was, to give it back on closing: the chat's box.
  FocusNode? _before;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final find = context.read<FindState>();
    if (find.focusRequests != _focusRequests) {
      _focusRequests = find.focusRequests;
      _takeFocus();
    }
  }

  void _takeFocus() {
    final now = FocusManager.instance.primaryFocus;
    if (now != _focus) _before = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _box.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _box.text.length,
      );
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    _box.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Searching a long document with each key would make typing lag on an old
  /// computer.
  void _changed(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 200), () {
      if (mounted) context.read<FindState>().setQuery(text);
    });
  }

  void _settle() {
    _typing?.cancel();
    context.read<FindState>().setQuery(_box.text);
  }

  void _close() {
    _typing?.cancel();
    final before = _before;
    context.read<FindState>().close();
    if (before != null && before.canRequestFocus) before.requestFocus();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final find = context.read<FindState>();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_box.value.composing.isValid) return KeyEventResult.ignored;
      _settle();
      if (HardwareKeyboard.instance.isShiftPressed) {
        find.previous();
      } else {
        find.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final find = context.watch<FindState>();
    if (find.focusRequests != _focusRequests) {
      _focusRequests = find.focusRequests;
      _takeFocus();
    }
    final scheme = Theme.of(context).colorScheme;
    final nothing = find.query.isNotEmpty && find.total == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) => _onKey(event),
              child: TextField(
                controller: _box,
                focusNode: _focus,
                onChanged: _changed,
                decoration: InputDecoration(
                  hintText: t.findOnPage,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            nothing
                ? t.findNothing
                : find.total == 0
                ? ''
                : t.findCount(
                    find.position,
                    find.reachedLimit ? '${find.total}+' : '${find.total}',
                  ),
            style: TextStyle(
              color: nothing ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: t.findPrevious,
            onPressed: find.total == 0 ? null : find.previous,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: t.findNext,
            onPressed: find.total == 0 ? null : find.next,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: t.closeFind,
            onPressed: _close,
          ),
        ],
      ),
    );
  }
}

/// Keeps a key on each line of a long list that builds its lines lazily, and
/// brings one of them into sight though it may not have been built yet.
class ListFinder {
  final ScrollController scroll;
  final Map<int, GlobalKey> _keys = {};
  int _seen = 0;
  int _trip = 0;

  ListFinder(this.scroll);

  Widget keep(int line, Widget child) =>
      KeyedSubtree(key: _keys[line] ??= GlobalKey(), child: child);

  /// Call from build: goes to the current match when Find has moved to one.
  void follow(FindState? find) {
    if (find == null || find.revision == _seen) return;
    _seen = find.revision;
    final target = find.current;
    if (target == null) return;
    _go(target.line);
  }

  void _bringIntoSight(int line) {
    final context = _keys[line]?.currentContext;
    if (context != null) Scrollable.ensureVisible(context, alignment: 0.3);
  }

  Future<void> _go(int line) async {
    final trip = ++_trip;
    await WidgetsBinding.instance.endOfFrame;
    // The lines off screen only have an estimated height, so an offset cannot
    // be worked out. Narrow it down by which lines the list has built.
    var low = 0.0;
    double? high;
    for (var tries = 0; tries < 24; tries++) {
      if (trip != _trip || !scroll.hasClients) return;
      final built = _keys.entries
          .where((entry) => entry.value.currentContext != null)
          .map((entry) => entry.key)
          .toList();
      if (built.isEmpty) return;
      if (built.contains(line)) {
        _bringIntoSight(line);
        return;
      }
      final first = built.reduce((a, b) => a < b ? a : b);
      if (line < first) {
        high = scroll.offset;
      } else {
        low = scroll.offset;
      }
      final top = high ?? scroll.position.maxScrollExtent;
      scroll.jumpTo((low + top) / 2);
      await WidgetsBinding.instance.endOfFrame;
    }
  }
}
