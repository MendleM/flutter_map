import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/map/flutter_map_state.dart';
import 'package:latlong2/latlong.dart';

class Polyline {
  final List<LatLng> points;
  final double strokeWidth;
  final Color color;
  final double borderStrokeWidth;
  final Color? borderColor;
  final List<Color>? gradientColors;
  final List<double>? colorsStop;
  final bool isDotted;
  final bool isDashed;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final bool useStrokeWidthInMeter;
  final double dashGap;
  final double dashLength;

  LatLngBounds? _boundingBox;

  LatLngBounds get boundingBox {
    _boundingBox ??= LatLngBounds.fromPoints(points);
    return _boundingBox!;
  }

  Polyline({
    required this.points,
    this.strokeWidth = 1.0,
    this.dashLength = 6.0,
    this.dashGap = 3.0,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.gradientColors,
    this.colorsStop,
    this.isDotted = false,
    this.isDashed = false,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.useStrokeWidthInMeter = false,
  });

  /// Used to batch draw calls to the canvas.
  int get renderHashCode => Object.hash(
        strokeWidth,
        dashLength,
        dashGap,
        color,
        borderStrokeWidth,
        borderColor,
        gradientColors,
        colorsStop,
        isDotted,
        isDashed,
        strokeCap,
        strokeJoin,
        useStrokeWidthInMeter,
      );
}

class PolylineLayer extends StatelessWidget {
  /// List of polylines to draw.
  final List<Polyline> polylines;

  final bool polylineCulling;

  /// {@macro newPolylinePainter.saveLayers}
  ///
  /// By default, this value is set to `false` to improve performance on
  /// layers containing a lot of polylines.
  ///
  /// You might want to set this to `true` if you get unwanted darker lines
  /// where they overlap but, keep in mind that this might reduce the
  /// performance of the layer.
  final bool saveLayers;

  const PolylineLayer({
    super.key,
    this.polylines = const [],
    this.polylineCulling = false,
    this.saveLayers = false,
  });

  @override
  Widget build(BuildContext context) {
    final map = FlutterMapState.maybeOf(context)!;
    final size = Size(map.size.x, map.size.y);
    final origin = map.pixelOrigin;
    final offset = Offset(origin.x.toDouble(), origin.y.toDouble());

    final Iterable<Polyline> lines = polylineCulling
        ? polylines.where((p) {
            return p.boundingBox.isOverlapping(map.bounds);
          })
        : polylines;

    final paint = CustomPaint(
      painter: PolylinePainter(lines, saveLayers, map),
      size: size,
      isComplex: true,
    );

    return Positioned(
      left: -offset.dx,
      top: -offset.dy,
      child: kIsWeb ? paint : RepaintBoundary(child: paint),
    );
  }
}

class PolylinePainter extends CustomPainter {
  final Iterable<Polyline> polylines;

  /// {@template newPolylinePainter.saveLayers}
  /// If `true`, the canvas will be updated on every frame by calling the
  /// methods [Canvas.saveLayer] and [Canvas.restore].
  /// {@endtemplate}
  final bool saveLayers;

  final FlutterMapState map;
  final double zoom;
  final double rotation;

  PolylinePainter(this.polylines, this.saveLayers, this.map)
      : zoom = map.zoom,
        rotation = map.rotation;

  int get hash {
    _hash ??= Object.hashAll(polylines);
    return _hash!;
  }

  int? _hash;

  List<Offset> getOffsets(List<LatLng> points) {
    return List.generate(points.length, (index) {
      return getOffset(points[index]);
    }, growable: false);
  }

