import '../companion/protocol.dart';
import '../models/gopher_item.dart';

/// The views of a page saved from the browser, as the extension's reader has
/// them. The server still offers them as menu lines, for any other client.
enum SavedView { article, page, links }

const _id = r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
final _linksPath = RegExp('^/page/($_id)\$');
final _textPath = RegExp('^/text/($_id)/(article|page)\$');

/// Which saved page an address is, and in which view.
class SavedPage {
  final String id;
  final SavedView view;

  const SavedPage(this.id, this.view);

  static SavedPage? of(GopherAddress? address) {
    if (address == null || !address.isLoopback) return null;
    if (address.port != companionPort) return null;
    final links = _linksPath.firstMatch(address.selector);
    if (links != null) return SavedPage(links[1]!, SavedView.links);
    final text = _textPath.firstMatch(address.selector);
    if (text == null) return null;
    return SavedPage(
      text[1]!,
      text[2] == 'article' ? SavedView.article : SavedView.page,
    );
  }

  /// Where a page saved from the browser opens: the article, as in the
  /// extension's reader. Its Links view is one button away, and any other
  /// address stays as it is.
  static String opening(String url) {
    try {
      final saved = of(GopherAddress.fromUrl(url));
      return saved?.view == SavedView.links
          ? saved!.urlOf(SavedView.article)
          : url;
    } on ArgumentError {
      return url;
    } on FormatException {
      return url;
    }
  }

  String urlOf(SavedView view) => switch (view) {
    SavedView.article => 'gopher://127.0.0.1:$companionPort/0/text/$id/article',
    SavedView.page => 'gopher://127.0.0.1:$companionPort/0/text/$id/page',
    SavedView.links => 'gopher://127.0.0.1:$companionPort/1/page/$id',
  };
}

/// What the menu of a saved page says about it.
class SavedPageInfo {
  final String id;
  final String title;
  final GopherItem? original;

  const SavedPageInfo(this.id, this.title, this.original);

  factory SavedPageInfo.fromMenu(String id, List<GopherItem> menu) {
    final title = menu
        .where((item) => item.type == GopherItemType.info)
        .map((item) => item.displayText)
        .firstOrNull;
    return SavedPageInfo(
      id,
      title ?? '',
      _beforeLinks(menu)
          .where(
            (item) =>
                item.type == GopherItemType.html &&
                item.selector.startsWith('URL:'),
          )
          .firstOrNull,
    );
  }

  /// The menu without the lines the buttons replace. The links of the page
  /// come after its "Links" line and stay, whatever they point at.
  List<GopherItem> withoutViews(List<GopherItem> menu) {
    final top = _beforeLinks(menu);
    return [
      ...top.where(
        (item) =>
            !identical(item, original) &&
            !(item.type == GopherItemType.file &&
                item.selector.startsWith('/text/$id/')),
      ),
      ...menu.skip(top.length),
    ];
  }

  static Iterable<GopherItem> _beforeLinks(List<GopherItem> menu) =>
      menu.takeWhile(
        (item) =>
            !(item.type == GopherItemType.info && item.displayText == 'Links'),
      );
}
