import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_tile_downloader/pill.dart';

import 'package:latlong/latlong.dart';
import 'tile_download_layer_options.dart';

import 'package:flutter_map_tile_downloader/utils/util.dart' as util;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:tuple/tuple.dart';

class TileDownloadLayer extends StatefulWidget {
  final TileDownloadLayerOptions options;
  final MapState map;
  final Stream<void> stream;

  TileDownloadLayer(this.options, this.map, this.stream);

  @override
  _TileDownloadLayerState createState() => _TileDownloadLayerState();
}

class _TileDownloadLayerState extends State<TileDownloadLayer> {

  double _tileZoom;
  Bounds _globalTileRange;
  String _dir;

  double minZoom = 8;
  double maxZoom = 12;
  int screenAreaToDownloadPx = 256;

  List<Widget> markers = [];
  Map<String, Rect> boundingBoxMap  = {};
  Widget boundingBox = Container();
  List<Widget> debugTools = [];

  StreamController<String> streamController;
  String streamValue = "";

  @override
  initState() {
    super.initState();
    streamController = StreamController();
    setState(() {
      minZoom = widget.options.minZoom;
      maxZoom = widget.options.maxZoom;
    });

    generateDebugTools();

    streamController.stream.listen((data) {
      if (mounted)
        setState((){ streamValue = data; });
    }, onDone: () {
      if (mounted)
        setState((){ streamValue = "Complete."; });
    }, onError: (error) {
      if (mounted)
        setState((){ streamValue = "Error: #$error"; });
    });
  }

  @override
  void dispose() {
    streamController.close();
    super.dispose();
  }

  /// TILE QUEUE BUILD /////////////////////////////////////////////////////////
  /// //////////////////////////////////////////////////////////////////////////

  var queue = <TileQueueItem>[];

  List<TileQueueItem> generateQueueForZoom(LatLng latLng, double zoom) {

    List<TileQueueItem> zoomQueue = [];

    setView(zoom);

    var pixelBounds = getBounds(latLng, zoom);
    var tileRange = pxBoundsToTileRange(pixelBounds);

    for (var j = tileRange.min.y; j <= tileRange.max.y; j++) {
      for (var i = tileRange.min.x; i <= tileRange.max.x; i++) {
        var coords = Coords(i.toDouble(), j.toDouble());
        coords.z = _tileZoom;

        if (!isValidTile(coords)) {
          continue;
        }
        // FIXME figure out an optimal way to do this. hash it or summat.
        if (!zoomQueue.any((TileQueueItem element) => element.coords == coords))
        zoomQueue.add(TileQueueItem(coords: coords, latLng: latLng));
      }
    }

    return zoomQueue;
  }

  Future<void> processQueue() async {

    if (queue.isNotEmpty) {
      if (_dir == null) {
        _dir = (await getApplicationDocumentsDirectory()).path;
      }
      streamController.add("Processing queue....");
      await new Directory('$_dir/offline_map').create()
          .then((Directory directory) async {

        for (var i = 0; i < queue.length; i++) {

          TileQueueItem next = queue[i];

          String url = _createTileImage(next.coords);
          await new Directory(
                  '$_dir/offline_map/${next.coords.z.round().toString()}')
              .create()

              .then((Directory directory) async {
            await new Directory(
                    '$_dir/offline_map/${next.coords.z.round().toString()}/${next.coords.x.round().toString()}')
                .create()

                .then((Directory directory) async {
                  streamController.add("Downloading file $i of ${queue.length}");
                  addBoundingBox(next.latLng, next.coords.z.round().toString());
                  await downloadFile(
                    url,
                    '${next.coords.y.round().toString()}.png',
                    '$_dir/offline_map/${next.coords.z.round().toString()}/${next.coords.x.round().toString()}');
            });
          });
        }
      });
    }
  }

  Bounds pxBoundsToTileRange(Bounds bounds) {
    var tileSize = CustomPoint(256.0, 256.0);
    return Bounds(
      bounds.min.unscaleBy(tileSize).floor(),
      bounds.max.unscaleBy(tileSize).ceil() - CustomPoint(1, 1),
    );
  }

  void setView(double zoom) {
    var tileZoom = zoom.round().toDouble();
    if (_tileZoom != tileZoom) {
      _tileZoom = tileZoom;
    }

    var bounds = widget.map.getPixelWorldBounds(_tileZoom);
    if (bounds != null) {
      _globalTileRange = pxBoundsToTileRange(bounds);
    }
  }

