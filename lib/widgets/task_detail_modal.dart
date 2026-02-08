import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import '../services/settings_service.dart';

class TaskDetailModal extends StatefulWidget {
  final Task task;
  final VoidCallback onClose;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final Function(String subtaskId) onSubtaskToggle;
  final Function(Task updatedTask)? onUpdate;
  final bool isPreview;
  final VoidCallback? onConfirm;
  
  
  

  const TaskDetailModal({
    super.key,
    required this.task,
    required this.onClose,
    required this.onToggle,
    required this.onDelete,
    required this.onSubtaskToggle,
    this.onUpdate,
    this.isPreview = false, 
    this.onConfirm,
  });

  @override
  State<TaskDetailModal> createState() => _TaskDetailModalState();
}

class _TaskDetailModalState extends State<TaskDetailModal> {
  bool _isEditing = false;
  late TextEditingController _titleController;
  late TextEditingController _descController;
  final TextEditingController _newSubtaskController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController(); // 🔥 Track the slider position
  final Map<String, TextEditingController> _subtaskControllers = {};
  late List<SubTask> _localSubtasks;
  final List<String> _categories = ['General', 'Work', 'Personal', 'Shopping'];

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  late String _selectedCategory; 
  late String _selectedPriority;
  bool _showScrollArrow = true;
  double _getCategoryValue() => _categories.indexOf(_selectedCategory).toDouble();

  @override
  void initState() {
    super.initState();
    _isEditing = false; 
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(text: widget.task.description);
    _localSubtasks = List.from(widget.task.subtasks);
    _selectedCategory = widget.task.category;
    _selectedPriority = widget.task.priority;
    _selectedDate = widget.task.exactDate;
    
    if (widget.task.hasSpecificTime && widget.task.exactDate != null) {
      _selectedTime = TimeOfDay.fromDateTime(widget.task.exactDate!);
    }

    _scrollController.addListener(() {
      if (_scrollController.hasClients && _scrollController.offset > 50 && _showScrollArrow) {
        setState(() => _showScrollArrow = false);
      } else if (_scrollController.hasClients && _scrollController.offset <= 50 && !_showScrollArrow) {
        setState(() => _showScrollArrow = true);
      }
    });
  }

@override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _newSubtaskController.dispose();
    _scrollController.dispose();
    
    // 🔥 ADD THIS LINE HERE
    _categoryScrollController.dispose(); 
    
    for (var c in _subtaskControllers.values) { c.dispose(); }
    super.dispose();
  }

  void _saveChanges() {
    DateTime? finalExactDate;
    bool hasTime = false;
    String displayDateString = "";

    // 🔥 DATA SYNC FIX: Reconcile date and time for the Task Card
    if (_selectedDate != null) {
      if (_selectedTime != null) {
        finalExactDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
        hasTime = true;
        displayDateString = "${_selectedDate!.day}/${_selectedDate!.month} ${_selectedTime!.format(context)}";
      } else {
        finalExactDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        displayDateString = "${_selectedDate!.day}/${_selectedDate!.month}";
      }
    }

    final updatedTask = widget.task.copyWith(
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      category: _selectedCategory,
      priority: _selectedPriority,
      exactDate: finalExactDate,
      dueDate: displayDateString.isEmpty ? widget.task.dueDate : displayDateString,
      hasSpecificTime: hasTime,
      subtasks: _localSubtasks.map((s) {
        if (_subtaskControllers.containsKey(s.id)) {
          return s.copyWith(title: _subtaskControllers[s.id]!.text.trim());
        }
        return s;
      }).toList(),
    );

    if (widget.onUpdate != null) widget.onUpdate!(updatedTask);
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final isDark = settings.isDarkMode;
    final themeColor = _getThemeColor(settings.themeColor);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.92,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: themeColor.withValues(alpha: 0.12), width: 1.5),
            ),
            // 🔥 THE NEW CLEAN ENGINE ROOM
