/// Represents a Gopher menu item type
enum GopherItemType {
  file('0'), // Text file
  directory('1'), // Directory/menu
  ccso('2'), // CCSO nameserver
  error('3'), // Error
  binhex('4'), // BinHex file
  dos('5'), // DOS binary archive
  uuencoded('6'), // UUencoded file
  search('7'), // Index-Search server
  telnet('8'), // Telnet session
  binary('9'), // Binary file
  redundant('+'), // Redundant server
  tn3270('T'), // TN3270 session
  gif('g'), // GIF image
  image('I'), // Image file
  info('i'), // Informational message
  html('h'), // HTML file
  unknown('?'); // Unknown type

  final String code;
  const GopherItemType(this.code);

  static GopherItemType fromCode(String code) {
    for (var type in GopherItemType.values) {
      if (type.code == code) return type;
    }
    return GopherItemType.unknown;
  }

  bool get isNavigable =>
      this == GopherItemType.directory ||
      this == GopherItemType.file ||
      this == GopherItemType.search ||
      this == GopherItemType.html;

  bool get isDownloadable =>
      this == GopherItemType.binary ||
      this == GopherItemType.gif ||
      this == GopherItemType.image ||
      this == GopherItemType.binhex ||
      this == GopherItemType.dos;
}

/// Represents a Gopher menu item
class GopherItem {
  final GopherItemType type;
  final String displayText;
  final String selector;
  final String host;
  final int port;

  GopherItem({
    required this.type,
    required this.displayText,
    required this.selector,
    required this.host,
    required this.port,
  });

  bool get isNavigable => type.isNavigable;

  bool get isSearchItem => type == GopherItemType.search;

  /// A line about the answer being written, not part of the conversation.
  bool get isChatStatus =>
      type == GopherItemType.info && selector == '/chat-status';

  /// Parse a Gopher menu line
  /// Format: <type><display text><TAB><selector><TAB><host><TAB><port>
  factory GopherItem.fromLine(String line) {
    if (line.isEmpty) {
      return GopherItem(
        type: GopherItemType.info,
        displayText: '',
        selector: '',
        host: '',
        port: 70,
      );
    }

    final type = GopherItemType.fromCode(line[0]);
    final parts = line.substring(1).split('\t');

    if (type.isNavigable &&
        (parts.length < 4 ||
            parts[2].isEmpty ||
            int.tryParse(parts[3]) == null)) {
      throw const FormatException('Incomplete Gopher menu item');
    }

    return GopherItem(
      type: type,
      displayText: parts.isNotEmpty ? parts[0] : '',
      selector: parts.length > 1 ? parts[1] : '',
      host: parts.length > 2 ? parts[2] : '',
      port: parts.length > 3 ? int.tryParse(parts[3]) ?? 70 : 70,
    );
  }

  /// Convert to a Gopher URL
  String toUrl() {
    if (host.isEmpty) return '';
    return address.toUrl();
  }

  GopherAddress get address =>
      GopherAddress(host: host, port: port, selector: selector, type: type);

  @override
  String toString() {
    return 'GopherItem(type: $type, text: $displayText, host: $host:$port, selector: $selector)';
  }
}

/// Represents a Gopher address
class GopherAddress {
  final String host;
  final int port;
  final String selector;
  final GopherItemType type;
  final String? query;

  GopherAddress({
    required this.host,
    this.port = 70,
    this.selector = '',
    this.type = GopherItemType.directory,
    this.query,
  }) {
    if (host.isEmpty || RegExp(r'\s|[/@?#]').hasMatch(host)) {
      throw ArgumentError('Enter a valid Gopher host');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('Port must be between 1 and 65535');
    }
    if (RegExp(r'[\r\n\t]').hasMatch(selector) ||
        (query != null && RegExp(r'[\r\n\t]').hasMatch(query!))) {
      throw ArgumentError(
        'Selectors and queries cannot contain tabs or newlines',
      );
    }
    if (query != null && type != GopherItemType.search) {
      throw ArgumentError('Only search addresses can contain a query');
    }
  }

  /// Parse a Gopher URL
  /// Format: gopher://host:port/<type><selector>[%09<query>].
  factory GopherAddress.fromUrl(String url) {
    final input = url.trim();
    final uri = Uri.parse(input.contains('://') ? input : 'gopher://$input');

    if (uri.scheme != 'gopher') {
      throw ArgumentError('Invalid Gopher URL: must start with gopher://');
    }

    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError(
        'Encode selector characters such as ? and # in the URL',
      );
    }

    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final type = path.isEmpty
        ? GopherItemType.directory
        : GopherItemType.fromCode(path[0]);
    if (type == GopherItemType.unknown) {
      throw ArgumentError('Unknown Gopher item type');
    }
    final fields = (path.isEmpty ? '' : path.substring(1)).split(
      RegExp('%09', caseSensitive: false),
    );
    if (fields.length > 2) {
      throw ArgumentError('Gopher+ requests are not supported');
    }

    return GopherAddress(
      host: uri.host,
      // Uri normalizes an explicit :0 away for schemes without a known port.
      port: _portFromInput(input),
      selector: Uri.decodeComponent(fields[0]),
      type: type,
      query: fields.length == 2 ? Uri.decodeComponent(fields[1]) : null,
    );
  }

  static int _portFromInput(String input) {
    final authority = (input.contains('://') ? input.split('://').last : input)
        .split('/')
        .first;
    final match = RegExp(r':([0-9]+)$').firstMatch(authority);
    return match == null ? 70 : int.parse(match.group(1)!);
  }

  String toUrl() {
    final authority = host.contains(':') && !host.startsWith('[')
        ? '[$host]'
        : host;
    final path = Uri.encodeComponent(selector).replaceAll('%2F', '/');
    final search = query == null ? '' : '%09${Uri.encodeComponent(query!)}';
    return 'gopher://$authority:$port/${type.code}$path$search';
  }

  String get request => query == null ? selector : '$selector\t$query';

  bool get isLoopback => const {
    '127.0.0.1',
    'localhost',
    '::1',
    '[::1]',
  }.contains(host.toLowerCase());

  /// A question put to a server on this computer, which may be a language
  /// model: slow to answer, and asking it again is not the same as reading it
  /// again.
  bool get isLocalQuestion =>
      type == GopherItemType.search && query != null && isLoopback;

  /// The AI-2 chat on this computer. It opens with no question, because its
  /// page has the box for one.
  bool get isLocalChat =>
      type == GopherItemType.search &&
      isLoopback &&
      (selector == '/chat' || selector.startsWith('/chat/'));

  /// The menus of saved conversations. They stay out of history like the chat.
  bool get isLocalChatMenu =>
      type == GopherItemType.directory &&
      isLoopback &&
      (selector == '/chats' || selector.startsWith('/chats/'));

  /// A conversation is one page, whatever was asked in it.
  String get shownUrl => isLocalChat
      ? GopherAddress(
          host: host,
          port: port,
          selector: '/chat',
          type: type,
        ).toUrl()
      : toUrl();

  @override
  String toString() => toUrl();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GopherAddress &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          selector == other.selector &&
          type == other.type &&
          query == other.query;

  @override
  int get hashCode => Object.hash(host, port, selector, type, query);
}
