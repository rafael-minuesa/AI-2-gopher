import 'dart:io' show FileSystemException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/export_text.dart';
import '../services/find_state.dart';
import '../services/saved_page.dart';
import '../widgets/address_bar.dart';
import '../widgets/chat_view.dart';
import '../widgets/find_bar.dart';
import '../widgets/menu_view.dart';
import '../widgets/text_view.dart';
import 'bookmarks_screen.dart';
import 'history_screen.dart';
import 'web_landing_page.dart';
import 'web_library_screen.dart';
import '../services/native_companion.dart';
import '../l10n/l10n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FindState _find = FindState();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _find.dispose();
    super.dispose();
  }

  void _openFind(AppState state) {
    state.selectTab(0);
    _find.open();
  }

  Future<void> _export(AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await () async {
      try {
        final path = await exportText(
          _find.pageLines.join('\n'),
          state.exportName,
        );
        return t.exportedTo(path);
      } on FileSystemException catch (error) {
        return t.exportFailed(error.osError?.message ?? error.message);
      }
    }();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Here rather than in a Shortcuts widget, which needs the keyboard to be
  /// somewhere inside it, and on a menu page it is nowhere.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || kIsWeb) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final state = context.read<AppState>();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f3 && _find.isOpen) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _find.previous();
      } else {
        _find.next();
      }
      return true;
    }
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (key == LogicalKeyboardKey.keyF) {
      _openFind(state);
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      state.growText();
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      state.shrinkText();
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      state.resetTextSize();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI-2 Gopher')),
        body: const WebLandingPage(),
      );
    }
    final appState = context.watch<AppState>();
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return ChangeNotifierProvider<FindState>.value(
      value: _find,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI-2 Gopher'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (narrow)
              PopupMenuButton<VoidCallback>(
                icon: const Icon(Icons.text_fields),
                tooltip: t.textAndFind,
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: appState.shrinkText,
                    enabled: appState.canShrinkText,
                    child: Text(t.smallerText),
                  ),
                  PopupMenuItem(
                    value: appState.growText,
                    enabled: appState.canGrowText,
                    child: Text(t.largerText),
                  ),
                  PopupMenuItem(
                    value: () => _openFind(appState),
                    child: Text(t.findOnPage),
                  ),
                  if (canExportText)
                    PopupMenuItem(
                      value: () => _export(appState),
                      enabled: appState.canExport,
                      child: Text(t.exportText),
                    ),
                ],
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.text_decrease),
                tooltip: t.smallerText,
                onPressed: appState.canShrinkText ? appState.shrinkText : null,
              ),
              IconButton(
                icon: const Icon(Icons.text_increase),
                tooltip: t.largerText,
                onPressed: appState.canGrowText ? appState.growText : null,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: t.findOnPage,
                onPressed: () => _openFind(appState),
              ),
              if (canExportText)
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  tooltip: t.exportText,
                  onPressed: appState.canExport
                      ? () => _export(appState)
                      : null,
                ),
            ],
            if (NativeCompanion.supported)
              IconButton(
                icon: const Icon(Icons.library_books_outlined),
                tooltip: t.savedWebPages,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WebLibraryScreen(),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: t.reload,
              onPressed: appState.canReload ? appState.reload : null,
            ),
            Consumer<AppState>(
              builder: (context, state, child) {
                return IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: state.canGoBack ? () => state.goBack() : null,
                  tooltip: t.back,
                );
              },
            ),
            Consumer<AppState>(
              builder: (context, state, child) {
                return IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: state.canGoForward
                      ? () => state.goForward()
                      : null,
                  tooltip: t.forward,
                );
              },
            ),
            Consumer<AppState>(
              builder: (context, state, child) {
                final url = state.currentAddress?.toUrl();
                if (url == null ||
                    state.currentAddress!.isLocalQuestion ||
                    state.currentAddress!.isLocalChat ||
                    state.currentAddress!.isLocalChatMenu) {
                  return const SizedBox.shrink();
                }

                return FutureBuilder<bool>(
                  future: state.isBookmarked(url),
                  builder: (context, snapshot) {
                    final isBookmarked = snapshot.data ?? false;
                    return IconButton(
                      icon: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      ),
                      onPressed: () => _toggleBookmark(context, state, url),
                      tooltip: isBookmarked ? t.removeBookmark : t.addBookmark,
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: appState.selectedTab,
          children: const [
            BrowserTab(),
            _ReadingSize(child: BookmarksScreen()),
            _ReadingSize(child: HistoryScreen()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: appState.selectedTab,
          onDestinationSelected: appState.selectTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.public),
              label: t.browse,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmark),
              label: t.bookmarks,
            ),
            NavigationDestination(
              icon: const Icon(Icons.history),
              label: t.history,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBookmark(
    BuildContext context,
    AppState state,
    String url,
  ) async {
    final isBookmarked = await state.isBookmarked(url);
    if (!context.mounted) return;

    if (isBookmarked) {
      final removed = await state.removeBookmark(url);
      if (removed && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.bookmarkRemoved)));
      }
    } else {
      await _showBookmarkDialog(context, state, url);
    }
  }

  Future<void> _showBookmarkDialog(
    BuildContext context,
    AppState state,
    String url,
  ) async {
    var title = state.currentTitle ?? url;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.addBookmarkTitle),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
          decoration: InputDecoration(
            labelText: t.titleLabel,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, title),
            child: Text(t.add),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final saved = await state.addBookmark(result, url);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.bookmarkAdded)));
      }
    }
  }
}

