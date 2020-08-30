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
  List<Widget> boundingBoxes  = [];
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

  Bounds _pxBoundsToTileRange(Bounds bounds) {
    var tileSize = CustomPoint(256.0, 256.0);
    return Bounds(
      bounds.min.unscaleBy(tileSize).floor(),
      bounds.max.unscaleBy(tileSize).ceil() - CustomPoint(1, 1),
    );
  }

  void _setView(double zoom) {
    var tileZoom = zoom.round().toDouble();
    if (_tileZoom != tileZoom) {
      _tileZoom = tileZoom;
    }

    var bounds = widget.map.getPixelWorldBounds(_tileZoom);
    if (bounds != null) {
      _globalTileRange = _pxBoundsToTileRange(bounds);
    }
  }

  bool _isValidTile(Coords coords) {
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

  Future<File> moveFile(File sourceFile, String newPath) async {
    try {
      // prefer using rename as it is probably faster
      return await sourceFile.rename(newPath);
    } on FileSystemException catch (e){
      // if rename fails, copy the source file and then delete it
      final newFile = await sourceFile.copy(newPath);
      await sourceFile.delete();
      return newFile;
    }
  }

  double getZoomScale(double toZoom, double fromZoom) {
    var crs = const Epsg3857();
    return crs.scale(toZoom) / crs.scale(fromZoom);
  }

  Point getBoxOffset(double scale){
    double boxSizeOffset = ((screenAreaToDownloadPx * 0.5) * scale);
    return Point(boxSizeOffset,boxSizeOffset);
  }

  Future<File> downloadFile(String url, String filename, String dir) async {
    var req = await http.Client().get(Uri.parse(url));
    var file = File('$dir/$filename');
    return file.writeAsBytes(req.bodyBytes);
  }

  var queue = <Coords>[];

  Bounds getBounds(LatLng point, double zoom) {
    var scale = getZoomScale(zoom, widget.map.zoom);
    double w = screenAreaToDownloadPx / scale;
    double h = screenAreaToDownloadPx / scale;
    Point center = getViewportPointFromLatLng(point);

    CustomPoint topLeft     = CustomPoint(center.x - (w * 0.5), center.y - (h * 0.5));
    CustomPoint bottomRight = CustomPoint(center.x + (w * 0.5), center.y + (h * 0.5));

    var globalTopLeft = pointToGlobal(topLeft, point, zoom);
    var globalBottomRight = pointToGlobal(bottomRight, point, zoom);

    addBoundingBox(topLeft, bottomRight, zoom);
    renderPoint(point, zoom);

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

  List<Coords<num>> generateQueueForZoom(LatLng point, double zoom) {

    List<Coords<num>> zoomQueue = [];

    _setView(zoom);

    var pixelBounds = getBounds(point, zoom);
    var tileRange = _pxBoundsToTileRange(pixelBounds);

    for (var j = tileRange.min.y; j <= tileRange.max.y; j++) {
      for (var i = tileRange.min.x; i <= tileRange.max.x; i++) {
        var coords = Coords(i.toDouble(), j.toDouble());
        coords.z = _tileZoom;

        if (!_isValidTile(coords)) {
          continue;
        }
        // FIXME figure out an optimal way to do this. hash it or summat.
        if (!zoomQueue.any((element) => element.x == coords.x && element.y == coords.y))
        zoomQueue.add(coords);
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
          String url = _createTileImage(queue[i]);
          await new Directory(
                  '$_dir/offline_map/${queue[i].z.round().toString()}')
              .create()

              .then((Directory directory) async {
            await new Directory(
                    '$_dir/offline_map/${queue[i].z.round().toString()}/${queue[i].x.round().toString()}')
                .create()

                .then((Directory directory) async {
                  streamController.add("Downloading file $i of ${queue.length}");

                  await downloadFile(
                    url,
                    '${queue[i].y.round().toString()}.png',
                    '$_dir/offline_map/${queue[i].z.round().toString()}/${queue[i].x.round().toString()}');
            });
          });
        }
      });
    }
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

      setState(() {
        boundingBoxes.clear();
      });

      queue.clear();

      for (LatLng point in widget.options.points){

        for( var i = minZoom ; i <= maxZoom; i++ ) {
          queue.addAll(generateQueueForZoom(point, i));
        }
      }

      await processQueue();
      streamController.add("Complete.");
      widget.options.onComplete();
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
      boundingBoxes.clear();
      points.clear();
    });
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

  List<Widget> getMarkers(){
    List<Widget> widgets = [];
    for (LatLng point in widget.options.points){
      Point p = getViewportPointFromLatLng(point);
      widgets.add(Positioned(
        top: p.y, left: p.x,
        child: Container(width: 10, height: 10, color: Colors.blue,)
      ));
    }
    return widgets;
  }

  void addBoundingBox(CustomPoint topLeft, CustomPoint bottomRight, double zoom, { color: Colors.blue }){
    boundingBoxes.add(Positioned(
      top: topLeft.y, left: topLeft.x,
      child: IgnorePointer(child: Container(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y,
        decoration: BoxDecoration(border: Border.all(
          width: 1.0,
          color: color,
        )),
        child: Text("$zoom")
      )
    )));
    setState(() { });
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
      Positioned(top: 20, left: 20,
        child: PillTag(widget.map.zoom.toString(), color: Colors.red)
      ),
      Positioned(top: 10, right: 10,
        child: RaisedButton(child: Text("Download"), onPressed: () => downloadTiles())
      ),
      Positioned(top: 50, right: 10,
        child: RaisedButton(child: Text("Reset"), onPressed: () => deleteTiles())
      ),
      Positioned(top: 90, right: 10,
        child: RaisedButton(child: Text("Stahp"), onPressed: () => queue.clear())
      ),
      Positioned(top: 50, left: 20,
        child: SizedBox(width: 250, child: Text(streamValue, style: TextStyle(fontSize: 10))),
      ),
      Positioned(top: 80, left: 20,
        child: RaisedButton(child: Text("Set Zoom"), onPressed: () => widget.map.move(widget.map.center, 12))
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {

    updateMarkers();
    generateDebugTools();

    return Stack(children: [
      ...debugTools,
      ...markers,
      ...boundingBoxes,
      ...points
    ]);
  }


}
