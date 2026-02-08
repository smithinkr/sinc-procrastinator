import 'package:flutter/material.dart';

class CategoryRibbons extends StatelessWidget {
  final double width; // This is the _drawerDragOffset from HomeScreen
  final String selectedCategory;
  final String? highlightCategory;
  final Function(String) onCategoryTap;

  const CategoryRibbons({
    super.key,
    required this.width,
    required this.selectedCategory,
    this.highlightCategory,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    // We only show if the drawer is being pulled
    if (width <= 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min, 
      crossAxisAlignment: CrossAxisAlignment.start,
      // mainAxisAlignment is handled by the parent Align/Center in HomeScreen
      children: [
        _buildRibbonItem(context, "All Tasks", Colors.blueGrey),
        _buildRibbonItem(context, "Urgent", const Color(0xFFFF5722)),
        _buildRibbonItem(context, "Work", Colors.blueAccent),
        _buildRibbonItem(context, "Personal", Colors.pinkAccent),
        _buildRibbonItem(context, "Shopping", Colors.orangeAccent),
        _buildRibbonItem(context, "General", Colors.teal),
      ],
    );
  }

Widget _buildRibbonItem(BuildContext context, String label, Color categoryColor) {
  final double screenWidth = MediaQuery.of(context).size.width;
  
  bool isSelected = label == selectedCategory || (label == "All Tasks" && selectedCategory == "All");
  bool isHighlighted = label == highlightCategory;
  bool isManualDrag = highlightCategory == null;
  
  const double chunkyHeight = 70.0;

  // --- 🔥 THE FIX: SCALABLE DECOUPLED REVEAL ---
  double finalWidth;
  
  if (isHighlighted) {
    // 🎯 The Salute Logic: Take 45% of screen but clamp between 160 and 200
    double calculatedWidth = screenWidth * 0.45;
    finalWidth = calculatedWidth.clamp(160.0, 200.0);
  } else {
    // 🎯 The Manual Logic: Glue to finger, add small bonus for selected
    finalWidth = width;
    if (isSelected) finalWidth += 25;
  }

  // Ensure text shows up during the salute even if 'width' is low
  bool showText = width > 110 || isHighlighted;

  // Manual drag = 40ms (Snappy) | Auto salute = 350ms (Elegant)
  final int animDuration = isManualDrag ? 40 : 350;

  return GestureDetector(
    onTap: () => onCategoryTap(label),
    child: AnimatedContainer(
      duration: Duration(milliseconds: animDuration), 
      // easeOutBack gives it that "springy" premium feel during the salute
      curve: isManualDrag ? Curves.linear : Curves.easeOutBack,
      width: finalWidth,
      height: chunkyHeight,
      margin: const EdgeInsets.symmetric(vertical: 6), 
      decoration: BoxDecoration(
        color: isSelected 
            ? categoryColor.withValues(alpha: 0.95) 
            : categoryColor.withValues(alpha: 0.75), 
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isSelected ? 0.9 : 0.4),
          width: isSelected ? 2.5 : 1.0, 
        ),
        boxShadow: (isSelected && !isHighlighted) ? [
          BoxShadow(
            color: categoryColor.withValues(alpha: 0.5),
            blurRadius: 15,
            offset: const Offset(4, 0),
          )
        ] : null,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Container(
          // Prevents text-jitter by giving the Row a fixed internal canvas
          width: 220, 
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              Icon(
                _getIcon(label),
                color: Colors.white,
                size: 24,
              ),
              if (showText) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    ),
  );
}

  IconData _getIcon(String label) {
    switch (label) {
      case 'All Tasks': return Icons.auto_awesome_motion;
      case 'Urgent': return Icons.bolt;
      case 'Work': return Icons.work_outline;
      case 'Personal': return Icons.person_outline;
      case 'Shopping': return Icons.shopping_cart_outlined;
      default: return Icons.label_outline;
    }
  }
}