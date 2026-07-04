/// Тёмный глобус-карта (орфографическая проекция Natural Earth 110m).
///
/// Умеет: медленно вращаться, плавно докручиваться к выбранной стране, при
/// подключении делать ускоряющийся «наезд» на страну и обратно, рисовать
/// маркеры серверов с подписями стран, жёлтую галочку выбранной локации и
/// пакеты, летящие из России в активный сервер.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

/// Маркер сервера на глобусе.
class GlobeMarker {
  final double lon;
  final double lat;
  final String label; // подпись (страна)
  final bool selected;
  const GlobeMarker({
    required this.lon,
    required this.lat,
    required this.label,
    this.selected = false,
  });
}

/// Распарсенная карта мира (кэшируется на всё приложение).
class WorldData {
  final List<MapCountry> countries;
  WorldData(this.countries);

  static Future<WorldData>? _future;
  static Future<WorldData> load() {
    return _future ??= rootBundle
        .loadString('assets/geo/world.json')
        .then((raw) {
      final list = jsonDecode(raw) as List;
      final countries = <MapCountry>[];
      for (final c in list) {
        final m = c as Map<String, dynamic>;
        final rings = <List<double>>[];
        for (final r in (m['r'] as List)) {
          final flat = <double>[];
          for (final p in (r as List)) {
            flat.add((p[0] as num).toDouble());
            flat.add((p[1] as num).toDouble());
          }
          rings.add(flat);
        }
        countries.add(MapCountry(m['n'] as String, rings));
      }
      return WorldData(countries);
    });
  }
}

/// Одна страна карты: имя + контуры (каждый ring — flat [lon,lat,lon,lat,...]).
class MapCountry {
  final String name;
  final List<List<double>> rings;
  MapCountry(this.name, this.rings);
}

class GlobeView extends StatefulWidget {
  final List<GlobeMarker> markers;

  /// Куда смотреть (страна выбранного сервера). Смена запускает докрутку.
  final List<double>? focus; // [lon,lat]

  /// true → проигрываем «наезд» на страну и обратно.
  final bool connected;

  /// Откуда летят пакеты (Россия). null → без пакетов.
  final List<double>? packetFrom;

  /// Промежуточная нода (вход) для двойного VPN: [lon,lat]. При наличии —
  /// путь строится через неё (from → relay → exit) с доп. пакетом, а её страна
  /// тоже подсвечивается.
  final List<double>? relay;
  final String? relayLabel;

  final bool animationsEnabled;
  final double size;

  const GlobeView({
    super.key,
    required this.markers,
    this.focus,
    this.connected = false,
    this.packetFrom,
    this.relay,
    this.relayLabel,
    this.animationsEnabled = true,
    this.size = 240,
  });

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

class _GlobeViewState extends State<GlobeView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  WorldData? _world;

  // вращение (центр глобуса = -rotLon, -rotLat)
  double _rotLon = -12, _rotLat = -38;

  // докрутка
  bool _rotting = false;
  double _rotT = 0;
  final double _rotDur = 1.2;
  double _fromLon = 0, _fromLat = 0, _toLon = 0, _toLat = 0;

  // zoom при подключении
  bool _zoomActive = false;
  double _zoomT = 0;
  double _scaleMul = 1.0;

  // пользовательское управление: drag = вращение (зум убран).
  bool _userInteracting = false;

  // пакеты
  double _packT = 0;

