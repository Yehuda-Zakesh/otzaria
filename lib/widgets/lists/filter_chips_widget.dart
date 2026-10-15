import 'package:flutter/material.dart';

/// A simple, reusable widget for displaying a list of selectable chips.
/// Replaces the complex filter_list library with a lightweight solution
/// using Flutter's built-in FilterChip widget. Selection state is kept by the
/// caller (Bloc/Cubit or setState), which rebuilds with the new selection.
///
/// Features:
/// - Multi-select mode
/// - Custom chip builder support
/// - Wrap alignment configuration
/// - Callback on selection change
class FilterChipsSelector<T> extends StatelessWidget {
  const FilterChipsSelector({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.labelBuilder,
    required this.onSelectionChanged,
    this.chipBuilder,
    this.wrapAlignment = WrapAlignment.start,
    this.wrapSpacing = 8.0,
    this.runSpacing = 4.0,
    this.padding = const EdgeInsets.all(8.0),
  });

  /// All available items to display as chips
  final List<T> items;

  /// Currently selected items
  final List<T> selectedItems;

  /// Function to get the display label for an item
  final String Function(T item) labelBuilder;

  /// Callback when selection changes
  final void Function(List<T> selectedItems) onSelectionChanged;

  /// Optional custom chip builder for full control over chip appearance
  final Widget Function(BuildContext context, T item, bool isSelected)?
  chipBuilder;

  /// Alignment of chips in the wrap
  final WrapAlignment wrapAlignment;

  /// Horizontal spacing between chips
  final double wrapSpacing;

  /// Vertical spacing between rows
  final double runSpacing;

  /// Padding around the entire widget
  final EdgeInsets padding;

  void _toggleSelection(T item) {
    final newSelection = List<T>.from(selectedItems);
    if (newSelection.contains(item)) {
      newSelection.remove(item);
    } else {
      newSelection.add(item);
    }
    onSelectionChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: wrapAlignment,
        spacing: wrapSpacing,
        runSpacing: runSpacing,
        children: items.map((item) {
          final isSelected = selectedItems.contains(item);

          if (chipBuilder != null) {
            return _SelectableChip(
              isSelected: isSelected,
              onTap: () => _toggleSelection(item),
              child: chipBuilder!(context, item, isSelected),
            );
          }

          return FilterChip(
            label: Text(
              labelBuilder(item),
            ),
            selected: isSelected,
            onSelected: (_) => _toggleSelection(item),
            selectedColor: Theme.of(context).colorScheme.secondary,
            labelStyle: TextStyle(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSecondary
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// שם ישן — הבורר כבר אינו מחזיק עותק בחירה פנימי.
typedef FilterChipsWidget<T> = FilterChipsSelector<T>;

/// עוטף צ׳יפ מותאם (`chipBuilder`) בהתנהגות של צ׳יפ אמיתי: מיקוד מקלדת,
/// הפעלה ב-Enter/רווח, וחשיפת מצב "נבחר" לקורא מסך.
class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // MergeSemantics מאחד את תווית הצ׳יפ עם דגלי הבחירה לצומת אחד, אחרת קורא
    // המסך מקריא "נבחר" ואת הטקסט כשני פריטים נפרדים.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: child,
        ),
      ),
    );
  }
}