  Offset getOffset(LatLng point) {
    final delta = map.project(point);
    return Offset(delta.x.toDouble(), delta.y.toDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    var path = ui.Path();
    var borderPath = ui.Path();
    var filterPath = ui.Path();
    var paint = Paint();
    Paint? borderPaint;
    Paint? filterPaint;
    int? lastHash;

    void drawPaths() {
      canvas.drawPath(path, paint);
      path = ui.Path();
      paint = Paint();

      if (borderPaint != null) {
        canvas.drawPath(borderPath, borderPaint!);
        borderPath = ui.Path();
        borderPaint = null;
      }

      if (filterPaint != null) {
        canvas.drawPath(filterPath, filterPaint!);
        filterPath = ui.Path();
        filterPaint = null;
      }
    }

    for (final polyline in polylines) {
      final offsets = getOffsets(polyline.points);
      if (offsets.isEmpty) {
        continue;
      }

      final hash = polyline.renderHashCode;
      if (lastHash != null && lastHash != hash) {
        drawPaths();
      }
      lastHash = hash;

      late final double strokeWidth;
      if (polyline.useStrokeWidthInMeter) {
        final firstPoint = polyline.points.first;
        final firstOffset = offsets.first;
        final r = const Distance().offset(
          firstPoint,
          polyline.strokeWidth,
          180,
        );
        final delta = firstOffset - getOffset(r);

        strokeWidth = delta.distance;
      } else {
        strokeWidth = polyline.strokeWidth;
      }

      final isDotted = polyline.isDotted;
      final isDashed = polyline.isDashed;

      paint = Paint()
        ..strokeWidth = strokeWidth
        ..strokeCap = polyline.strokeCap
        ..strokeJoin = polyline.strokeJoin
        ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
        ..blendMode = BlendMode.srcOver;

      if (polyline.gradientColors == null) {
        paint.color = polyline.color;
      } else {
        polyline.gradientColors!.isNotEmpty
            ? paint.shader = _paintGradient(polyline, offsets)
            : paint.color = polyline.color;
      }

      if (polyline.borderColor != null) {
        filterPaint = Paint()
          ..color = polyline.borderColor!.withAlpha(255)
          ..strokeWidth = strokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.dstOut;
      }

      if (polyline.borderStrokeWidth > 0.0) {
        borderPaint = Paint()
          ..color = polyline.borderColor ?? const Color(0x00000000)
          ..strokeWidth = strokeWidth + polyline.borderStrokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.srcOver;
      }

      final radius = paint.strokeWidth / 2;
      final borderRadius = (borderPaint?.strokeWidth ?? 0) / 2;

      if (saveLayers) canvas.saveLayer(rect, Paint());
      if (isDotted) {
        final spacing = strokeWidth * 1.5;
        if (borderPaint != null && filterPaint != null) {
          _paintDottedLine(borderPath, offsets, borderRadius, spacing);
          _paintDottedLine(filterPath, offsets, radius, spacing);
        }
        _paintDottedLine(path, offsets, radius, spacing);
      } else if (isDashed) {
        if (borderPaint != null && filterPaint != null) {
          _paintDashedLine(
            borderPath,
            offsets,
            strokeWidth,
            polyline.dashLength,
            polyline.dashGap,
            zoom,
          );
          _paintDashedLine(
            filterPath,
            offsets,
            strokeWidth,
            polyline.dashLength,
            polyline.dashGap,
            zoom,
          );
        }
        _paintDashedLine(
          path,
          offsets,
          strokeWidth,
          polyline.dashLength,
          polyline.dashGap,
          zoom,
        );
      } else {
        if (borderPaint != null && filterPaint != null) {
          _paintLine(borderPath, offsets);
          _paintLine(filterPath, offsets);
        }
        _paintLine(path, offsets);
      }
      if (saveLayers) canvas.restore();
    }

    drawPaths();
  }

  void _paintDottedLine(ui.Path path, List<Offset> offsets, double radius, double stepLength) {
    var startDistance = 0.0;
    for (var i = 0; i < offsets.length - 1; i++) {
      final o0 = offsets[i];
      final o1 = offsets[i + 1];
      final totalDistance = (o0 - o1).distance;
      var distance = startDistance;
      while (distance < totalDistance) {
        final f1 = distance / totalDistance;
        final f0 = 1.0 - f1;
        final offset = Offset(o0.dx * f0 + o1.dx * f1, o0.dy * f0 + o1.dy * f1);
        path.addOval(Rect.fromCircle(center: offset, radius: radius));
        distance += stepLength;
      }
      startDistance = distance < totalDistance
          ? stepLength - (totalDistance - distance)
          : distance - totalDistance;
    }
    path.addOval(Rect.fromCircle(center: offsets.last, radius: radius));
  }

  void _paintDashedLine(
    ui.Path path,
    List<Offset> offsets,
    double strokeWidth,
    double dashLength,
    double dashGap,
    double zoom,
  ) {
    final double normalizedDashGap = dashGap * strokeWidth;
    for (var i = 0; i < offsets.length - 1; i++) {
      _paintDashedSegment(
        path,
        offsets[i],
        offsets[i + 1],
        strokeWidth,
        dashLength,
        normalizedDashGap,
      );
    }
  }

  void _paintDashedSegment(
    ui.Path path,
    Offset start,
    Offset end,
    double strokeWidth,
    double dashLength,
    double normalizedDashGap,
  ) {
    final distance = (end - start).distance;
    if (distance <= strokeWidth) {
      return;
    }

    final dashCount = (distance / (dashLength + normalizedDashGap)).floor();
    if (dashCount == 0) {
      return;
    }

    final dashSpace = distance / dashCount - dashLength;
    final halfWidth = strokeWidth / 2;
    final angle = atan2(end.dy - start.dy, end.dx - start.dx);

    final startPoint = Offset(start.dx + halfWidth * cos(angle), start.dy + halfWidth * sin(angle));
    final endPoint = Offset(end.dx - halfWidth * cos(angle), end.dy - halfWidth * sin(angle));
    final dashPath = ui.Path();

    for (var i = 0; i < dashCount; i++) {
      final offset = i * (dashLength + dashSpace);
      final startOffset =
          Offset(startPoint.dx + offset * cos(angle), startPoint.dy + offset * sin(angle));
      final endOffset = Offset(
          startOffset.dx + dashLength * cos(angle), startOffset.dy + dashLength * sin(angle));
      dashPath.moveTo(startOffset.dx, startOffset.dy);
      dashPath.lineTo(endOffset.dx, endOffset.dy);
    }

    // add miter join with curved edges
    final joinPath = ui.Path()
      ..moveTo(startPoint.dx, startPoint.dy)
      ..lineTo(endPoint.dx, endPoint.dy);
    path.addPath(joinPath, Offset.zero);

    path.addPath(dashPath, Offset.zero);
  }

  void _paintLine(ui.Path path, List<Offset> offsets) {
    if (offsets.isEmpty) {
      return;
    }
    path.addPolygon(offsets, false);
  }

  ui.Gradient _paintGradient(Polyline polyline, List<Offset> offsets) => ui.Gradient.linear(
      offsets.first, offsets.last, polyline.gradientColors!, _getColorsStop(polyline));

  List<double>? _getColorsStop(Polyline polyline) => (polyline.colorsStop != null &&
          polyline.colorsStop!.length == polyline.gradientColors!.length)
      ? polyline.colorsStop
      : _calculateColorsStop(polyline);

  List<double> _calculateColorsStop(Polyline polyline) {
    final colorsStopInterval = 1.0 / polyline.gradientColors!.length;
    return polyline.gradientColors!
        .map(
            (gradientColor) => polyline.gradientColors!.indexOf(gradientColor) * colorsStopInterval)
        .toList();
  }

  @override
  bool shouldRepaint(PolylinePainter oldDelegate) {
    return kIsWeb ||
        oldDelegate.zoom != zoom ||
        oldDelegate.rotation != rotation ||
        oldDelegate.hash != hash;
  }
}
