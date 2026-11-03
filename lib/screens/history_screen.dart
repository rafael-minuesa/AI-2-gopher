import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/storage_service.dart';
import '../l10n/l10n.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        if (state.history.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  t.noHistory,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(t.historyWillAppear, textAlign: TextAlign.center),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _confirmClearHistory(context, state),
                    icon: const Icon(Icons.delete_sweep),
                    label: Text(t.clearHistory),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.history.length,
                itemBuilder: (context, index) {
                  final entry = state.history[index];
                  return _HistoryItem(entry: entry);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    AppState state,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.clearHistory),
        content: Text(t.removeAllHistory),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.clear),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final cleared = await state.clearHistory();
      if (cleared && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.historyCleared)));
      }
    }
  }
}

class _HistoryItem extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.public),
      title: Text(entry.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.url, style: Theme.of(context).textTheme.bodySmall),
          Text(
            _formatTimestamp(context, entry.timestamp),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () {
        context.read<AppState>().navigate(entry.url, title: entry.title);
      },
    );
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return t.justNow;
    } else if (diff.inHours < 1) {
      return t.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return t.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return t.daysAgo(diff.inDays);
    } else {
      return MaterialLocalizations.of(context).formatShortDate(timestamp);
    }
  }
}
