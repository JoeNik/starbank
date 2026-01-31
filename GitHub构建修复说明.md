# GitHub Actions 构建失败修复

## 问题描述

GitHub Actions构建时出现以下错误:
```
Try correcting the name to the name of an existing method, or defining a method named 'toARGB32'.
'android.crop_grid_color': int32(this.cropGridColor?.toARGB32()),
```

以及:
```
Target kernel_snapshot_program failed: Exception
```

## 原因分析

- `image_cropper`包与Flutter 3.27.0存在兼容性问题
- `toARGB32()`方法在Flutter 3.27.0中已被移除
- 所有版本的`image_cropper`(8.0.2、8.1.0等)都存在此问题

## 解决方案

### 暂时禁用image_cropper

由于`image_cropper`与Flutter 3.27.0不兼容,暂时禁用裁剪功能。

**修改文件1**: `pubspec.yaml`

```yaml
# 修改前
image_cropper: ^8.0.2          # 图片裁剪

# 修改后
# image_cropper: ^8.1.0        # 暂时禁用,构建兼容性问题
```

**修改文件2**: `lib/widgets/image_utils.dart`

- 移除`image_cropper`导入
- 禁用裁剪逻辑
- 保留`enableCrop`参数但不生效(保持API兼容)
- 直接返回选择的图片

## 功能影响

### 受影响的功能
- ❌ 添加/编辑宝宝时的头像裁剪功能暂时不可用
- ✅ 图片选择功能正常
- ✅ 图片自动压缩到512x512

### 用户体验
- 选择头像时会直接使用原图(已压缩)
- 建议用户选择方形或接近方形的图片

## 后续计划

1. 等待`image_cropper`发布兼容Flutter 3.27的新版本
2. 或寻找替代的图片裁剪方案
3. 问题解决后恢复裁剪功能

## 相关Issue

- [image_cropper GitHub Issues](https://github.com/hnvn/flutter_image_cropper/issues)
- Flutter 3.27.0中`Color.toARGB32()`被移除

## 测试

提交代码后重新触发GitHub Actions构建应该能成功。