  bool isValidTile(Coords coords) {
    var crs = widget.map.options.crs;
    if (!crs.infinite) {
      var bounds = _globalTileRange;
      if ((crs.wrapLng == null &&
              (coords.x < bounds.min.x || coords.x > bounds.max.x)) ||
          (crs.wrapLat == null &&
              (coords.y < bounds.min.y || coords.y > bounds.max.y))) {
        return false;
      }
    }
    return true;
  }

  /// TILE DOWNLOADING /////////////////////////////////////////////////////////
  /// //////////////////////////////////////////////////////////////////////////

  Future<File> downloadFile(String url, String filename, String dir) async {
    var req = await http.Client().get(Uri.parse(url));
    var file = File('$dir/$filename');
    return file.writeAsBytes(req.bodyBytes);
  }

  String getSubdomain(Coords coords, List<String> subdomains) {
    var index = (coords.x + coords.y).round() % subdomains.length;
    return subdomains[index];
  }

  String _createTileImage(Coords coords) {
    var data = <String, String>{
      'x': coords.x.round().toString(),
      'y': coords.y.round().toString(),
      'z': coords.z.round().toString(),
      's': getSubdomain(coords, widget.options.subdomains)
    };

    var allOpts = Map<String, String>.from(data);

    return util.template(widget.options.urlTemplate, allOpts);
  }

  CustomPoint offsetToCustomPoint(Offset offset) {
    return CustomPoint(offset.dx, offset.dy);
  }

  downloadTiles() async {

    await Permission.storage.request();

    bool permissionStorage = await Permission.storage.isGranted;

    if(permissionStorage) {
      queue.clear();
      for (LatLng point in widget.options.points){
        for( var i = minZoom ; i <= maxZoom; i++ ) {
          queue.addAll(generateQueueForZoom(point, i));
        }
      }
      await processQueue();
      streamController.add("Complete.");
      widget.options.onComplete();

      setState(() { boundingBox = Container(); });
    }
  }

  deleteTiles() async {
    if (_dir == null) {
      _dir = (await getApplicationDocumentsDirectory()).path;
    }
    try {
      final dir = Directory("$_dir/offline_map/");
      streamController.add("Destroying tiles...");
      dir.deleteSync(recursive: true);
      streamController.add("Destroyed tiles.");
      DefaultCacheManager manager = new DefaultCacheManager();
      manager.emptyCache();
    } catch (e){
      print("Already cleared");
    }
    setState((){
      boundingBoxMap.clear();
      points.clear();
    });
  }

  var _templateRe = RegExp(r'\{ *([\w_-]+) *\}');

  String template(String str, Map<String, String> data) {
    return str.replaceAllMapped(_templateRe, (Match match) {
      var value = data[match.group(1)];
      if (value == null) {
        throw Exception('No value provided for variable ${match.group(1)}');
      } else {
        return value;
      }
    });
  }

  double wrapNum(double x, Tuple2<double, double> range, [bool includeMax]) {
    var max = range.item2;
    var min = range.item1;
    var d = max - min;
    return x == max && includeMax != null ? x : ((x - min) % d + d) % d + min;
  }

  /// GEO Maths ////////////////////////////////////////////////////////////////
  /// //////////////////////////////////////////////////////////////////////////

  double getZoomScale(double toZoom, double fromZoom) {
    var crs = const Epsg3857();
    return crs.scale(toZoom) / crs.scale(fromZoom);
  }


  Bounds getBounds(LatLng latLng, double zoom) {
    var scale = getZoomScale(zoom, widget.map.zoom);
    double w = screenAreaToDownloadPx / scale;
    double h = screenAreaToDownloadPx / scale;
    Point center = getViewportPointFromLatLng(latLng);

    CustomPoint topLeft     = CustomPoint(center.x - (w * 0.5), center.y - (h * 0.5));
    CustomPoint bottomRight = CustomPoint(center.x + (w * 0.5), center.y + (h * 0.5));

    // add to debug map
    boundingBoxMap["${latLng.toString()}_${zoom.round().toString()}"] = Rect.fromLTRB(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);

    var globalTopLeft = pointToGlobal(topLeft, latLng, zoom);
    var globalBottomRight = pointToGlobal(bottomRight, latLng, zoom);

    return Bounds(globalTopLeft * scale, globalBottomRight * scale);
  }