child: _isEditing 
    ? _buildMicromanageLayout(themeColor, isDark) 
    : _buildStandardLayout(themeColor, isDark),
          ),
        ),
      ),
    );
  }

  // --- GLASS COMPONENTS ---

 Widget _buildHeader(Color theme, bool isDark) {
  return Container(
    padding: const EdgeInsets.fromLTRB(24, 24, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildGlassTag(_selectedCategory.toUpperCase(), isDark ? Colors.white60 : Colors.black54, isDark),
                const SizedBox(width: 10),
                _buildGlassTag(_selectedPriority.toUpperCase(), _selectedPriority == 'High' ? Colors.redAccent : theme, isDark),
              ],
            ),
            // Glass Close Button
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    shape: BoxShape.circle,
                    border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: IconButton(
                    onPressed: widget.onClose, 
                    icon: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54)
                  ),
                ),
              ),
            ),
          ],
        ),
        
        // 🔥 THE CONTENT AREA (Conditional Editing UI)
        if (_isEditing) ...[
          const SizedBox(height: 24),
          // 1. NEUTRAL PRIORITY SELECTOR (Thin borders, no heavy fill)
          _buildBiggerSelector(
            title: "PRIORITY", 
            options: ['Low', 'Medium', 'High'], 
            current: _selectedPriority, 
            onSelect: (v) => setState(() => _selectedPriority = v), 
            theme: theme, 
            isDark: isDark,
            isSlider: false, // Standard row for Priority
          ),
          
          const SizedBox(height: 20),
          // 2. TACTILE CATEGORY SLIDER (Physical line + Round thumb)
          _buildBiggerSelector(
            title: "CATEGORY", 
            options: _categories, 
            current: _selectedCategory, 
            onSelect: (v) => setState(() => _selectedCategory = v), 
            theme: theme, 
            isDark: isDark,
            isSlider: true, // Physical slider for Categories
          ),
        ]
      ],
    ),
  );
}
Widget _buildTactileSlider(Color theme, bool isDark) {
  return Column(
    children: [
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          activeTrackColor: theme.withValues(alpha: 0.3),
          inactiveTrackColor: Colors.grey.withValues(alpha: 0.1),
          thumbColor: isDark ? Colors.white : theme,
          overlayColor: theme.withValues(alpha: 0.1),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 4),
          tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
          activeTickMarkColor: theme,
          inactiveTickMarkColor: Colors.grey,
        ),
        child: Slider(
          value: _getCategoryValue(),
          min: 0,
          max: 3,
          divisions: 3,
          onChanged: (val) {
            setState(() => _selectedCategory = _categories[val.toInt()]);
          },
        ),
      ),
      const SizedBox(height: 4), // Added space for the larger text
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14), // Balanced padding
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _categories.map((c) {
            final isSelected = _selectedCategory == c;
            return Text(
              c.toUpperCase(), 
              style: TextStyle(
                fontSize: 12, // 🔥 INCREASED from 8 to 12
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                color: isSelected 
                    ? (isDark ? Colors.white : theme) 
                    : Colors.grey[400],
                letterSpacing: 1.1,
              ),
            );
          }).toList(),
        ),
      ),
    ],
  );
}
  Widget _buildGlassMetadataRow(Color theme, bool isDark) {
    final dateText = _selectedDate == null ? "No Date" : "${_selectedDate!.day}/${_selectedDate!.month}";
    final timeText = _selectedTime == null ? "No Time" : _selectedTime!.format(context);

    return Row(
      children: [
        Expanded(child: _buildLargeGlassButton(icon: Icons.calendar_today_rounded, label: dateText, onTap: _isEditing ? _pickDate : null, isDark: isDark, theme: theme)),
        const SizedBox(width: 12),
        Expanded(child: _buildLargeGlassButton(icon: Icons.access_time_filled_rounded, label: timeText, onTap: _isEditing ? _pickTime : null, isDark: isDark, theme: theme)),
      ],
    );
  }

  Widget _buildLargeGlassButton({required IconData icon, required String label, required VoidCallback? onTap, required bool isDark, required Color theme}) {
  bool isActive = onTap != null;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // 🔥 REMOVED SOLID THEME COLOR: Now just a light grey/white glass tint
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? Colors.grey.withValues(alpha: 0.15) : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isActive ? theme.withValues(alpha: 0.7) : Colors.grey),
          const SizedBox(width: 10),
          Text(
            label, 
            style: TextStyle(
              fontSize: 13, 
              fontWeight: FontWeight.bold, 
              color: isActive ? (isDark ? Colors.white : Colors.black87) : Colors.grey
            )
          ),
        ],
      ),
    ),
  );
}

  
  Widget _buildFooter(Color theme, bool isDark) {
  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 🛠️ MICROMANAGE / SAVE BUTTON
        _buildActionGlassButton(
          onTap: () {
            if (_isEditing) {
              _saveChanges();
            } else {
              setState(() => _isEditing = true);
            }
          },
          isDark: isDark,
          child: Row(
            children: [
              Icon(
                _isEditing ? Icons.check_circle_outline : Icons.auto_fix_high_outlined,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 10),
              Text(
                _isEditing ? "SAVE UPDATES" : "MICROMANAGE",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // 🚀 ACTION SIDE (ADD or DELETE)
        widget.isPreview
            ? _buildActionGlassButton(
                onTap: widget.onConfirm!,
                isDark: isDark,
                isHighlight: true,
                child: const Text(
                  "ADD TASK",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              )
            : ClipRRect(
                // 🔥 UPGRADED: Glassmorphic Delete Button
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
                    ),
                    child: IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
      ],
    ),
  );
}

  Widget _buildActionGlassButton({required VoidCallback onTap, required Widget child, required bool isDark, bool isHighlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isHighlight 
                ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1))
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // --- SUB-ELEMENTS (Logic Preserved) ---

  Widget _buildGlassTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.2)),
    );
  }

 Widget _buildTitle() {
  return _isEditing
      ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: ShapeDecoration(
            // 🔥 FIX: Move 'side' inside StadiumBorder and remove 'const'
            shape: StadiumBorder(
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white.withValues(alpha: 0.05) 
                : Colors.black.withValues(alpha: 0.03),
          ),
          child: TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            maxLines: 1,
            decoration: const InputDecoration(
              hintText: "Enter Goal...",
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        )
      : Text(
          widget.task.title, 
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.2)
        );
}

  Widget _buildNotes(bool isDark) {
    if (!_isEditing && widget.task.description.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("CONTEXT", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 1.2)),
        const SizedBox(height: 8),
        _isEditing 
          ? TextField(controller: _descController, maxLines: null, decoration: const InputDecoration(border: InputBorder.none, hintText: "Add intel..."))
          : Text(widget.task.description, style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.white70 : Colors.black87)),
      ],
    );
  }
  Widget _buildBiggerSelector({
  required String title,
  required List<String> options,
  required String current,
  required Function(String) onSelect,
  required Color theme,
  required bool isDark,
  bool isSlider = false, // 🔥 NEW FLAG
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey[500], letterSpacing: 1.5)),
      const SizedBox(height: 12),
      if (isSlider)
        _buildTactileSlider(theme, isDark) // 🔥 CUSTOM SLIDER
      else
        Row(
          children: options.map((opt) {
            bool isSel = current == opt;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSel ? theme.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    opt, 
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel ? (isDark ? Colors.white : Colors.black87) : Colors.grey
                    )
                  ),
                ),
              ),
            );
          }).toList(),
        ),
    ],
  );
}
// --- 🧊 STANDARD MODE: Fixed Header/Footer ---
Widget _buildStandardLayout(Color themeColor, bool isDark) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildHeader(themeColor, isDark),
      Flexible(
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildBodyContent(themeColor, isDark),
            ),
            if (_showScrollArrow) 
              Positioned(bottom: 10, left: 0, right: 0, child: Icon(Icons.keyboard_arrow_down_rounded, color: themeColor.withValues(alpha: 0.3), size: 30)),
          ],
        ),
      ),
      _buildFooter(themeColor, isDark),
    ],
  );
}

