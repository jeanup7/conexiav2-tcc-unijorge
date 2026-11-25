import 'package:flutter/material.dart';

/// Shared bottom navigation for authenticated and preview screens.
class ConexiaCompass extends StatelessWidget {
  const ConexiaCompass({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: destinations,
  );
}
