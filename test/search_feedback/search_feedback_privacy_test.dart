import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_events.dart';

void main() {
  final vectors = <String, String>{
    'שו"ת alice+study@example.co.il תורה': 'שו"ת <email> תורה',
    'a.b@one.org x_y@two.com': '<email> <email>',
    'שו"ת "C:\\Users\\John Smith\\שאלה אישית.txt" תורה': 'שו"ת <path> תורה',
    r"שו'ת 'C:\\Users\\John Smith\\שאלה אישית.txt' תורה": "שו'ת <path> תורה",
    'שו"ת "/home/שם פרטי/שאלה אישית.txt" תורה': 'שו"ת <path> תורה',
    'שו"ת "/Users/John O\'Connor/שאלה.txt" תורה': 'שו"ת <path> תורה',
    r'שו"ת "\\server\private share\שם אישי.txt" תורה': 'שו"ת <path> תורה',
    r'שו"ת C:\Users\John Smith\שאלה אישית.txt': 'שו"ת <path>',
    r'שו"ת \\server\private share\שם אישי.txt': 'שו"ת <path>',
    'שו"ת /home/שם פרטי/שאלה אישית.txt': 'שו"ת <path>',
    'שו"ת file:///home/שם/פרטי.txt': 'שו"ת <path>',
    'שו"ת D:/library/אישי.txt': 'שו"ת <path>',
    'שו"ת "/tmp/alice@example.com private.txt" תורה': 'שו"ת <path> תורה',
    'David דוד בראשית א/ב שמות ג/ד': 'David דוד בראשית א/ב שמות ג/ד',
    'שו"ת רמב"ם הלכה / סימן': 'שו"ת רמב"ם הלכה / סימן',
    'https://example.com/torah': 'https://example.com/torah',
    'family@abc': 'family@abc',
    "שו'ת '/home/O'Connor/private.txt' תורה": "שו'ת <path> תורה",
    r"שו'ת 'C:\Users\O'Connor\private.doc' תורה": "שו'ת <path> תורה",
    'שו"ת /home/John O\'Connor/אישי.txt': 'שו"ת <path>',
    'שו"ת file://server/private%20share/alice.txt': 'שו"ת <path>',
    'שו"ת FILE:///home/alice/private.txt': 'שו"ת <path>',
    'שו"ת file://localhost/home/alice/private.txt': 'שו"ת <path>',
    'תורה <path> <email>': 'תורה <path> <email>',
  };
  for (final entry in vectors.entries) {
    test('query privacy: ${entry.key}', () {
      final redacted = redactSearchFeedbackQuery(entry.key);
      expect(redacted, entry.value);
      expect(redactSearchFeedbackQuery(redacted), redacted);
      final raw = jsonEncode({
        'query': entry.key,
        'eventId': 'event_original',
        'searchSessionId': 'session_original',
        'result': {'passageText': entry.key},
      });
      final line = redactSearchFeedbackEventLine(raw);
      final event = jsonDecode(line) as Map;
      expect(event['query'], entry.value);
      expect(event['result'], {'passageText': entry.key});
      expect(event['eventId'], 'event_original');
      expect(event['searchSessionId'], 'session_original');
      expect(redactSearchFeedbackEventLine(line), line);
    });
  }
}