// --- 🔥 MICROMANAGE MODE: Everything Scrolls Together ---
Widget _buildMicromanageLayout(Color themeColor, bool isDark) {
  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(themeColor, isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildBodyContent(themeColor, isDark),
        ),
        _buildFooter(themeColor, isDark),
        // Ensure the Save button can scroll above the keyboard
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 0),
      ],
    ),
  );
}

// --- 🥩 THE CONTENT: Reusable body logic ---
Widget _buildBodyContent(Color themeColor, bool isDark) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      _buildTitle(),
      const SizedBox(height: 18),
      _buildGlassMetadataRow(themeColor, isDark),
      const SizedBox(height: 24),
      _buildNotes(isDark),
      const SizedBox(height: 28),
      _buildRoadmap(themeColor, isDark),
      const SizedBox(height: 30),
    ],
  );
}

  Widget _buildRoadmap(Color theme, bool isDark) {
    if (!_isEditing && _localSubtasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("ROADMAP", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: theme.withValues(alpha: 0.6), letterSpacing: 1.5)),
        const SizedBox(height: 12),
        ..._localSubtasks.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              if (_isEditing)
                GestureDetector(onTap: () => setState(() => _localSubtasks.removeAt(e.key)), child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 22))
              else
                SizedBox(width: 24, height: 24, child: Checkbox(value: e.value.isCompleted, onChanged: (_) => widget.onSubtaskToggle(e.value.id), activeColor: theme, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))),
              const SizedBox(width: 14),
              Expanded(
                child: _isEditing
                  ? TextField(controller: _subtaskControllers.putIfAbsent(e.value.id, () => TextEditingController(text: e.value.title)), style: const TextStyle(fontSize: 15), maxLines: null, decoration: const InputDecoration(isDense: true, border: InputBorder.none))
                  : Text(e.value.title, style: TextStyle(fontSize: 15, color: e.value.isCompleted ? Colors.grey : (isDark ? Colors.white : Colors.black87))),
              ),
            ],
          ),
        )),
        if (_isEditing) TextField(controller: _newSubtaskController, decoration: InputDecoration(hintText: "Add milestone...", prefixIcon: Icon(Icons.add_rounded, size: 20, color: theme), border: InputBorder.none), onSubmitted: (v) { if(v.isNotEmpty) { setState(() { _localSubtasks.add(SubTask(id: const Uuid().v4(), title: v, isCompleted: false)); _newSubtaskController.clear(); }); } }),
      ],
    );
  }

  Color _getThemeColor(String theme) {
    switch (theme.toLowerCase()) {
      case 'emerald': return const Color(0xFF047857);
      case 'rose':    return const Color(0xFFBE123C);
      case 'cyan':    return const Color(0xFF0E7490);
      default:        return const Color(0xFF4338CA);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _selectedDate ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime(2030));
    if (d != null) setState(() => _selectedDate = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _selectedTime ?? TimeOfDay.now());
    if (t != null) setState(() => _selectedTime = t);
  }
}