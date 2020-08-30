import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';

class TileDownloadLayerOptions extends LayerOptions {
  final Color color;

  final void Function() onComplete;
  String urlTemplate;
  List<String> subdomains;

  final double maxZoom;
  final double minZoom;
  final List<LatLng> points;
  final bool debug;

  TileDownloadLayerOptions({
    this.color,
    this.onComplete,
    this.urlTemplate,
    this.subdomains,
    this.minZoom = 6,
    this.maxZoom = 16,
    this.points,
    this.debug = false
  });
}
