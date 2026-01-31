import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';

/// 统一的 Toast 提示工具类 (玻璃态风格)
class ToastUtils {
  static void showSuccess(String message,
      {String title = '成功', TextButton? mainButton}) {
    _show(title, message, Icons.check_circle_outline, Colors.green,
        mainButton: mainButton);
  }

  static void showError(String message,
      {String title = '错误', TextButton? mainButton}) {
    _show(title, message, Icons.error_outline, Colors.red,
        mainButton: mainButton);
  }

  static void showInfo(String message,
      {String title = '提示', TextButton? mainButton}) {
    _show(title, message, Icons.info_outline, Colors.blueAccent,
        mainButton: mainButton);
  }

  static void showWarning(String message,
      {String title = '注意', TextButton? mainButton}) {
    _show(title, message, Icons.warning_amber_rounded, Colors.orange,
        mainButton: mainButton);
  }

  static void _show(String title, String message, IconData icon, Color color,
      {TextButton? mainButton}) {
    if (Get.isSnackbarOpen) {
      // 可选: 关闭当前正在显示的，防止堆叠过多
      // Get.closeAllSnackbars();
    }

    Get.snackbar(
      title, // title (被 titleText 覆盖，但保留作为 key)
      message, // message (被 messageText 覆盖)
      titleText: Text(
        title,
        style: TextStyle(
          color: const Color(0xFF333333),
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
          fontFamily: 'MiSans',
        ),
      ),
      messageText: Text(
        message,
        style: TextStyle(
          color: const Color(0xFF666666),
          fontSize: 13.sp,
          fontFamily: 'MiSans',
        ),
      ),
      icon: Container(
        margin: EdgeInsets.only(left: 8.w),
        child: Icon(icon, color: color, size: 28.sp),
      ),
      mainButton: mainButton,
      shouldIconPulse: false, // 禁止图标跳动动画
      snackPosition: SnackPosition.TOP, // 统一顶部弹出
      margin: EdgeInsets.only(top: 10.h, left: 16.w, right: 16.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      borderRadius: 16.r,
      backgroundColor: Colors.white.withOpacity(0.65), // 高透明度
      barBlur: 20.0, // 玻璃模糊
      overlayBlur: 0.0, // 背景不模糊
      colorText: Colors.black87,
      boxShadows: [
        BoxShadow(
          color: color.withOpacity(0.25),
          offset: const Offset(0, 8),
          blurRadius: 16,
          spreadRadius: -4, // 柔和的彩色投影
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          offset: const Offset(0, 4),
          blurRadius: 8,
        ),
      ],
      animationDuration: const Duration(milliseconds: 400),
      duration: const Duration(seconds: 3),
      isDismissible: true,
      dismissDirection: DismissDirection.horizontal,
      forwardAnimationCurve: Curves.easeOutCubic,
    );
  }
}
