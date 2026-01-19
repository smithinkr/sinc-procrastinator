import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/task_model.dart';

class TaskDetailModal extends StatefulWidget {
  final Task task;
  final VoidCallback onClose;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final Function(String subtaskId) onSubtaskToggle;
  
  // Callback to save edits
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
  
  // Map to hold controllers for each subtask to ensure we don't lose focus
  final Map<String, TextEditingController> _subtaskControllers = {};

  // Date & Time & Category State
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  late String _selectedCategory; 

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(text: widget.task.description);
    
    // Initialize Category
    _selectedCategory = widget.task.category;

    // Initialize Date/Time from the task
    _selectedDate = widget.task.exactDate;
    if (widget.task.hasSpecificTime && widget.task.exactDate != null) {
      _selectedTime = TimeOfDay.fromDateTime(widget.task.exactDate!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    for (var c in _subtaskControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // --- Pickers ---
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    // SAFETY CHECK: Ensure widget is still on screen
    if (!mounted) return;
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (!mounted) return;
    if (time != null) setState(() => _selectedTime = time);
  }

  void _toggleEditMode() {
    if (_isEditing) {
      // --- Save Logic ---
      DateTime? finalExactDate;
      bool hasTime = false;
      String displayDate = "";

      if (_selectedDate != null) {
        if (_selectedTime != null) {
          // Merge Date + Time
          finalExactDate = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
            _selectedTime!.hour, _selectedTime!.minute
          );
          hasTime = true;
          // Format inside context safety is good practice
          if (mounted) {
             displayDate = "${_selectedDate!.day}/${_selectedDate!.month} ${_selectedTime!.format(context)}";
          }
        } else {
          // Date Only
          finalExactDate = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day
          );
          hasTime = false;
          displayDate = "${_selectedDate!.day}/${_selectedDate!.month}";
        }
      }

      final updatedTask = widget.task.copyWith(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _selectedCategory,
        exactDate: finalExactDate,
        dueDate: displayDate,
        hasSpecificTime: hasTime,
        // Update subtask titles from controllers if they exist
        subtasks: widget.task.subtasks.map((s) {
          if (_subtaskControllers.containsKey(s.id)) {
            return s.copyWith(title: _subtaskControllers[s.id]!.text.trim());
          }
          return s;
        }).toList(),
      );

      if (widget.onUpdate != null) {
        widget.onUpdate!(updatedTask);
      }
    }
    
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  // Helper to lazily create subtask controllers
  TextEditingController getSubtaskController(String id, String initialText) {
    return _subtaskControllers.putIfAbsent(id, () => TextEditingController(text: initialText));
  }

  @override
  Widget build(BuildContext context) {
    // Strings for display
    String dateText = _selectedDate == null 
        ? "Set Date" 
        : "${_selectedDate!.day}/${_selectedDate!.month}";
    
    String timeText = _selectedTime == null
        ? "Set Time"
        : _selectedTime!.format(context);

    return GestureDetector(
      onTap: widget.onClose,
      child: Material(
        color: Colors.black.withValues(alpha: 0.2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent closing when clicking inside modal
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
                ),
                child: Column(
                  children: [
                    // --- HEADER ---
                    Container(
                      height: 80, 
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      ),
                      child: Stack(
                        children: [
                          // Close Button
                          Positioned(
                            top: 16, right: 16,
                            child: IconButton(
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close),
                              style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                            ),
                          ),

                          // Priority Badge & Category (Display Mode)
                          Positioned(
                            bottom: 16, left: 24,
                            child: Row(
                              children: [
                                // Priority
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Text(
                                    "${widget.task.priority} Priority".toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Category
                                if (!_isEditing)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _selectedCategory.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.indigo),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // --- BODY ---
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          // TITLE ROW
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _isEditing 
                                  ? TextField(
                                      controller: _titleController,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                      textCapitalization: TextCapitalization.sentences,
                                      decoration: const InputDecoration(
                                        hintText: "Task Title",
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                      maxLines: null,
                                    )
                                  : Text(
                                      widget.task.title,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.2),
                                    ),
                              ),
                              if (!widget.isPreview && !_isEditing) 
                                IconButton(
                                  onPressed: widget.onToggle,
                                  icon: Icon(Icons.check, color: widget.task.isCompleted ? Colors.white : Colors.grey[400]),
                                  style: IconButton.styleFrom(
                                    backgroundColor: widget.task.isCompleted ? Colors.green : Colors.grey[100],
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 16),

                          // --- DATE & TIME ROW ---
                          if (_isEditing || widget.task.exactDate != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Row(
                                children: [
                                  // Date Chip
                                  _buildChip(
                                    icon: Icons.calendar_today,
                                    label: _isEditing ? dateText : (widget.task.dueDate.isNotEmpty ? widget.task.dueDate.split(' ').first : dateText),
                                    isActive: true, // Always active for date
                                    onTap: _isEditing ? _pickDate : null,
                                  ),
                                  const SizedBox(width: 10),

                                  // Time Chip
                                  _buildChip(
                                    icon: Icons.access_time,
                                    label: _isEditing 
                                        ? timeText 
                                        : (widget.task.hasSpecificTime ? widget.task.dueDate.split(' ').last : "No Time"),
                                    isActive: _isEditing && _selectedDate != null, // Only active if date is picked
                                    onTap: (_isEditing && _selectedDate != null) ? _pickTime : null,
                                    isHighlight: _isEditing && _selectedDate != null,
                                  ),
                                ],
                              ),
                            ),
                          
                          // --- CATEGORY SELECTOR (Editing Only) ---
                          if (_isEditing) ...[
                             Row(children: [
                                Icon(Icons.category, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 8),
                                Text("CATEGORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[400]))
                             ]),
                             const SizedBox(height: 8),
                             SingleChildScrollView(
                               scrollDirection: Axis.horizontal,
                               child: Row(
                                 children: ['General', 'Work', 'Personal', 'Shopping'].map((cat) {
                                   final bool isSelected = _selectedCategory == cat;
                                   return Padding(
                                     padding: const EdgeInsets.only(right: 8),
                                     child: ChoiceChip(
                                       label: Text(cat),
                                       selected: isSelected,
                                       onSelected: (bool selected) {
                                         if (selected) setState(() => _selectedCategory = cat);
                                       },
                                       selectedColor: Colors.indigo,
                                       backgroundColor: Colors.grey[100],
                                       labelStyle: TextStyle(
                                         color: isSelected ? Colors.white : Colors.black87,
                                         fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                                       ),
                                       side: BorderSide.none,
                                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                     ),
                                   );
                                 }).toList(),
                               ),
                             ),
                             const SizedBox(height: 24),
                          ],

                          // DESCRIPTION / NOTES
                          if (_isEditing || widget.task.description.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[200]!)
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(Icons.notes, size: 14, color: Colors.grey[400]),
                                    const SizedBox(width: 8),
                                    Text("NOTES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[400]))
                                  ]),
                                  const SizedBox(height: 8),
                                  _isEditing
                                    ? TextField(
                                        controller: _descController,
                                        style: TextStyle(color: Colors.grey[700], height: 1.5),
                                        textCapitalization: TextCapitalization.sentences,
                                        decoration: const InputDecoration(
                                          hintText: "Add details...",
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        maxLines: null,
                                      )
                                    : Text(widget.task.description, style: TextStyle(color: Colors.grey[700], height: 1.5)),
                                ],
                              ),
                            ),
                          
                          const SizedBox(height: 24),
                          
                          // SUBTASKS
                          if (widget.task.subtasks.isNotEmpty) ...[
                            Text("SUBTASKS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 1)),
                            const SizedBox(height: 12),
                            ...widget.task.subtasks.map((st) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start, 
                                children: [
                                  // Checkbox
                                  if (!_isEditing)
                                    InkWell(
                                      onTap: widget.isPreview ? null : () => widget.onSubtaskToggle(st.id),
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 2), 
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          color: st.isCompleted ? Colors.indigo : Colors.white,
                                          border: Border.all(color: st.isCompleted ? Colors.indigo : Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(6)
                                        ),
                                        child: st.isCompleted ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                                      ),
                                    ),
                                  
                                  const SizedBox(width: 12),
                                  
                                  // Text or Input
                                  Expanded(
                                    child: _isEditing
                                      ? TextField(
                                          controller: getSubtaskController(st.id, st.title),
                                          textCapitalization: TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: UnderlineInputBorder(),
                                          ),
                                        )
                                      : InkWell(
                                          onTap: widget.isPreview ? null : () => widget.onSubtaskToggle(st.id),
                                          child: Text(
                                            st.title, 
                                            style: TextStyle(
                                              color: st.isCompleted ? Colors.grey[400] : Colors.black87,
                                              decoration: st.isCompleted ? TextDecoration.lineThrough : null,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                  )
                                ],
                              ),
                            )),
                          ],

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),

                    // --- FOOTER (ACTION BUTTONS) ---
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey[100]!))
                      ),
                      child: widget.isPreview 
                      ? Column(
                          children: [
                            // 1. Micromanage Button
                            TextButton.icon(
                              onPressed: _toggleEditMode,
                              icon: Icon(_isEditing ? Icons.save : Icons.edit_note, size: 16),
                              label: Text(_isEditing ? "Save Changes" : "Micromanage Details"),
                              style: TextButton.styleFrom(
                                foregroundColor: _isEditing ? Colors.green : Colors.indigo
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // 2. Confirm/Discard
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: widget.onClose, 
                                    style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: const EdgeInsets.symmetric(vertical: 16)),
                                    child: const Text("Discard"),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    onPressed: widget.onConfirm,
                                    icon: const Icon(Icons.check),
                                    label: const Text("Confirm & Add"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: _toggleEditMode,
                              icon: Icon(_isEditing ? Icons.save : Icons.edit_note, size: 16),
                              label: Text(_isEditing ? "Save Changes" : "Micromanage"),
                              style: TextButton.styleFrom(
                                foregroundColor: _isEditing ? Colors.green : Colors.indigo
                              ),
                            ),
                            if (!_isEditing)
                              TextButton.icon(
                                onPressed: widget.onDelete,
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text("Delete"),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                              )
                          ],
                        ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper for Date/Time Chips
  Widget _buildChip({
    required IconData icon, 
    required String label, 
    required VoidCallback? onTap, 
    bool isActive = false, 
    bool isHighlight = false
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: isHighlight ? Border.all(color: Colors.indigo.withValues(alpha: 0.3)) : null
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isHighlight ? Colors.indigo : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}