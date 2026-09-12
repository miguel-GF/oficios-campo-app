import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JalePalette {
  const JalePalette({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.background,
    required this.surface,
    required this.accent,
  });

  final String id;
  final String name;
  final String description;
  final Color primary;
  final Color background;
  final Color surface;
  final Color accent;
}

const jalePalettes = <JalePalette>[
  JalePalette(
    id: 'cobalto',
    name: 'Cobalto',
    description: 'Azul vivo, claro y confiable',
    primary: Color(0xff1769aa),
    background: Color(0xfff1f7fc),
    surface: Colors.white,
    accent: Color(0xffffc857),
  ),
  JalePalette(
    id: 'campo',
    name: 'Campo',
    description: 'Verde cálido y natural',
    primary: Color(0xff176b57),
    background: Color(0xfff5f6f1),
    surface: Colors.white,
    accent: Color(0xffffc857),
  ),
  JalePalette(
    id: 'mar',
    name: 'Mar',
    description: 'Azul fresco y confiable',
    primary: Color(0xff145b83),
    background: Color(0xfff1f6fa),
    surface: Colors.white,
    accent: Color(0xfff2b84b),
  ),
  JalePalette(
    id: 'barro',
    name: 'Barro',
    description: 'Terracota cercano y firme',
    primary: Color(0xff9a4d32),
    background: Color(0xfffaf5f0),
    surface: Colors.white,
    accent: Color(0xffe8b35c),
  ),
  JalePalette(
    id: 'noche',
    name: 'Noche',
    description: 'Violeta sobrio y moderno',
    primary: Color(0xff60458e),
    background: Color(0xfff6f3fa),
    surface: Colors.white,
    accent: Color(0xffd7a7f5),
  ),
  JalePalette(
    id: 'grafito',
    name: 'Grafito',
    description: 'Gris carbón minimalista',
    primary: Color(0xff303b43),
    background: Color(0xfff3f5f6),
    surface: Colors.white,
    accent: Color(0xff8ed0c4),
  ),
];

class JaleThemeController extends ChangeNotifier {
  JalePalette palette = jalePalettes.first;
  bool darkMode = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('jale.palette') ?? palette.id;
    darkMode = prefs.getBool('jale.darkMode') ?? false;
    palette = jalePalettes.firstWhere(
      (item) => item.id == id,
      orElse: () => jalePalettes.first,
    );
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (darkMode == value) return;
    darkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jale.darkMode', value);
  }

  Future<void> select(JalePalette next) async {
    if (palette.id == next.id) return;
    palette = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jale.palette', next.id);
  }

  ThemeData get theme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: darkMode ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: palette.primary,
          onPrimary: Colors.white,
          secondary: palette.accent,
          surface: darkMode ? const Color(0xff121212) : palette.surface,
          surfaceContainer: darkMode
              ? const Color(0xff1b1b1b)
              : palette.surface,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: darkMode ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkMode ? Colors.black : palette.background,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkMode ? const Color(0xff1b1b1b) : palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkMode ? const Color(0xff151515) : palette.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
