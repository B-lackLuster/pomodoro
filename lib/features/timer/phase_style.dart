import 'package:flutter/material.dart';

import '../../core/models.dart';

/// 三个阶段各自的强调色（专注=番茄红、短休=青、长休=蓝）
const phaseColors = <PomodoroPhase, Color>{
  PomodoroPhase.focus: Color(0xFFE53935),
  PomodoroPhase.shortBreak: Color(0xFF00897B),
  PomodoroPhase.longBreak: Color(0xFF1565C0),
};

Color phaseColor(PomodoroPhase phase) => phaseColors[phase]!;
