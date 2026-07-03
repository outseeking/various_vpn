/// Гео-справочник: координаты стран (для маркеров на глобусе) и соответствие
/// кода страны названию в world.json (для подсветки выбранной страны).
library;

class Geo {
  Geo._();

  /// [долгота, широта] — центр страны для маркера/докрутки глобуса.
  static const Map<String, List<double>> coords = {
    'DE': [10.4, 51.1],
    'NL': [5.3, 52.1],
    'FI': [25.0, 62.0],
    'RU': [37.6, 55.7],
    'US': [-98.0, 39.0],
    'GB': [-1.5, 52.5],
    'FR': [2.3, 46.6],
    'SE': [16.0, 62.0],
    'PL': [19.0, 52.0],
    'TR': [35.0, 39.0],
  };

  /// Название страны в world.json (Natural Earth) по коду — для подсветки.
  static const Map<String, String> worldName = {
    'DE': 'Germany',
    'NL': 'Netherlands',
    'FI': 'Finland',
    'RU': 'Russia',
    'US': 'United States of America',
    'GB': 'United Kingdom',
    'FR': 'France',
    'SE': 'Sweden',
    'PL': 'Poland',
    'TR': 'Turkey',
  };

  /// Откуда «выходит» пользователь (для анимации пакетов) — Россия.
  static const List<double> origin = [37.6, 55.7];

  static List<double>? of(String cc) => coords[cc];
}
