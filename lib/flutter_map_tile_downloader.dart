library flutter_map_tile_downloader;

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
export 'tileDownloader/tile_download_layer.dart';
export 'tileDownloader/tile_download_layer_options.dart';
export './tile_downloader_plugin.dart';

class OfflineTileConfig {
  final String urlTemplate;
  final double minZoom;
  final double maxZoom;
  const OfflineTileConfig({
    this.urlTemplate = "",
    this.minZoom = 0,
    this.maxZoom = 0,
  });
}

Future<OfflineTileConfig> getOfflineTileData() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return OfflineTileConfig(
    minZoom: prefs.getDouble('offline_min_zoom'),
    maxZoom: prefs.getDouble('offline_max_zoom'),
    urlTemplate: prefs.getString('offline_template_url'),
  );
}
