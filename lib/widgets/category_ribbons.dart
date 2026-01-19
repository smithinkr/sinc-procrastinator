import 'package:flutter/material.dart';

class CategoryRibbons extends StatelessWidget {
  final double width; // This is the _drawerDragOffset from HomeScreen
  final String selectedCategory;
  final Function(String) onCategoryTap;

  const CategoryRibbons({
    super.key,
    required this.width,
    required this.selectedCategory,
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
    
    // --- 1. VERTICAL THICKNESS (CHUNKY) ---
    // Fixed height ensures they look prominent and consistent across devices
    const double chunkyHeight = 70.0;

    // --- 2. PULL-OUT HORIZONTAL LOGIC ---
    // The width follows the drag (width). 
    // We add a small 'pop' if selected so it looks substantial.
    double finalWidth = isSelected ? width + 25 : width;

    // Only show text if there is enough horizontal room
    bool showText = width > 110;

    return GestureDetector(
      onTap: () => onCategoryTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: finalWidth,
        height: chunkyHeight,
        // Reduced spacing between ribbons for a cohesive cluster
        margin: const EdgeInsets.symmetric(vertical: 6), 
        decoration: BoxDecoration(
          // Vibrant color even when glassy (0.75 alpha)
          color: isSelected 
              ? categoryColor.withValues(alpha: 0.95) 
              : categoryColor.withValues(alpha: 0.75), 
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(25), // Pill-shaped right edge
            bottomRight: Radius.circular(25),
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: isSelected ? 0.9 : 0.4),
            width: isSelected ? 2.5 : 1.0, 
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: categoryColor.withValues(alpha: 0.5),
                blurRadius: 15,
                offset: const Offset(4, 0),
              )
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Container(
            // Safe zone to prevent text wrap/overflow flashing
            width: screenWidth * 0.6, 
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Icon(
                  _getIcon(label),
                  color: Colors.white,
                  size: 24, // Consistent icon size
                ),
                if (showText) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14, // Contained size to prevent overcrowding
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