import 'dart:convert';
import 'dart:typed_data';

/// CUBE LUT数据结构
class CubeLut {
  final int size;
  final Float32List data;
  
  CubeLut(this.size, this.data);
}

/// 加载和解析.cube格式的LUT文件
Future<CubeLut> loadCubeLut(ByteData fileData) async {
  final lines = utf8.decode(fileData.buffer.asUint8List()).split(RegExp(r'\r?\n'));
  int size = 0;
  final values = <double>[];

  for (final line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
      continue;
    }

    // 解析LUT_3D_SIZE
    if (trimmedLine.toUpperCase().startsWith('LUT_3D_SIZE')) {
      size = int.parse(trimmedLine.split(RegExp(r'\s+'))[1]);
      continue;
    }

    // 解析RGB数值
    if (RegExp(r'^-?\d').hasMatch(trimmedLine)) {
      final parts = trimmedLine.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        values.add(double.parse(parts[0]));
        values.add(double.parse(parts[1]));
        values.add(double.parse(parts[2]));
      }
    }
  }

  if (size == 0) {
    throw Exception('无法找到LUT_3D_SIZE');
  }

  if (values.length != size * size * size * 3) {
    throw Exception('LUT数据长度不匹配: 期望 ${size * size * size * 3}, 实际 ${values.length}');
  }

  return CubeLut(size, Float32List.fromList(values));
}