  // общее время анимации (для мерцания звёзд, блика, пульсации страны)
  double _time = 0;

  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    WorldData.load().then((w) {
      if (mounted) setState(() => _world = w);
    });
    if (widget.focus != null) _aimAt(widget.focus!, instant: true);
    _ticker = createTicker(_onTick)..start();
  }

  void _aimAt(List<double> ll, {bool instant = false}) {
    final targetLon = _shortest(_rotLon, -ll[0]);
    final targetLat = -ll[1];
    if (instant) {
      _rotLon = targetLon;
      _rotLat = targetLat;
      return;
    }
    _fromLon = _rotLon;
    _fromLat = _rotLat;
    _toLon = targetLon;
    _toLat = targetLat;
    _rotT = 0;
    _rotting = true;
  }

  // ближайший эквивалент угла b к текущему a (без лишнего оборота)
  double _shortest(double a, double b) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return a + d;
  }

  @override
  void didUpdateWidget(GlobeView old) {
    super.didUpdateWidget(old);
    final f = widget.focus;
    if (f != null &&
        (old.focus == null || old.focus![0] != f[0] || old.focus![1] != f[1])) {
      _aimAt(f);
    }
    if (widget.connected && !old.connected) {
      _zoomActive = true;
      _zoomT = 0;
      if (widget.focus != null) _aimAt(widget.focus!);
    }
  }

  Duration _lastPaint = Duration.zero;

  void _onTick(Duration now) {
    // Троттлинг до ~30 fps: перерисовка всей карты мира каждый кадр (60/120 Гц)
    // грузит слабые устройства. 30 fps для глобуса визуально плавно.
    if (_lastPaint != Duration.zero &&
        (now - _lastPaint).inMilliseconds < 33 &&
        !_userInteracting) {
      return;
    }
    _lastPaint = now;

    final dt = _last == Duration.zero
        ? 0.016
        : (now - _last).inMicroseconds / 1e6;
    _last = now;

    final anim = widget.animationsEnabled;
    // время анимации копим ТОЛЬКО когда анимации включены — иначе звёзды,
    // радар-пульс и падающие звёзды замирают (флаг реально выключает всё).
    if (anim) _time += dt;

    // докрутка
    if (_rotting) {
      _rotT += dt / _rotDur;
      if (_rotT >= 1) {
        _rotT = 1;
        _rotting = false;
      }
      final e = _easeInOut(_rotT);
      _rotLon = _fromLon + (_toLon - _fromLon) * e;
      _rotLat = _fromLat + (_toLat - _fromLat) * e;
    } else if (anim && !widget.connected && !_userInteracting) {
      // лёгкое автовращение только когда НЕ подключены и пользователь не крутит
      // глобус сам; при подключении глобус держится на выбранной стране.
      _rotLon -= dt * 6;
    }

    // при подключении глобус слегка приближается к выбранной стране — плавно,
    // без резкого «наезда». Без подключения — обычный масштаб.
    final restScale = widget.connected ? 1.22 : 1.0;

    // мягкое приближение при подключении: просто плавно тянемся к restScale
    // (ease через экспоненциальное сглаживание) — красиво и без рывков.
    if (_zoomActive) {
      _zoomT += dt / 1.2;
      if (_zoomT >= 1) {
        _zoomT = 1;
        _zoomActive = false;
      }
    }
    _scaleMul += (restScale - _scaleMul) * (dt * 3.2).clamp(0, 1);

    // пакеты
    if (widget.connected && anim) {
      _packT = (_packT + dt * 0.45) % 1.0;
    }

    _repaint.value++;
  }

  double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    _userInteracting = true;
    _rotting = false; // прерываем докрутку — пользователь взял управление
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // вращение пальцем: сдвиг → изменение долготы/широты. Зум убран по просьбе.
    _rotLon += d.delta.dx * 0.35;
    _rotLat = (_rotLat - d.delta.dy * 0.35).clamp(-85.0, 85.0);
    _repaint.value++;
  }

  void _onPanEnd(DragEndDetails d) {
    _userInteracting = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _GlobePainter(
            state: this,
            repaint: _repaint,
          ),
        ),
      ),
    );
  }
}

