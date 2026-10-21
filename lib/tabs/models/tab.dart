/* this is a representation of the tabs that could be open in the app.
a tab is either a pdf book or a text book, or a full text search window*/

import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';

abstract class OpenedTab {
  String title;
  bool isPinned;
  final String? dedupeKey;
  OpenedTab(this.title, {this.isPinned = false, this.dedupeKey});

  /// Called when the tab is being disposed.
  /// Override this method to perform cleanup.
  void dispose() {}

  /// מחזיר עותק עצמאי עם בקרים ומחזור חיים נפרדים.
  OpenedTab clone();

  factory OpenedTab.from(OpenedTab tab) => tab.clone();

  factory OpenedTab.fromBook(
    Book book,
    int index, {
    ReadingAnchor? initialReadingAnchor,
    String searchText = '',
    String highlightText = '',
    int? permanentHighlightLine,
    List<String>? commentators,
    bool openLeftPane = false,
    bool isPinned = false,
    bool? showPageShapeView,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
    int? pinpointHighlightSectionIndex,
    String? dedupeKey,
    ExternalBookMatches? externalMatches,
  }) {
    if (book is PdfBook) {
      return PdfBookTab(
        book: book,
        pageNumber: index,
        openLeftPane: openLeftPane,
        searchText: searchText,
        isPinned: isPinned,
        requiresStableLayout: requiresStableLayout,
        dedupeKey: dedupeKey,
        externalMatches: externalMatches,
      );
    } else if (book is ConvertibleDocumentBook) {
      // ספרי מסמך רצים דרך זרימת TextBook — העטיפה דרך toTextBook משמרת
      // id/categoryId/externalLibraryId שדרושים ל-LibraryProviderManager.
      return TextBookTab(
        book: book.toTextBook(),
        index: index,
        initialReadingAnchor: initialReadingAnchor,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    } else if (book is TextBook) {
      return TextBookTab(
        book: book,
        index: index,
        initialReadingAnchor: initialReadingAnchor,
        searchText: searchText,
        highlightText: highlightText,
        permanentHighlightLine: permanentHighlightLine,
        commentators: commentators,
        openLeftPane: openLeftPane,
        isPinned: isPinned,
        showPageShapeView: showPageShapeView,
        pinpointHighlight: pinpointHighlight,
        pinpointHighlightSectionIndex: pinpointHighlightSectionIndex,
        dedupeKey: dedupeKey,
      );
    }
    throw UnsupportedError("Unsupported book type: ${book.runtimeType}");
  }

  /// המפענח **היחיד** של טאב שמור.
  ///
  /// ⚠️ קודם לכן הוא הכיר חמישה טיפוסים בלבד, ושלושה קוראים עקפו אותו עם
  /// מפענחים מקבילים משלהם (`TabsRepository`, `Workspace.fromJson`,
  /// `decodeCombinedTab`). התוצאה: כרטיסיית מפרשים לא הייתה ניתנת להעברה
  /// בין חלונות — `canTransfer` חסם אותה — בעוד אותה כרטיסיה בדיוק כן
  /// נטענה מהדיסק, כי המסלול הזה עבר במפענח אחר. שכפול של טבלת טיפוסים
  /// מתיישן בכיוונים שונים, וזו בדיוק הדרך שבה זה קרה.
  ///
  /// טיפוס לא מוכר זורק ולא נופל בשקט ל-[SearchingTab]: נפילה כזו יצרה טאב
  /// רפאים בשם הכלי/הספר בכל ירידת גרסה, וההצפה נשמרה חזרה לדיסק. הקוראים
  /// (`TabsRepository.loadTabs`, `Workspace.fromJson`) מדלגים על טאב שנכשל.
  factory OpenedTab.fromJson(Map<String, dynamic> json) {
    String type = json['type'];
    if (type == 'TextBookTab') {
      return TextBookTab.fromJson(json);
    } else if (type == 'PdfBookTab') {
      return PdfBookTab.fromJson(json);
    } else if (type == 'CombinedTab') {
      return decodeCombinedTab(json);
    } else if (type == 'ToolTab') {
      return ToolTab.fromJson(json);
    } else if (type == 'SearchingTabWindow' || type == 'SearchingTab') {
      return SearchingTab.fromJson(json);
    } else if (type == 'SemanticSearchTab') {
      return SemanticSearchTab.fromJson(json);
    } else if (type == 'CommentatorsTab') {
      return CommentatorsTab.fromJson(json);
    } else if (type == 'PdfCommentatorsTab') {
      return PdfCommentatorsTab.fromJson(json);
    }
    throw FormatException('Unknown tab type: $type');
  }
  Map<String, dynamic> toJson();
}

/// מחזיק טאב מקור חי עד שכל הכרטיסיות התלויות בו נסגרות.
class SourceTabOwnership {
  SourceTabOwnership(this.sourceTab);

  final OpenedTab sourceTab;
  int _leases = 0;

  void retain() {
    _leases++;
  }

  void release() {
    if (_leases == 0 || --_leases != 0) return;
    sourceTab.dispose();
  }
}
