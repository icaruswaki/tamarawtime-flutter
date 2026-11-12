import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'planner.dart';
import 'responsive.dart';

class ClassCalendar extends StatefulWidget {
  const ClassCalendar({
    super.key,
    required this.classes,
    required this.selected,
    required this.onSelected,
    required this.classTile,
    this.classTileWithDate,
    required this.onAdd,
  });
  final List<Map<String, dynamic>> classes;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final Widget Function(Map<String, dynamic>) classTile;
  final Widget Function(Map<String, dynamic>, DateTime)? classTileWithDate;
  final VoidCallback onAdd;
  @override
  State<ClassCalendar> createState() => _ClassCalendarState();
}

class _ClassCalendarState extends State<ClassCalendar> {
  late DateTime focused = widget.selected;
  List<Map<String, dynamic>> events(DateTime date) =>
      classesOnDate(widget.classes, date);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = AppLayout.textScale(context);
    final selectedClasses = events(widget.selected);
    final today = manilaNow();
    final reduced = MediaQuery.disableAnimationsOf(context);
    final calendar = Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TableCalendar<Map<String, dynamic>>(
          key: const ValueKey('class-calendar'),
          firstDay: DateTime.utc(2000),
          lastDay: DateTime.utc(2100, 12, 31),
          focusedDay: focused,
          currentDay: today,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          rowHeight: 48 * scale.clamp(1, 1.6),
          daysOfWeekHeight: 26 * scale,
          eventLoader: events,
          selectedDayPredicate: (day) => isSameDay(day, widget.selected),
          onDaySelected: (selected, focus) {
            setState(() => focused = focus);
            widget.onSelected(selected);
          },
          onPageChanged: (day) => focused = day,
          pageAnimationEnabled: !reduced,
          pageAnimationDuration: reduced
              ? Duration.zero
              : const Duration(milliseconds: 220),
          formatAnimationDuration: reduced
              ? Duration.zero
              : const Duration(milliseconds: 180),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            leftChevronPadding: EdgeInsets.all(12),
            rightChevronPadding: EdgeInsets.all(12),
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(color: colors.onPrimaryContainer),
            selectedDecoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
              color: colors.onPrimary,
              fontWeight: FontWeight.bold,
            ),
            markerDecoration: BoxDecoration(
              color: colors.tertiary,
              shape: BoxShape.circle,
            ),
            markersMaxCount: 3,
            cellMargin: const EdgeInsets.all(3),
          ),
          calendarBuilders: CalendarBuilders(
            dowBuilder: (context, day) => Center(
              child: Text(
                days[day.weekday % 7].substring(0, 1),
                semanticsLabel: days[day.weekday % 7],
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
    );
    final schedule = Column(
      key: ValueKey(
        'selected-day-${widget.selected.year}-${widget.selected.month}-${widget.selected.day}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${days[widget.selected.weekday % 7]}, '
          '${widget.selected.month}/${widget.selected.day}/${widget.selected.year}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${selectedClasses.length} ${selectedClasses.length == 1 ? 'class' : 'classes'} planned',
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('Classes repeat every week on their selected days.'),
        const SizedBox(height: 12),
        if (selectedClasses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No classes on this day. Add a class to plan ahead.'),
            ),
          ),
        ...selectedClasses.map(
          (entry) =>
              widget.classTileWithDate?.call(entry, widget.selected) ??
              widget.classTile(entry),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add class for this day'),
        ),
      ],
    );
    final selectedSchedule = AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      child: schedule,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Class Schedule',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Text('Select a date to see your weekly classes.'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) =>
              AppLayout.columns(box.maxWidth, textScale: scale)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: calendar),
                    const SizedBox(width: 20),
                    Expanded(child: selectedSchedule),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    calendar,
                    const SizedBox(height: 20),
                    selectedSchedule,
                  ],
                ),
        ),
      ],
    );
  }
}
