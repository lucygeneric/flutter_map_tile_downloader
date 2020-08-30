import 'package:flutter/material.dart';

class PillTag extends StatelessWidget {
  final String text;
  final Color color;
  final double sizeOverride;
  final int alphaOverride;

  PillTag(this.text, {
    Key key,
    this.color,
    this.sizeOverride,
    this.alphaOverride,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var color = this.color ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.all(5.0),
      constraints: BoxConstraints(maxWidth: sizeOverride != null ? sizeOverride : 200),
      decoration: BoxDecoration(
        color: color.withAlpha(alphaOverride != null ? alphaOverride : 50),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: alphaOverride != null && alphaOverride > 155 ? Colors.white : color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
