import 'package:flutter/material.dart';
import 'package:marineflow/features/timer/timer_screen.dart';

void main() {
  runApp(const MarineFlowApp());
}

class MarineFlowApp extends StatelessWidget {
  const MarineFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF0F1115);
    return MaterialApp(
      title: 'MarineFlow',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: surface,
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: Color(0xFF42E3A7),
          secondary: Color(0xFFFFC857),
        ),
      ),
      home: const TimerScreen(),
    );
  }
}