class _GlobePainter extends CustomPainter {
  final _GlobeViewState state;
  _GlobePainter({required this.state, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 4;
    final scale = r * state._scaleMul;

    final lon0 = -state._rotLon * math.pi / 180;
    final lat0 = -state._rotLat * math.pi / 180;
    final sinLat0 = math.sin(lat0);
    final cosLat0 = math.cos(lat0);

    final t = state._time;
    // звёзды вокруг Земли + изредка падающие звёзды (в области глобуса)
    _drawStars(canvas, size, cx, cy, r, t);
    if (state.widget.animationsEnabled) _drawShootingStars(canvas, size, t);

    // атмосфера — мягкое свечение по краю сферы (при подключении ярче/лаймовее)
    final atmoColor = state.widget.connected ? P.lime : P.violet;
    final atmoAlpha = state.widget.connected ? 0.28 : 0.16;
    canvas.drawCircle(
        Offset(cx, cy),
        r + 6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              atmoColor.withValues(alpha: atmoAlpha),
              atmoColor.withValues(alpha: 0.0),
            ],
            stops: const [0.86, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r + 6))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // вода (сфера)
    final water = Paint()..color = P.bgGlobe;
    canvas.drawCircle(Offset(cx, cy), r, water);
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x0DFFFFFF));

    // ограничиваем рисование диском глобуса
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // проекция точки -> экран; возвращает null, если на обратной стороне
    Offset? project(double lonDeg, double latDeg) {
      final lon = lonDeg * math.pi / 180;
      final lat = latDeg * math.pi / 180;
      final cosc =
          sinLat0 * math.sin(lat) + cosLat0 * math.cos(lat) * math.cos(lon - lon0);
      if (cosc < 0) return null; // обратная сторона
      final x = math.cos(lat) * math.sin(lon - lon0);
      final y =
          cosLat0 * math.sin(lat) - sinLat0 * math.cos(lat) * math.cos(lon - lon0);
      return Offset(cx + scale * x, cy - scale * y);
    }

    _drawGraticule(canvas, project);

    final world = state._world;
    if (world != null) {
      final landFill = Paint()..color = P.land;
      final landStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..color = P.landStroke;
      final selFill = Paint()..color = P.gold.withValues(alpha: 0.32);
      final selStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = P.gold;

      // имена подсвечиваемых стран: выбранный сервер + вход (при мультихопе)
      final highlight = <String>{};
      for (final m in state.widget.markers) {
        if (m.selected) highlight.add(_ru2world(m.label));
      }
      if (state.widget.relayLabel != null) {
        highlight.add(_ru2world(state.widget.relayLabel!));
      }

      for (final c in world.countries) {
        final isSel = highlight.contains(c.name);
        for (final ring in c.rings) {
          final path = _ringPath(ring, project);
          if (path == null) continue;
          canvas.drawPath(path, isSel ? selFill : landFill);
          canvas.drawPath(path, isSel ? selStroke : landStroke);
        }
      }
    }

    // дуга и пакеты из России в активный сервер
    final from = state.widget.packetFrom;
    GlobeMarker? sel;
    for (final m in state.widget.markers) {
      if (m.selected) {
        sel = m;
        break;
      }
    }
    if (from != null && sel != null && state.widget.connected) {
      final relay = state.widget.relay;
      if (relay != null) {
        // двойной VPN: путь Россия → вход → выход, с пакетом на каждом участке
        _drawArc(canvas, project, from, relay);
        _drawArc(canvas, project, relay, [sel.lon, sel.lat]);
      } else {
        _drawArc(canvas, project, from, [sel.lon, sel.lat]);
      }
    }

    // --- 3D-затенение сферы (пока клип ещё активен) ---
    // 1) затемнение к краю (limb darkening) — создаёт объём шара.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4), // источник света сверху-слева
          radius: 1.1,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.45),
          ],
          stops: const [0.55, 0.8, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    // 2) мягкий блик сверху-слева.
    canvas.drawCircle(
      Offset(cx - r * 0.32, cy - r * 0.36),
      r * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(cx - r * 0.32, cy - r * 0.36), radius: r * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    canvas.restore(); // снимаем клип для маркеров/подписей (они поверх края ок)

    // маркеры серверов + подписи стран
    for (final m in state.widget.markers) {
      final p = project(m.lon, m.lat);
      if (p == null) continue;
      if (!m.selected) {
        canvas.drawCircle(
            p, 2.6, Paint()..color = const Color(0xB3CFE0FF));
      }
      _label(canvas, p, m.label, m.selected);
    }

    // выбранная локация: мягкий оранжевый ореол (без галочки — страна уже
    // подсвечена оранжевым заполнением выше).
    if (sel != null) {
      final p = project(sel.lon, sel.lat);
      if (p != null) {
        // пульсирующее кольцо-радар вокруг выбранной страны — «дорогой» акцент
        final pr = (state._time * 0.9) % 1.0;
        canvas.drawCircle(
            p,
            5 + pr * 16,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = P.gold.withValues(alpha: (1 - pr) * 0.7));
        canvas.drawCircle(p, 7, Paint()..color = P.gold.withValues(alpha: 0.22));
        canvas.drawCircle(p, 3.2, Paint()..color = P.gold);
        canvas.drawCircle(
            p,
            3.2,
            Paint()
              ..color = P.gold.withValues(alpha: 0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
    }

    // источник (Россия) — с подписью, чтобы точка не выглядела «лишней»
    if (from != null) {
      final p = project(from[0], from[1]);
      if (p != null) {
        canvas.drawCircle(p, 3, Paint()..color = const Color(0xCCFFFFFF));
        _label(canvas, p, 'Россия', false);
      }
    }

    // один летящий пакет со шлейфом, курсирует с паузами (первые ~65% цикла
    // летит, дальше пауза — так глобус не «пестрит»).
    if (from != null && sel != null && state.widget.connected) {
      final cycle = state._packT;
      if (cycle < 0.65) {
        final phase = cycle / 0.65; // 0..1 полёт
        final dst = [sel.lon, sel.lat];
        for (var tI = 0; tI < 5; tI++) {
          final tt = phase - tI * 0.04;
          if (tt < 0 || tt > 1) continue;
          final pos = _slerp(from, dst, tt);
          final p = project(pos[0], pos[1]);
          if (p == null) continue;
          final a = (1 - tI / 5.0) * 0.9;
          canvas.drawCircle(
              p, 3.2 - tI * 0.5, Paint()..color = P.limeText.withValues(alpha: a));
        }
      }
    }
  }

  // Звёздное поле вокруг Земли (вне диска глобуса), мягко мерцает.
  void _drawStars(
      Canvas canvas, Size size, double cx, double cy, double r, double t) {
    const n = 60;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final h = (i * 2654435761) & 0x7fffffff;
      final x = (h % 1000) / 1000 * size.width;
      final y = ((h ~/ 1000) % 1000) / 1000 * size.height;
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy < (r + 10) * (r + 10)) continue; // не на глобусе
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 1.6 + i));
      final rad = 0.6 + (i % 3) * 0.5;
      p.color = Colors.white.withValues(alpha: 0.10 + 0.28 * tw);
      canvas.drawCircle(Offset(x, y), rad, p);
    }
  }

  // Падающие звёзды — несколько каналов, красивый затухающий след с длинным
  // хвостом. Часть траекторий проходит через центр — и уходит ЗА глобус (сфера
  // рисуется поверх, звезда скрывается за Землёй).
  void _drawShootingStars(Canvas canvas, Size size, double t) {
    // период, фаза, startX, startY, длина(доля ширины), наклон(dy/dx)
    const channels = [
      [5.0, 0.0, 0.05, 0.06, 0.95, 0.55],
      [6.5, 2.1, 0.62, 0.02, 0.85, 0.62],
      [8.0, 4.0, 0.20, 0.00, 1.05, 0.85], // через центр — за глобусом
      [9.5, 1.2, 0.85, 0.30, 0.70, 0.50],
      [11.0, 6.0, 0.40, 0.55, 0.65, -0.45],
    ];
    for (final c in channels) {
      final local = (t + c[1]) % c[0];
      if (local > 1.2) continue;
      final p = local / 1.2;
      final sx = size.width * c[2];
      final sy = size.height * c[3];
      final len = size.width * c[4];
      final dx = len, dy = len * c[5];
      final hx = sx + dx * p, hy = sy + dy * p;
      final tp = (p - 0.22).clamp(0.0, 1.0); // длиннее хвост
      final tx = sx + dx * tp, ty = sy + dy * tp;
      final fade = 1 - p;
      canvas.drawLine(
        Offset(tx, ty),
        Offset(hx, hy),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(tx, ty),
            Offset(hx, hy),
            [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9 * fade)],
          )
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
      canvas.drawCircle(
          Offset(hx, hy), 2.6, Paint()..color = Colors.white.withValues(alpha: fade));
      canvas.drawCircle(
          Offset(hx, hy),
          6,
          Paint()
            ..color = P.limeText.withValues(alpha: 0.5 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
  }

  void _drawGraticule(Canvas canvas, Offset? Function(double, double) project) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = P.graticule;
    for (var lon = -180.0; lon < 180; lon += 30) {
      _polyline(canvas, paint, project, (t) => [lon, -80 + t * 160], 40);
    }
    for (var lat = -60.0; lat <= 60; lat += 30) {
      _polyline(canvas, paint, project, (t) => [-180 + t * 360, lat], 60);
    }
  }

  void _polyline(Canvas canvas, Paint paint,
      Offset? Function(double, double) project,
      List<double> Function(double) at, int steps) {
    Path? path;
    for (var i = 0; i <= steps; i++) {
      final ll = at(i / steps);
      final p = project(ll[0], ll[1]);
      if (p == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  Path? _ringPath(List<double> flat, Offset? Function(double, double) project) {
    Path? path;
    var started = false;
    for (var i = 0; i < flat.length; i += 2) {
      final p = project(flat[i], flat[i + 1]);
      if (p == null) {
        // обрыв на горизонте — завершаем подпуть
        started = false;
        continue;
      }
      if (!started) {
        path ??= Path();
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path!.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  void _drawArc(Canvas canvas, Offset? Function(double, double) project,
      List<double> a, List<double> b) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x8C7CB10F);
    Path? path;
    for (var i = 0; i <= 40; i++) {
      final ll = _slerp(a, b, i / 40);
      final p = project(ll[0], ll[1]);
      if (p == null) {
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  // сферическая интерполяция между двумя точками [lon,lat] (доли t)
  List<double> _slerp(List<double> a, List<double> b, double t) {
    final va = _toVec(a), vb = _toVec(b);
    var dot = va[0] * vb[0] + va[1] * vb[1] + va[2] * vb[2];
    dot = dot.clamp(-1.0, 1.0);
    final omega = math.acos(dot);
    if (omega < 1e-6) return a;
    final s = math.sin(omega);
    final k0 = math.sin((1 - t) * omega) / s;
    final k1 = math.sin(t * omega) / s;
    final x = k0 * va[0] + k1 * vb[0];
    final y = k0 * va[1] + k1 * vb[1];
    final z = k0 * va[2] + k1 * vb[2];
    final lat = math.asin(z) * 180 / math.pi;
    final lon = math.atan2(y, x) * 180 / math.pi;
    return [lon, lat];
  }

  List<double> _toVec(List<double> ll) {
    final lon = ll[0] * math.pi / 180, lat = ll[1] * math.pi / 180;
    return [math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)];
  }

  void _label(Canvas canvas, Offset p, String text, bool selected) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? P.gold : const Color(0xCCFFFFFF),
          shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.dx + 7, p.dy - tp.height / 2));
  }

  static String _ru2world(String ru) => switch (ru) {
        'Германия' => 'Germany',
        'Нидерланды' => 'Netherlands',
        'Финляндия' => 'Finland',
        'Россия' => 'Russia',
        'США' => 'United States of America',
        'Великобритания' => 'United Kingdom',
        _ => ru,
      };

  @override
  bool shouldRepaint(covariant _GlobePainter old) => true;
}
