import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// מסנן HTML משותף לתוכן ספרים לפני העברתו למנוע התצוגה.
class BookHtmlSanitizer {
  const BookHtmlSanitizer();

  static const _allowedTags = {
    'a',
    'b',
    'blockquote',
    'br',
    'code',
    'del',
    'div',
    'em',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'i',
    'img',
    'li',
    'ol',
    'p',
    'pre',
    'span',
    'strong',
    'table',
    'tbody',
    'td',
    'th',
    'thead',
    'tr',
    'ul',
  };
  static const _globalAttributes = {'class', 'dir', 'id', 'lang', 'title'};
  static const _tagAttributes = {
    // `name` נשמר: מסמכי Markdown רבים מגדירים יעדי קישור פנימיים בעזרת
    // `<a name="…"></a>` לפני הכותרת, ובלעדיו הקישורים אינם ניתנים לפתרון.
    'a': {'href', 'name'},
    'img': {'alt', 'height', 'src', 'width'},
    'ol': {'start'},
    'td': {'colspan', 'rowspan'},
    'th': {'colspan', 'rowspan', 'scope'},
  };

  /// מסיר אלמנטים, מאפייני אירועים וכתובות URL שאינם בטוחים.
  String sanitize(String source) {
    final fragment = html_parser.parseFragment(source);
    for (final node in fragment.nodes.toList()) {
      _sanitizeNode(node);
    }
    return fragment.outerHtml;
  }

  void _sanitizeNode(Node node) {
    if (node is! Element) {
      for (final child in node.nodes.toList()) {
        _sanitizeNode(child);
      }
      return;
    }
    final tag = node.localName;
    if (!_allowedTags.contains(tag)) {
      if (const {
        'script',
        'style',
        'iframe',
        'object',
        'embed',
        'svg',
      }.contains(tag)) {
        node.remove();
      } else {
        node.replaceWith(Text(node.text));
      }
      return;
    }

    final allowed = {..._globalAttributes, ...?_tagAttributes[tag]};
    for (final attribute in node.attributes.keys.toList()) {
      final name = attribute.toString().toLowerCase();
      if (!allowed.contains(name) || name.startsWith('on')) {
        node.attributes.remove(attribute);
      }
    }
    _sanitizeClass(node);
    if (tag == 'a') {
      _sanitizeUrlAttribute(node, 'href', allowDataImages: false);
    } else if (tag == 'img') {
      _sanitizeUrlAttribute(node, 'src', allowDataImages: true);
    }
    for (final child in node.nodes.toList()) {
      _sanitizeNode(child);
    }
  }

  void _sanitizeClass(Element node) {
    final value = node.attributes['class'];
    if (value == null) return;
    final safe = value
        .split(RegExp(r'\s+'))
        .where(
          (name) =>
              name == 'footnote-marker' ||
              name == 'footnote' ||
              name.startsWith('language-'),
        )
        .toList();
    if (safe.isEmpty) {
      node.attributes.remove('class');
    } else {
      node.attributes['class'] = safe.join(' ');
    }
  }

  void _sanitizeUrlAttribute(
    Element element,
    String name, {
    required bool allowDataImages,
  }) {
    final value = element.attributes[name]?.trim();
    if (value == null || value.isEmpty) return;
    final lower = value.toLowerCase();
    final uri = Uri.tryParse(value);
    // כתובת ללא סכימה (`#frag`, `/abs`, `./rel`) בטוחה, אך לא כתובת
    // protocol-relative — `//host/x` תמשוך תוכן מרוחק בקורא לא-מקוון.
    final isSafe =
        (uri != null && !uri.hasScheme && !uri.hasAuthority) ||
        lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('file:') ||
        (allowDataImages && lower.startsWith('data:image/'));
    if (!isSafe) element.attributes.remove(name);
  }
}
