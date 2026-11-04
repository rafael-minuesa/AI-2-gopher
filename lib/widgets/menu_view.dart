import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gopher_item.dart';
import '../services/app_state.dart';
import '../services/find_state.dart';
import 'find_bar.dart';
import '../l10n/l10n.dart';

class MenuView extends StatefulWidget {
  final List<GopherItem> items;

  /// More lines are on their way; keep the newest in sight.
  final bool follow;

  const MenuView({super.key, required this.items, this.follow = false});

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  final ScrollController _scroll = ScrollController();
  late final ListFinder _finder = ListFinder(_scroll);

  @override
  void didUpdateWidget(MenuView old) {
    super.didUpdateWidget(old);
    // Whoever scrolled up to reread stays where they are.
    if (old.follow &&
        widget.items.length > old.items.length &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 64) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final find = FindState.of(context);
    find?.report([for (final item in widget.items) item.displayText]);
    _finder.follow(find);
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        itemCount: widget.items.length,
        itemBuilder: (context, index) => _finder.keep(
          index,
          _MenuItemTile(item: widget.items[index], line: index),
        ),
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  final GopherItem item;
  final int line;

  const _MenuItemTile({required this.item, required this.line});

  @override
  Widget build(BuildContext context) {
    // Info items are not clickable
    if (item.type == GopherItemType.info) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: FoundText(
          item.displayText,
          line: line,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Error items
    if (item.type == GopherItemType.error) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: FoundText(
          item.displayText,
          line: line,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    // Navigable items
    return ListTile(
      leading: _getIcon(item.type),
      title: FoundText(item.displayText, line: line),
      // The address only says something about another computer.
      subtitle:
          (item.type == GopherItemType.directory ||
                  item.type == GopherItemType.file) &&
              !item.address.isLoopback
          ? Text(
              '${item.host}:${item.port}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: item.type.isNavigable ? const Icon(Icons.chevron_right) : null,
      onTap: item.type.isNavigable
          ? () {
              if (item.type == GopherItemType.search &&
                  !item.address.isLocalChat) {
                _showSearchDialog(context, item);
              } else {
                context.read<AppState>().navigateToItem(item);
              }
            }
          : null,
    );
  }

  Widget _getIcon(GopherItemType type) {
    IconData iconData;
    Color? color;

    switch (type) {
      case GopherItemType.directory:
        iconData = Icons.folder;
        color = Colors.blue;
        break;
      case GopherItemType.file:
        iconData = Icons.description;
        color = Colors.grey;
        break;
      case GopherItemType.search:
        iconData = Icons.search;
        color = Colors.green;
        break;
      case GopherItemType.gif:
      case GopherItemType.image:
        iconData = Icons.image;
        color = Colors.purple;
        break;
      case GopherItemType.binary:
      case GopherItemType.binhex:
      case GopherItemType.dos:
        iconData = Icons.file_download;
        color = Colors.orange;
        break;
      case GopherItemType.html:
        iconData = Icons.language;
        color = Colors.teal;
        break;
      case GopherItemType.error:
        iconData = Icons.error;
        color = Colors.red;
        break;
      case GopherItemType.info:
        iconData = Icons.info;
        color = Colors.grey;
        break;
      case GopherItemType.telnet:
      case GopherItemType.tn3270:
        iconData = Icons.terminal;
        color = Colors.cyan;
        break;
      default:
        iconData = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return Icon(iconData, color: color);
  }

  Future<void> _showSearchDialog(BuildContext context, GopherItem item) async {
    var query = '';
    // A search item on this computer is answered, often by a language model.
    final asking = GopherAddress(
      host: item.host,
      port: item.port,
      selector: item.selector,
      type: item.type,
    ).isLoopback;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.displayText),
        content: TextFormField(
          onChanged: (value) => query = value,
          decoration: InputDecoration(
            labelText: asking ? t.yourQuestion : t.searchQuery,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(asking ? Icons.question_answer : Icons.search),
          ),
          autofocus: true,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, query),
            child: Text(asking ? t.ask : t.search),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      await context.read<AppState>().search(item, result);
    }
  }
}
