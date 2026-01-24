import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/task_model.dart';

class CalendarModal extends StatefulWidget {
  final List<Task> tasks;
  final VoidCallback onClose;

  const CalendarModal({super.key, required this.tasks, required this.onClose});

  @override
  State<CalendarModal> createState() => _CalendarModalState();
}

class _CalendarModalState extends State<CalendarModal> {
  int _viewMode = 0; // 0 = Calendar, 1 = Timeline
  late PageController _pageController;
  static const int _initialPage = 1000;
  
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDate; 

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
void didUpdateWidget(covariant CalendarModal oldWidget) {
  super.didUpdateWidget(oldWidget);
  // This triggers a refresh inside the modal if the tasks list changes 
  // (even if the dialog stays open)
  if (widget.tasks != oldWidget.tasks) {
    setState(() {}); 
  }
}

  // Helper to snap back to the current month
  void _jumpToToday() {
    _pageController.animateToPage(
      _initialPage, 
      duration: const Duration(milliseconds: 600), 
      curve: Curves.elasticOut
    );
    setState(() {
      _focusedDay = DateTime.now();
      _selectedDate = DateTime.now();
    });
  }

  bool _isTaskOnDate(Task task, DateTime date) {
    if (task.exactDate == null) return false;
    return task.exactDate!.year == date.year &&
           task.exactDate!.month == date.month &&
           task.exactDate!.day == date.day;
  }

  void _closeWithUnfocus() {
    FocusScope.of(context).unfocus();
    widget.onClose();
  }

  void _jumpMonth(int offset) {
    _pageController.animateToPage(
      _pageController.page!.round() + offset, 
      duration: const Duration(milliseconds: 300), 
      curve: Curves.easeInOut
    );
  }

