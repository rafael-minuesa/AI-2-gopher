import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/gopher_item.dart';
import '../services/app_state.dart';
import '../l10n/l10n.dart';

/// The conversation and the box for the next question, on one page. A chat
/// page is still a Gopher menu: its two search items become the box and the
/// button here, and any other client shows them as items.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  // What the server reads as one request is 4096 bytes, and these are at most
  // 3 bytes each. It is also more than a small model can take in.
  static const _maxQuestion = 1300;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _box = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _following = true;

  @override
  void initState() {
    super.initState();
    // Whoever scrolled up to reread stays where they are.
    _scroll.addListener(() => _following = _scroll.position.extentAfter < 64);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _box.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _follow([int tries = 4]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following || !_scroll.hasClients) return;
      if (_scroll.position.extentAfter <= 0) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      // Lines not laid out yet only have an estimated height.
      if (tries > 1) _follow(tries - 1);
    });
  }

  void _send(AppState state) {
    if (state.isLoading) return;
    // Gopher asks in one line.
    final question = _box.text
        .replaceAll(RegExp(r'\s*[\r\n\t]+\s*'), ' ')
        .trim();
    if (question.isEmpty) return;
    _box.clear();
    _following = true;
    state.askChat(question);
    _focus.requestFocus();
  }

  KeyEventResult _onKey(AppState state, KeyEvent event) {
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is! KeyDownEvent ||
        !enter ||
        HardwareKeyboard.instance.isShiftPressed ||
        _box.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    _send(state);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.chatItems;
    final lines = items
        .where((item) => item.type != GopherItemType.search)
        .toList();
    // Only until the first words of the answer.
    if (!state.isLoading || lines.isEmpty || !lines.last.isChatStatus) {
      lines.removeWhere((item) => item.isChatStatus);
    }
    final fresh = items
        .where((i) => i.isSearchItem && i.selector == '/chat')
        .firstOrNull;
    final hasConversation = items.any(
      (i) => i.isSearchItem && i.selector.startsWith('/chat/'),
    );
    _follow();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: lines.length,
                itemBuilder: (context, index) => _ChatLine(item: lines[index]),
              ),
            ),
          ),
          if (state.error != null) _problem(context, state),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) => _onKey(state, event),
                    child: TextField(
                      controller: _box,
                      focusNode: _focus,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(_maxQuestion),
                      ],
                      decoration: InputDecoration(
                        hintText: t.yourQuestion,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (state.isLoading)
                  OutlinedButton.icon(
                    onPressed: state.cancelLoading,
                    icon: const Icon(Icons.close),
                    label: Text(t.cancel),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _send(state),
                    icon: const Icon(Icons.send),
                    label: Text(t.ask),
                  ),
              ],
            ),
          ),
          if (fresh != null && hasConversation && !state.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    _following = true;
                    state.navigateToItem(fresh);
                    _focus.requestFocus();
                  },
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(fresh.displayText),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _problem(BuildContext context, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(state.error!)),
          const SizedBox(width: 8),
          if (state.canRetry)
            OutlinedButton(onPressed: state.retry, child: Text(t.retry)),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: state.clearError, child: Text(t.dismiss)),
        ],
      ),
    );
  }
}

class _ChatLine extends StatelessWidget {
  final GopherItem item;

  const _ChatLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = item.displayText;
    if (text.isEmpty) return const SizedBox(height: 12);
    final style = Theme.of(context).textTheme.bodyMedium;
    if (item.isChatStatus) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
        child: _Dots(
          text: text,
          style: style?.copyWith(color: scheme.onSurface),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      child: Text(
        text,
        style: item.type == GopherItemType.error
            ? style?.copyWith(color: scheme.error)
            : text.startsWith('> ')
            ? style?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              )
            : style?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}

/// One, two, three dots, while the model is silent. Twice a second on one line:
/// a smooth animation would take processor time from the model.
class _Dots extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _Dots({required this.text, this.style});

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> {
  late final Timer _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _dots = _dots % 3 + 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.text.replaceFirst(RegExp(r'[\s.]+$'), '');
    return Text('$words ${'.' * _dots}', style: widget.style);
  }
}
