import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/address_bar.dart';
import '../widgets/menu_view.dart';
import '../widgets/text_view.dart';
import 'bookmarks_screen.dart';
import 'history_screen.dart';
import 'web_landing_page.dart';
import 'web_library_screen.dart';
import '../services/native_companion.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI-2 Gopher')),
        body: const WebLandingPage(),
      );
    }
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI-2 Gopher'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (NativeCompanion.supported)
            IconButton(
              icon: const Icon(Icons.library_books_outlined),
              tooltip: 'Saved web pages',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WebLibraryScreen(),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: appState.canReload ? appState.reload : null,
          ),
          Consumer<AppState>(
            builder: (context, state, child) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: state.canGoBack ? () => state.goBack() : null,
                tooltip: 'Back',
              );
            },
          ),
          Consumer<AppState>(
            builder: (context, state, child) {
              return IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: state.canGoForward ? () => state.goForward() : null,
                tooltip: 'Forward',
              );
            },
          ),
          Consumer<AppState>(
            builder: (context, state, child) {
              final url = state.currentAddress?.toUrl();
              if (url == null || state.currentAddress!.isLocalQuestion) {
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
                    tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
                  );
                },
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: appState.selectedTab,
        children: const [BrowserTab(), BookmarksScreen(), HistoryScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: appState.selectedTab,
        onDestinationSelected: appState.selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.bookmark), label: 'Bookmarks'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
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
        ).showSnackBar(const SnackBar(content: Text('Bookmark removed')));
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
        title: const Text('Add Bookmark'),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, title),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final saved = await state.addBookmark(result, url);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bookmark added')));
      }
    }
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
                TextButton(
                  onPressed: state.init,
                  child: const Text('Try again'),
                ),
              ],
            );
          },
        ),
        Expanded(
          child: Consumer<AppState>(
            builder: (context, state, child) {
              if (state.isLoading) {
                final partial = state.partialMenu;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      // No animation once lines are showing: on an old
                      // computer it would take processor time from the model.
                      child: partial == null
                          ? const Center(child: CircularProgressIndicator())
                          : MenuView(
                              key: ValueKey(state.pageId),
                              items: partial,
                              follow: true,
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: state.cancelLoading,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
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
                              child: const Text('Retry'),
                            ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: state.clearError,
                            child: const Text('Dismiss'),
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
                          'Error',
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
                            child: const Text('Retry'),
                          ),
                        ElevatedButton(
                          onPressed: state.clearError,
                          child: const Text('Dismiss'),
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
                        items: state.currentMenu!,
                      ),
                    ),
                  ],
                );
              }

              if (state.currentContent != null) {
                return TextView(
                  content: state.currentContent!,
                  title: state.currentAddress?.type.code == 'h'
                      ? 'HTML source'
                      : (state.currentTitle ?? 'Text Document'),
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
                      'Welcome to Gopher',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter a gopher:// URL above to start browsing',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Example servers:',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
      ],
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
