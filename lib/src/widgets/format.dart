import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class FormatButton extends StatefulWidget {
  const FormatButton({Key? key}) : super(key: key);

  @override
  State<FormatButton> createState() => _FormatButtonState();
}

class _FormatButtonState extends State<FormatButton> {
  @override
  Widget build(BuildContext context) {
    // 仅保留 JPEG（禁用切换）
    return DropdownButton<CompressFormat>(
      icon: const Padding(
        padding: EdgeInsets.only(left: 4.0),
        child: Icon(Icons.image),
      ),
      value: CompressFormat.jpeg,
      items: const [
        DropdownMenuItem<CompressFormat>(
          value: CompressFormat.jpeg,
          child: Text('JPEG/JPG'),
        ),
      ],
      onChanged: null,
    );
  }
}

CompressFormat getCompressFormat() => CompressFormat.jpeg;
