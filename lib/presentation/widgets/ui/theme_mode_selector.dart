import 'package:flutter/material.dart';

/// System / Light / Dark segmented control. Styling comes from the theme's
/// `segmentedButtonTheme` (lime selected pill). Value is owned by the
/// caller (ThemeCubit) so this widget stays dependency-free.
class ThemeModeSelector extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  const ThemeModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('Auto'),
          icon: Icon(Icons.brightness_auto, size: 18),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Light'),
          icon: Icon(Icons.light_mode, size: 18),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Dark'),
          icon: Icon(Icons.dark_mode, size: 18),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
      showSelectedIcon: false,
    );
  }
}