  Point pointToGlobal(Point point, LatLng center, double zoom){
    var renderObject = context.findRenderObject() as RenderBox;
    var width = renderObject.size.width;
    var height = renderObject.size.height;
    var localPointCenterDistance =
        CustomPoint((width / 2) - point.x, (height / 2) - point.y);
    var mapCenter = widget.map.project(widget.map.center);

    return mapCenter - localPointCenterDistance;
  }

  Point globalToPoint(Point point){
    LatLng latLng = widget.map.unproject(point);
    return getViewportPointFromLatLng(latLng);
  }

  Point getViewportPointFromLatLng(LatLng latLng) {
    CustomPoint<num> northWestPoint = Epsg3857().latLngToPoint(widget.map.bounds.northWest, widget.map.zoom);
    CustomPoint<num> markerPoint = Epsg3857().latLngToPoint(latLng, widget.map.zoom);
    double x = markerPoint.x - northWestPoint.x;
    double y = markerPoint.y - northWestPoint.y;
    return Point(x,y);
  }

  LatLng getLatLngFromViewportPoint(CustomPoint point) {
    return Epsg3857().pointToLatLng(point, widget.map.zoom);
  }

  /// Markers + Debug stuff ////////////////////////////////////////////////////
  /// //////////////////////////////////////////////////////////////////////////

  List<Widget> getMarkers(){
    List<Widget> widgets = [];
    markers.clear();
    for (LatLng point in widget.options.points){
      Point p = getViewportPointFromLatLng(point);
      widgets.add(Positioned(
        top: p.y, left: p.x,
        child: Container(width: 15, height: 15,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.all(Radius.circular(10),),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: Colors.black38, offset: Offset(0.0, 1.0), blurRadius: 2.0)],
            ),
          )
      ));
    }
    return widgets;
  }

  void addBoundingBox(LatLng latLng, String zoom){
    Rect boxRect = boundingBoxMap["${latLng.toString()}_$zoom"];

    setState(() {
      boundingBox = (boxRect == null) ? Container() : Positioned(
      top: boxRect.top, left: boxRect.left,
      child: IgnorePointer(child: Container(width: boxRect.right - boxRect.left, height: boxRect.bottom - boxRect.top,
        decoration: BoxDecoration(border: Border.all(
          width: 1.0,
          color: Colors.white,
        ), color: Colors.white.withOpacity(0.2)),
      )));
    });
  }

  void updateMarkers(){
    setState(() {
      markers = getMarkers();
    });
  }

  List<Widget> points = [];

  void renderPoint(LatLng latLng, double zoom){
    Point point = getViewportPointFromLatLng(latLng);
    setState(() {
      points.add(
        Positioned(
          top: point.y, left: point.x,
          child: Container(width: 15, height: 15,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.all(Radius.circular(10)),
              boxShadow: [BoxShadow(color: Colors.black12, offset: Offset(0.0, 2.0), blurRadius: 10.0)],
            ),
            child: Padding(padding: EdgeInsets.only(top: 2, left: 2), child:
              Text(zoom.floor().toString(), style: TextStyle(fontSize: 9.0, color: Colors.white)
          )))
      ));
    });
  }

  void generateDebugTools() {

    if (widget.options.debug != true) return;

    debugTools.addAll([
      Positioned(top: 50, right: 10,
        child: RaisedButton(child: Text("Reset"), onPressed: () => deleteTiles())
      ),
      Positioned(top: 90, right: 10,
        child: RaisedButton(child: Text("Stahp"), onPressed: () => queue.clear())
      ),

    ]);
  }

  /// Yay Build! ///////////////////////////////////////////////////////////////
  /// //////////////////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {

    updateMarkers();

    return Stack(children: [

      boundingBox,

      Positioned(top: 20, left: 20,
        child: streamValue == "" ? Container() : PillTag(streamValue, color: Colors.black54)
      ),

      Positioned(top: 10, right: 10,
        child: RaisedButton(child: Text("Download"), onPressed: () => downloadTiles())
      ),

      ...debugTools,
      ...points,
      ...markers,
    ]);
  }


}


class TileQueueItem {

  final LatLng latLng;
  final Coords coords;

  TileQueueItem({
    this.coords,
    this.latLng,
  });
}