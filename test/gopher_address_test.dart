import 'package:flutter_test/flutter_test.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';

void main() {
  test('root addresses, typed selectors and default ports', () {
    expect(GopherAddress.fromUrl(' example.org ').selector, '');
    expect(GopherAddress.fromUrl('gopher://example.org').port, 70);
    final text = GopherAddress.fromUrl('gopher://example.org/0/readme.txt');
    expect(text.selector, '/readme.txt');
    expect(text.type, GopherItemType.file);
    expect(text.toUrl(), 'gopher://example.org:70/0/readme.txt');
    // The first selector character is significant even when it resembles a type.
    expect(
      GopherAddress.fromUrl('gopher://example.org/11docs').selector,
      '1docs',
    );
  });

  test('special selector characters and search queries round trip', () {
    for (final selector in ['/a b/?x=1#fragment%20', '/café', '', '//docs']) {
      final address = GopherAddress(
        host: 'example.org',
        selector: selector,
        type: GopherItemType.file,
      );
      expect(GopherAddress.fromUrl(address.toUrl()), address);
    }
    final search = GopherAddress.fromUrl(
      'gopher://example.org:7070/7search%09two%20words',
    );
    expect(search.selector, 'search');
    expect(search.query, 'two words');
    expect(search.request, 'search\ttwo words');
    expect(GopherAddress.fromUrl(search.toUrl()), search);
    expect(
      search,
      isNot(
        GopherAddress(
          host: search.host,
          port: search.port,
          selector: search.selector,
        ),
      ),
    );
  });

  test('menu links retain their type', () {
    final item = GopherItem.fromLine('0Read me\t/readme.txt\texample.org\t70');
    expect(item.isNavigable, isTrue);
    expect(item.toUrl(), 'gopher://example.org:70/0/readme.txt');
    expect(GopherAddress.fromUrl(item.toUrl()).type, GopherItemType.file);
  });

  test('IPv6 addresses can be serialized and parsed', () {
    final address = GopherAddress.fromUrl('gopher://[::1]:7070/0hello');
    expect(address.toUrl(), 'gopher://[::1]:7070/0hello');
    expect(GopherAddress.fromUrl(address.toUrl()), address);
  });

  test('invalid destinations and protocol delimiters are rejected', () {
    for (final url in [
      'gopher://',
      'https://example.org',
      'gopher://example.org:0/1',
      'gopher://example.org:65536/1',
      'gopher://example.org/0hi%0D%0Aquit',
      'gopher://example.org/0hi%09query',
      'gopher://example.org/7search%09hi%09+',
      'gopher://example.org/0hi?x=1',
      'gopher://user@example.org/1',
    ]) {
      expect(
        () => GopherAddress.fromUrl(url),
        throwsA(isA<ArgumentError>()),
        reason: url,
      );
    }
    expect(
      () => GopherAddress(host: 'example.org', selector: 'bad\tselector'),
      throwsArgumentError,
    );
  });
}
