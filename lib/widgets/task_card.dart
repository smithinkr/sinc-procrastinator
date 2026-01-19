import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for HapticFeedback
import '../models/task_model.dart';

class VisualTaskCard extends StatefulWidget {
  final Task task;
  final String themeColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  
  // New Variables passed from Home Screen
  final Color? overrideColor; 
  final Color? overrideBandColor;

  const VisualTaskCard({
    super.key,
    required this.task,
    required this.themeColor,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
    required this.onLongPress,
    this.overrideColor,
    this.overrideBandColor,
  });

  @override
  State<VisualTaskCard> createState() => VisualTaskCardState();
}

class VisualTaskCardState extends State<VisualTaskCard> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    // Setup Shimmer Animation
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800), 
    );

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOutSine),
    );

    _shimmerController.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        setState(() {}); 
      }
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> playMagicWoosh() async {
    HapticFeedback.heavyImpact();
    setState(() {}); 
    await _shimmerController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // 1. COLOR SELECTION LOGIC
    // Use the override if provided, otherwise fallback.
    final Color baseColor = widget.overrideColor ?? 
        (isDarkMode ? Colors.grey[900]! : Colors.white);

    final Color bannerColor = widget.overrideBandColor ?? 
        (isDarkMode ? Colors.white10 : Colors.grey[100]!);
    
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // --- LAYER 1: CONTENT ---
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDarkMode 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : Colors.white.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // A. TEXT (Left Side)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category Tag
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.task.category.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold, 
                                    color: isDarkMode ? Colors.white70 : Colors.grey[700], 
                                    letterSpacing: 0.5
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // Title
                              Text(
                                widget.task.title,
                                style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold,
                                  decoration: widget.task.isCompleted ? TextDecoration.lineThrough : null,
                                  color: isDarkMode 
                                      ? Colors.white.withValues(alpha: widget.task.isCompleted ? 0.5 : 1.0)
                                      : Colors.black.withValues(alpha: widget.task.isCompleted ? 0.38 : 0.87),
                                ),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              
                              // Description / Subtasks
                              if (widget.task.subtasks.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.checklist, size: 14, color: Colors.grey[500]),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${widget.task.subtasks.where((s) => s.isCompleted).length}/${widget.task.subtasks.length}",
                                        style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // B. THE BUTTON (Right Side)
                        GestureDetector(
                          onTap: widget.onToggle,
                          child: widget.task.isCompleted
                              // STATE 1: COMPLETED -> RESTORE BUTTON
                              // (Renamed comment to avoid linter warning)
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.all(Radius.circular(30)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x1A000000), // Fixed Hex (Black 10%)
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.replay, size: 14, color: Colors.black87),
                                        SizedBox(width: 4),
                                        Text(
                                          "Undone",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              // STATE 2: ACTIVE -> DONE BUTTON
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: isDarkMode ? Colors.white54 : Colors.grey.shade400,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    "Done", 
                                    style: TextStyle(
                                      fontSize: 12, 
                                      fontWeight: FontWeight.bold, 
                                      color: isDarkMode ? Colors.white70 : Colors.grey[600]
                                    )
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Bottom Banner (Date & Flag)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: bannerColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                      border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.03))),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.task.dueDate.isNotEmpty ? Icons.calendar_today_outlined : Icons.snooze,
                          size: 14, color: isDarkMode ? Colors.white70 : Colors.black87, 
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.task.dueDate.isNotEmpty ? "Due ${widget.task.dueDate}" : "Hold to Snooze",
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            fontStyle: widget.task.dueDate.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                            color: isDarkMode ? Colors.white70 : Colors.black87, 
                          ),
                        ),
                        const Spacer(),
                        if (widget.task.priority == 'High')
                          const Icon(Icons.flag, size: 14, color: Colors.redAccent)
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- LAYER 2: SHIMMER OVERLAY ---
            if (_shimmerController.isAnimating)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, child) {
                        return FractionallySizedBox(
                          widthFactor: 1.5,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(_shimmerAnimation.value - 1, 0),
                                end: Alignment(_shimmerAnimation.value, 0),
                                colors: [
                                  Colors.transparent,
                                  Colors.cyanAccent.withValues(alpha: 0.7),
                                  Colors.purpleAccent.withValues(alpha: 0.6),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.4, 0.6, 1.0],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}