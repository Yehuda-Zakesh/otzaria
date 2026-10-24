import 'package:flutter/material.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_times_panel.dart';

enum CalendarSidePanelView { times, events }

class CalendarSidePanel extends StatelessWidget {
  final CalendarSidePanelView activeView;
  final CalendarTimesPanel timesPanel;
  final CalendarEventsPanel eventsPanel;

  const CalendarSidePanel({
    super.key,
    required this.activeView,
    required this.timesPanel,
    required this.eventsPanel,
  });

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: activeView == CalendarSidePanelView.events ? 1 : 0,
      children: [
        timesPanel,
        eventsPanel,
      ],
    );
  }
}
