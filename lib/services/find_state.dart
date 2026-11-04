import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Each letter to one letter, so a place in the folded text is the same place
// in the original. N with a tilde is not here: in Spanish it is its own letter,
// and "ano" is not "año".
const _plain = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ą': 'a',
  'ć': 'c',
  'ç': 'c',
  'č': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ę': 'e',
  'ě': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ł': 'l',
  'ń': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ś': 's',
  'š': 's',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
};

/// Without case or accents, and exactly as long as [text].
String _folded(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit < 0x80) {
      out.writeCharCode(unit >= 0x41 && unit <= 0x5A ? unit + 32 : unit);
      continue;
    }
    final char = String.fromCharCode(unit);
    final lower = char.toLowerCase();
    out.write(lower.length == 1 ? (_plain[lower] ?? lower) : char);
  }
  return out.toString();
}

/// One place a search matched: a line of the page and where in it.
class FindMatch {
  final int line;
  final int start;
  final int end;

  const FindMatch(this.line, this.start, this.end);
}

/// Find on this page. The page's view says what its lines are, in [report],
/// and shows the matches this holds; the bar changes the query and moves
/// between them.
class FindState extends ChangeNotifier {
  /// More than anyone steps through, and each one is a span to lay out on an
  /// old computer.
  static const limit = 2000;

  /// Null where there is no Find, as for a view shown on its own.
  static FindState? of(BuildContext context) =>
      Provider.of<FindState?>(context);

  bool _open = false;
  String _query = '';
  List<String> _lines = const [];
  int _searched = 0;
  int? _page;
  List<FindMatch> _matches = const [];
  Map<int, List<FindMatch>> _byLine = const {};
  int _current = -1;
  int _revision = 0;
  bool _notifying = false;
  bool _disposed = false;

  bool get isOpen => _open;
  String get query => _query;
  int get total => _matches.length;
  bool get reachedLimit => _matches.length >= limit;

  /// Position of the current match, counted from 1. 0 when there is none.
  int get position => _current + 1;
  FindMatch? get current => _current < 0 ? null : _matches[_current];

  /// Changes each time the page should bring the current match into sight.
  /// Text arriving does not change it, so nobody loses their place.
  int get revision => _revision;

  /// The bar asks for its box again: Ctrl+F while it is already open.
  int get focusRequests => _focusRequests;
  int _focusRequests = 0;

  List<FindMatch> on(int line) => _byLine[line] ?? const [];

  void open() {
    _open = true;
    _focusRequests++;
    notifyListeners();
  }

  void close() {
    _open = false;
    _query = '';
    _clear();
    notifyListeners();
  }

  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _search();
    _current = _matches.isEmpty ? -1 : 0;
    _revision++;
    notifyListeners();
  }

  void next() => _step(1);

  void previous() => _step(-1);

  void _step(int by) {
    if (_matches.isEmpty) return;
    _current = (_current + by) % _matches.length;
    _revision++;
    notifyListeners();
  }

  /// Another page: what was found belongs to the last one.
  void beginPage(int id) {
    if (id == _page) return;
    _page = id;
    _lines = const [];
    _clear();
    _notifyAfterBuild();
  }

  /// From a view's build, with the lines it is showing. A chat answer calls
  /// this with each word, so it does nothing unless they changed.
  void report(List<String> lines) {
    _lines = lines;
    if (_query.isEmpty) return;
    final searched = Object.hashAll(lines);
    if (searched == _searched) return;
    final before = current;
    final total = _matches.length;
    _search(searched);
    if (_matches.isEmpty) {
      _current = -1;
    } else if (before == null) {
      _current = 0;
      _revision++;
    } else {
      _current = _current.clamp(0, _matches.length - 1);
    }
    if (total != _matches.length || before == null) _notifyAfterBuild();
  }

  void _search([int? searched]) {
    _searched = searched ?? Object.hashAll(_lines);
    final found = <FindMatch>[];
    final byLine = <int, List<FindMatch>>{};
    if (_query.isNotEmpty) {
      final wanted = _folded(_query);
      outer:
      for (var line = 0; line < _lines.length; line++) {
        final text = _folded(_lines[line]);
        var from = 0;
        while (true) {
          final start = text.indexOf(wanted, from);
          if (start < 0) break;
          final match = FindMatch(line, start, start + wanted.length);
          found.add(match);
          (byLine[line] ??= []).add(match);
          if (found.length >= limit) break outer;
          from = match.end;
        }
      }
    }
    _matches = found;
    _byLine = byLine;
  }

  void _clear() {
    _matches = const [];
    _byLine = const {};
    _current = -1;
    _searched = 0;
  }

  void _notifyAfterBuild() {
    if (_notifying) return;
    _notifying = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifying = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// The accent of the reader is green, so the matches stand out in yellow.
const _found = Color(0x66FFD54F);
const _currentFound = Color(0xFFFFD54F);
const _onCurrentFound = Color(0xFF171B19);

/// [text] with the matches on [line] marked. Null when there is none, so a
/// page nobody is searching stays as plain as it was.
TextSpan? foundSpan(FindState? find, String text, int line, TextStyle? style) {
  if (find == null) return null;
  final matches = find.on(line);
  if (matches.isEmpty) return null;
  final current = find.current;
  final parts = <InlineSpan>[];
  var at = 0;
  for (final match in matches) {
    if (match.start > at) {
      parts.add(TextSpan(text: text.substring(at, match.start)));
    }
    parts.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: identical(match, current)
            ? const TextStyle(
                backgroundColor: _currentFound,
                color: _onCurrentFound,
              )
            : const TextStyle(backgroundColor: _found),
      ),
    );
    at = match.end;
  }
  if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: parts);
}

/// A line of a list page, with what Find found in it marked.
class FoundText extends StatelessWidget {
  final String text;
  final int line;
  final TextStyle? style;

  const FoundText(this.text, {super.key, required this.line, this.style});

  @override
  Widget build(BuildContext context) {
    final span = foundSpan(FindState.of(context), text, line, null);
    if (span == null) return Text(text, style: style);
    return Text.rich(span, style: style);
  }
}
