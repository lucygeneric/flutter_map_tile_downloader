import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_downloader/flutter_map_tile_downloader.dart';
import 'package:path_provider/path_provider.dart';


import 'package:latlong/latlong.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState()  {
    super.initState();
    setup();
  }

  List<LayerOptions> layers = [];
  OfflineTileConfig config;

  bool showOffline = false;

  void setup() async {
    String dir = (await getApplicationDocumentsDirectory()).path;
    config = OfflineTileConfig(minZoom: 6, maxZoom: 16, urlTemplate: "$dir/offline_map/{z}/{x}/{y}.png");
    setState(() { });
  }

  @override
  Widget build(BuildContext context)  {
    List<LatLng> points = [
      LatLng(-36.863361,174.906494),
      LatLng(-36.864600,174.760810),
      LatLng(-36.884632,174.736068),
      LatLng(-36.874265,174.742595),
      LatLng(-36.877012,174.727531),
      LatLng(-36.877424,174.913795)
    ];

    if (config == null) return Container();

    layers.clear();

    if (!showOffline)
      layers.add(TileLayerOptions(
          urlTemplate: "https://api.mapbox.com/styles/v1/ecoportal-developer/ck9apf67102vs1is7uptnulc4/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiZWNvcG9ydGFsLWRldmVsb3BlciIsImEiOiJjazlhcGF1d2owOG9uM21xdXQ1cDZiZDY3In0.mDehRjqNwuGZzH5cO2Fa4g",
          additionalOptions: {
            'accessToken': 'pk.eyJ1IjoiZWNvcG9ydGFsLWRldmVsb3BlciIsImEiOiJjazlhcGF1d2owOG9uM21xdXQ1cDZiZDY3In0.mDehRjqNwuGZzH5cO2Fa4g',
            'id': 'mapbox.streets',
          },
          keepBuffer: 0
        ));

    layers.add(TileDownloadLayerOptions(
        onComplete: () => print("FOOOO"),
        urlTemplate: "https://api.mapbox.com/styles/v1/ecoportal-developer/ck9apf67102vs1is7uptnulc4/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiZWNvcG9ydGFsLWRldmVsb3BlciIsImEiOiJjazlhcGF1d2owOG9uM21xdXQ1cDZiZDY3In0.mDehRjqNwuGZzH5cO2Fa4g",
        subdomains: ['z','x','y'],
        minZoom: config.minZoom,
        maxZoom: config.maxZoom,
        points: points
      ));

    if (showOffline)
      layers.add(TileLayerOptions(
        tileProvider: FileTileProvider(),
        maxZoom: config.maxZoom,
        urlTemplate: config.urlTemplate,
      ));

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Tile downloader example')),
        body: Padding(
          padding: EdgeInsets.zero,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(
                center: LatLng(-36.863361,174.906494),
                zoom: 10.0,
                minZoom: config.minZoom,
                maxZoom: config.maxZoom,
                plugins: [
                  TileDownloaderPlugin()
                ],
              ),
              layers: layers
            ),
            Positioned(child:
              RaisedButton(child: Text("Toggle Offline"), onPressed: () => setState((){ showOffline = !showOffline; })),
              bottom: 20.0, left: 20.0
            )
          ])
        ),
      ),
    );
  }
}