  void _onPageChanged(int index) {
    int diff = index - _initialPage;
    setState(() {
      DateTime now = DateTime.now();
      _focusedDay = DateTime(now.year, now.month + diff, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _closeWithUnfocus,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withValues(alpha: 0.2)),
            ),
          ),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.80, 
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? Colors.black.withValues(alpha: 0.85) 
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 10))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // --- HEADER ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_viewMode == 0) ...[
                             IconButton(
                              icon: Icon(Icons.chevron_left, color: isDarkMode ? Colors.white : Colors.black87),
                              onPressed: () => _jumpMonth(-1),
                            ),
                            GestureDetector(
                              onTap: _jumpToToday, // Tap title to reset
                              child: Text(
                                "${_getMonthName(_focusedDay.month)} ${_focusedDay.year}",
                                style: TextStyle(
                                  fontSize: 20, 
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode ? Colors.white : Colors.black87
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.chevron_right, color: isDarkMode ? Colors.white : Colors.black87),
                              onPressed: () => _jumpMonth(1),
                            ),
                          ] else 
                              Text(
                               "Timeline",
                               style: TextStyle(
                                 fontSize: 22, 
                                 fontWeight: FontWeight.bold,
                                 color: isDarkMode ? Colors.white : Colors.black87
                               ),
                              ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),

                      // --- TOGGLE PILL ---
                      Container(
                        height: 38,
                        width: double.infinity, 
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildToggleButton(0, "Calendar", isDarkMode)),
                            const SizedBox(width: 4),
                            Expanded(child: _buildToggleButton(1, "Timeline", isDarkMode)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- CONTENT ---
                      _viewMode == 0 
                          ? _buildSwipeableCalendar(isDarkMode)
                          : _buildTimelineView(isDarkMode),

                      const SizedBox(height: 20),
                      
                      // --- TODAY BUTTON (Only shown if scrolled away) ---
                      if (_viewMode == 0 && (_focusedDay.month != DateTime.now().month || _focusedDay.year != DateTime.now().year))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextButton.icon(
                            onPressed: _jumpToToday,
                            icon: const Icon(Icons.today, size: 18),
                            label: const Text("Back to Today"),
                            style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                          ),
                        ),

                      // --- CLOSE BUTTON ---
                      GestureDetector(
                        onTap: _closeWithUnfocus,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text("Close", style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white70 : Colors.black54)),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildToggleButton(int mode, String label, bool isDark) {
    bool isActive = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? (isDark ? Colors.white : Colors.indigo) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white54 : Colors.black45),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeableCalendar(bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ["S", "M", "T", "W", "T", "F", "S"].map((d) => 
            Text(d, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.bold))
          ).toList(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 240, 
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              int diff = index - _initialPage;
              DateTime now = DateTime.now();
              DateTime monthTime = DateTime(now.year, now.month + diff, 1);
              return _buildMonthGrid(monthTime, isDark);
            },
          ),
        ),
        const Divider(),
        _selectedDate == null 
            ? Padding(
                padding: const EdgeInsets.all(20), 
                child: Text("Select a date", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))
              )
            : _buildSelectedDayTasks(isDark),
      ],
    );
  }

  Widget _buildMonthGrid(DateTime monthTime, bool isDark) {
    final daysInMonth = DateUtils.getDaysInMonth(monthTime.year, monthTime.month);
    final firstDayOffset = DateTime(monthTime.year, monthTime.month, 1).weekday % 7;
    
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(), 
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: daysInMonth + firstDayOffset,
      itemBuilder: (context, index) {
        if (index < firstDayOffset) return const SizedBox.shrink();
        
        final dayNum = index - firstDayOffset + 1;
        final currentDayDate = DateTime(monthTime.year, monthTime.month, dayNum);
        bool hasTask = widget.tasks.any((t) => _isTaskOnDate(t, currentDayDate));
        bool isSelected = _selectedDate != null && 
                          _selectedDate!.day == dayNum && 
                          _selectedDate!.month == monthTime.month &&
                          _selectedDate!.year == monthTime.year;

        return GestureDetector(
          onTap: () => setState(() => _selectedDate = currentDayDate),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected 
                  ? Colors.indigo 
                  : (hasTask ? Colors.indigo.withValues(alpha: 0.15) : Colors.transparent),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$dayNum",
                  style: TextStyle(
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: (isSelected || hasTask) ? FontWeight.bold : FontWeight.normal
                  ),
                ),
                if (hasTask && !isSelected)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 4, height: 4,
                    decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedDayTasks(bool isDark) {
    final dayTasks = widget.tasks.where((t) => _isTaskOnDate(t, _selectedDate!)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dayTasks.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Clear day!")))
        else
          ...dayTasks.map((task) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      task.isCompleted ? Icons.check_circle : Icons.circle_outlined, 
                      size: 20, 
                      color: task.isCompleted ? Colors.green : Colors.indigo
                    ),
                    const SizedBox(width: 12),
                    Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        task.title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
      // --- THE PRECISION LAYER ---
      // We check for exactDate and hasSpecificTime to avoid "Ignore me" strings
      if (task.exactDate != null && task.hasSpecificTime)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              // Subtle AI indicator if Gemini helped with this timing
              if (task.isAiGenerated)
                const Icon(Icons.auto_awesome, size: 10, color: Colors.indigoAccent),
              if (task.isAiGenerated) const SizedBox(width: 4),
              Text(
                TimeOfDay.fromDateTime(task.exactDate!).format(context),
                style: TextStyle(
                  fontSize: 11, 
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
    ],
  ),
)
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildTimelineView(bool isDark) {
    // Only show incomplete tasks with dates in the Timeline
    final datedTasks = widget.tasks.where((t) => t.exactDate != null && !t.isCompleted).toList();
    datedTasks.sort((a, b) => a.exactDate!.compareTo(b.exactDate!));

    if (datedTasks.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No upcoming deadlines")));
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: datedTasks.length,
      itemBuilder: (context, index) {
        final task = datedTasks[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.indigo),
                    const SizedBox(height: 4),
                    Text(
                      "${_getMonthName(task.exactDate!.month)} ${task.exactDate!.day}", 
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        task.title, 
        maxLines: 1, 
        overflow: TextOverflow.ellipsis, 
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
      ),
      // 🔥 THE EDIT: Using logic-based confirmation instead of string-splitting
      Text(
        task.hasSpecificTime ? "Scheduled for this day" : "All day task", 
        style: const TextStyle(fontSize: 12, color: Colors.grey)
      ),
    ],
  ),
),
            ],
          ),
        );
      },
    );
  }

  String _getMonthName(int month) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[(month - 1) % 12];
  }
}