/// What is read follows A- and A+. The bars around it stay put, so the buttons
/// do not move away from under the mouse.
class _ReadingSize extends StatelessWidget {
  final Widget child;

  const _ReadingSize({required this.child});

  @override
  Widget build(BuildContext context) {
    final size = context.select<AppState, double>((s) => s.textSize);
    final data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        textScaler: TextScaler.linear(data.textScaler.scale(1) * size),
      ),
      child: child,
    );
  }
}

/// What a question to this computer shows until its first line: nothing that
/// moves.
class _StillWait extends StatelessWidget {
  const _StillWait();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(t.workingOnThisComputer, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class BrowserTab extends StatelessWidget {
  const BrowserTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AddressBar(),
        Consumer<AppState>(
          builder: (context, state, child) {
            if (state.storageWarning == null) return const SizedBox.shrink();
            return MaterialBanner(
              content: Text(state.storageWarning!),
              actions: [
                TextButton(onPressed: state.init, child: Text(t.tryAgain)),
              ],
            );
          },
        ),
        Consumer<FindState>(
          builder: (context, find, child) =>
              find.isOpen ? const FindBar() : const SizedBox.shrink(),
        ),
        const Align(alignment: Alignment.centerLeft, child: _SavedPageBar()),
        Expanded(
          child: _ReadingSize(
            child: Consumer<AppState>(
              builder: (context, state, child) {
                context.read<FindState>().beginPage(state.pageId);
                if (state.isChat) return const ChatView();

                if (state.isLoading) {
                  final partial = state.partialMenu;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        // No animation while this computer works on the
                        // answer: on an old computer it takes processor time
                        // from the model. Measured on a 2-core machine, a
                        // spinner made a 3 second search take nearly 6.
                        child: partial == null
                            ? state.isAskingLocally
                                  ? const _StillWait()
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    )
                            : MenuView(
                                key: ValueKey(state.pageId),
                                items: partial,
                                follow: state.isAskingLocally,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: state.cancelLoading,
                            icon: const Icon(Icons.close),
                            label: Text(t.cancel),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (state.error != null && state.partialMenu != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MenuView(
                          key: ValueKey(state.pageId),
                          items: state.partialMenu!,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: SelectableText(state.error!)),
                            const SizedBox(width: 8),
                            if (state.canRetry)
                              OutlinedButton(
                                onPressed: state.retry,
                                child: Text(t.retry),
                              ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: state.clearError,
                              child: Text(t.dismiss),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (state.error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t.errorHeading,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.error!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          if (state.canRetry)
                            ElevatedButton(
                              onPressed: state.retry,
                              child: Text(t.retry),
                            ),
                          ElevatedButton(
                            onPressed: state.clearError,
                            child: Text(t.dismiss),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state.currentMenu != null) {
                  // Same tree as while it was arriving, so the scroll position
                  // survives the last line.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MenuView(
                          key: ValueKey(state.pageId),
                          items: state.shownMenu!,
                        ),
                      ),
                    ],
                  );
                }

                if (state.currentContent != null) {
                  return TextView(
                    content: state.currentContent!,
                    title: state.currentAddress?.type.code == 'h'
                        ? t.htmlSource
                        : (state.savedInfo?.title ??
                              state.currentTitle ??
                              t.textDocument),
                  );
                }

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.public,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.welcome,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(t.enterUrlToStart, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      Text(
                        t.exampleServers,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const _ExampleLink('gopher://gopher.floodgap.com'),
                      const _ExampleLink('gopher://gopher.quux.org'),
                      const _ExampleLink('gopher://gopherpedia.com'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Article, Full page, Links and the original page, as in the browser
/// extension's reader.
class _SavedPageBar extends StatelessWidget {
  const _SavedPageBar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.savedPage;
    if (saved == null) return const SizedBox.shrink();
    final original = state.savedInfo?.original;
    // From the left, so Original page arriving does not move the others.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<SavedView>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: SavedView.article, label: Text(t.article)),
              ButtonSegment(value: SavedView.page, label: Text(t.fullPage)),
              ButtonSegment(value: SavedView.links, label: Text(t.links)),
            ],
            selected: {saved.view},
            onSelectionChanged: state.isLoading
                ? null
                : (views) => state.navigate(saved.urlOf(views.first)),
          ),
          if (original != null)
            TextButton.icon(
              onPressed: () => state.navigateToItem(original),
              icon: const Icon(Icons.open_in_browser),
              label: Text(t.originalPage),
            ),
        ],
      ),
    );
  }
}

class _ExampleLink extends StatelessWidget {
  final String url;

  const _ExampleLink(this.url);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        context.read<AppState>().navigate(url);
      },
      child: Text(url),
    );
  }
}
