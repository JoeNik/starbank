import 'dart:io';

// 简单的图片压缩脚本
void main() {
  final directory = Directory('assets/images/story');
  if (!directory.existsSync()) {
    print('目录不存在: ${directory.path}');
    return;
  }

  print('开始检查图片...');
  final files = directory.listSync().whereType<File>().toList();

  for (var file in files) {
    // 简单检查大小，实际压缩通常需要引入 image 库或者使用外部工具如 ffmpeg/magick
    // 这里我们只是输出建议，或者如果环境支持可以调用外部命令
    final sizeMB = file.lengthSync() / (1024 * 1024);
    print(
        '图片: ${file.path.split(Platform.pathSeparator).last}, 大小: ${sizeMB.toStringAsFixed(2)} MB');

    if (sizeMB > 0.5) {
      print('Warning: 图片过大，建议压缩到 500KB 以下');
    }
  }
}
