import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../utils/screen_adapter.dart';
import '../../utils/animation_config.dart';
import '../detail/detail_screen.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  final bool embedded;

  CalendarScreen({super.key, this.embedded = false});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<CalendarEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  void _loadEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    _events = {
      today.subtract(const Duration(days: 2)): [
        CalendarEvent(
          title: '�Ǽʴ�Խ',
          tmdbId: 157336,
          posterPath: '/rAiYTfKGqDCRIIqo664sY9XZIvQ.jpg',
          type: EventType.watched,
        ),
      ],
      today.subtract(const Duration(days: 1)): [
        CalendarEvent(
          title: '���οռ�',
          tmdbId: 27205,
          posterPath: '/9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg',
          type: EventType.watched,
        ),
        CalendarEvent(
          title: 'ɳ��2',
          tmdbId: 693134,
          posterPath: '/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg',
          type: EventType.airing,
        ),
      ],
      today: [
        CalendarEvent(
          title: '������è4',
          tmdbId: 1011985,
          posterPath: '/1XDDXPXGiI8id753300jO33wvRn.jpg',
          type: EventType.released,
        ),
      ],
      today.add(const Duration(days: 1)): [
        CalendarEvent(
          title: '����������',
          tmdbId: 533535,
          posterPath: '/7WUHnWGXyDvNq3dMIPI3Y4P4W2F.jpg',
          type: EventType.airing,
        ),
      ],
      today.add(const Duration(days: 3)): [
        CalendarEvent(
          title: 'ͷ�����2',
          tmdbId: 775567,
          posterPath: '/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
          type: EventType.upcoming,
        ),
      ],
    };
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    
    if (widget.embedded) {
      return Column(
        children: [
          SizedBox(height: 16),
          _buildCalendar(),
          SizedBox(height: 8),
          Expanded(
            child: _buildEventList(adapter),
          ),
        ],
      );
    }
    
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(adapter),
            _buildCalendar(),
            SizedBox(height: 8),
            Expanded(
              child: _buildEventList(adapter),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ScreenAdapter adapter) {
    return Padding(
      padding: EdgeInsets.all(adapter.contentPadding),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: context.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 16),
          Text(
            '�ۿ�����',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TableCalendar<CalendarEvent>(
        firstDay: DateTime.utc(2024, 1, 1),
        lastDay: DateTime.utc(2026, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        eventLoader: _getEventsForDay,
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onFormatChanged: (format) {
          setState(() => _calendarFormat = format);
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
        },
        calendarStyle: CalendarStyle(
          todayDecoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
            color: AppTheme.secondary,
            shape: BoxShape.circle,
          ),
          defaultTextStyle: TextStyle(color: context.textPrimary),
          weekendTextStyle: TextStyle(color: context.textPrimary.withValues(alpha:0.7)),
          outsideTextStyle: TextStyle(color: context.textPrimary.withValues(alpha:0.3)),
          disabledTextStyle: TextStyle(color: context.textPrimary.withValues(alpha:0.2)),
          todayTextStyle: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
          selectedTextStyle: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          formatButtonDecoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          formatButtonTextStyle: TextStyle(color: AppTheme.primary),
          titleTextStyle: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          leftChevronIcon: Icon(Icons.chevron_left, color: context.textPrimary),
          rightChevronIcon: Icon(Icons.chevron_right, color: context.textPrimary),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(color: context.textPrimary.withValues(alpha:0.6)),
          weekendStyle: TextStyle(color: context.textPrimary.withValues(alpha:0.4)),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return null;
            return Positioned(
              bottom: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: events.take(3).map((event) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _getEventColor(event.type),
                      shape: BoxShape.circle,
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getEventColor(EventType type) {
    switch (type) {
      case EventType.watched:
        return AppTheme.primary;
      case EventType.airing:
        return AppTheme.accent;
      case EventType.released:
        return Colors.green;
      case EventType.upcoming:
        return AppTheme.secondary;
    }
  }

  Widget _buildEventList(ScreenAdapter adapter) {
    final events = _getEventsForDay(_selectedDay!);
    
    return events.isEmpty
        ? _buildEmptyState()
        : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _buildEventCard(event, adapter);
            },
          );
  }

  Widget _buildEventCard(CalendarEvent event, ScreenAdapter adapter) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          AppAnimations.buildPageRoute(
            page: DetailScreen.fromTMDB(TMDBMovie(id: event.tmdbId, title: event.title)),
            type: PageTransitionType.fade,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getEventColor(event.type).withValues(alpha:0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: event.posterPath != null
                  ? CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w200${event.posterPath}',
                      width: 70,
                      height: 100,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 70,
                      height: 100,
                      color: context.textPrimary.withValues(alpha:0.1),
                      child: Icon(Icons.movie, color: context.textPrimary),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getEventColor(event.type).withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getEventTypeText(event.type),
                        style: TextStyle(
                          color: _getEventColor(event.type),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  String _getEventTypeText(EventType type) {
    switch (type) {
      case EventType.watched:
        return '�ѹۿ�';
      case EventType.airing:
        return '���ڲ���';
      case EventType.released:
        return '����ӳ';
      case EventType.upcoming:
        return '������ӳ';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 56,
            color: context.textPrimary.withValues(alpha:0.2),
          ),
          SizedBox(height: 16),
          Text(
            '��һ��û�а���',
            style: TextStyle(
              color: context.textPrimary.withValues(alpha:0.4),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

enum EventType {
  watched,
  airing,
  released,
  upcoming,
}

class CalendarEvent {
  final String title;
  final int tmdbId;
  final String? posterPath;
  final EventType type;

  CalendarEvent({
    required this.title,
    required this.tmdbId,
    this.posterPath,
    required this.type,
  });
}

