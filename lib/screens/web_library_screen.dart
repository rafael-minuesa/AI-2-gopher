import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/native_companion.dart';
import '../companion/client.dart';
import '../l10n/l10n.dart';

class WebLibraryScreen extends StatefulWidget {
  final CompanionClient? client;
  const WebLibraryScreen({super.key, this.client});
  @override
  State<WebLibraryScreen> createState() => _WebLibraryScreenState();
}

class _WebLibraryScreenState extends State<WebLibraryScreen> {
  List<dynamic> _pages = [];
  String? _error;
  bool _loading = true;
  CompanionClient get _client => widget.client ?? NativeCompanion.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _client.request({'action': 'list'}, start: true);
      if (mounted) {
        setState(() {
          _pages = result['pages'] as List;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> page) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.removeSavedCopyQuestion),
        content: Text(page['title'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (remove != true) return;
    try {
      await _client.request({'action': 'remove', 'id': page['id']});
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _stop() async {
    try {
      await _client.request({'action': 'stop'});
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.servingStopped)));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t.savedWebPages),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: t.refreshLibrary,
        ),
        TextButton(
          onPressed: _loading || _error != null ? null : _stop,
          child: Text(t.stopServing),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t.libraryIntro),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_error!),
                ),
              if (_error != null)
                TextButton(onPressed: _load, child: Text(t.tryAgain)),
              if (_pages.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t.libraryEmpty),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index] as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(page['title'] as String),
                      subtitle: Text(page['source'] as String),
                      onTap: page['url'] == null
                          ? null
                          : () {
                              final state = context.read<AppState>();
                              Navigator.pop(context);
                              state.selectTab(0);
                              state.navigate(
                                page['url'] as String,
                                title: page['title'] as String,
                              );
                            },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: t.removeSavedCopy,
                        onPressed: () => _remove(page),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
