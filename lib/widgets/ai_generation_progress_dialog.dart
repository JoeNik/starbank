import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

/// AI 生成进度对话框
/// 用于展示 AI 生成过程的详细步骤和结果
class AIGenerationProgressDialog extends StatelessWidget {
  final RxList<GenerationStep> steps;
  final VoidCallback? onClose;

  const AIGenerationProgressDialog({
    Key? key,
    required this.steps,
    this.onClose,
  }) : super(key: key);

  /// 显示对话框
  static void show({
    required RxList<GenerationStep> steps,
    VoidCallback? onClose,
  }) {
    Get.dialog(
      AIGenerationProgressDialog(steps: steps, onClose: onClose),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: 600.h,
          maxWidth: 500.w,
        ),
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purple, size: 28.sp),
                SizedBox(width: 12.w),
                Text(
                  'AI 生成进度',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Obx(() {
                  final allCompleted =
                      steps.every((s) => s.status.value != StepStatus.running);
                  if (allCompleted && onClose != null) {
                    return IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            ),
            SizedBox(height: 20.h),

            // 步骤列表
            Flexible(
              child: Obx(() => ListView.builder(
                    shrinkWrap: true,
                    itemCount: steps.length,
                    itemBuilder: (context, index) {
                      final step = steps[index];
                      return _buildStepItem(step, index);
                    },
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(GenerationStep step, int index) {
    return Obx(() => Container(
          margin: EdgeInsets.only(bottom: 16.h),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: _getStepColor(step.status.value).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: _getStepColor(step.status.value).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 步骤标题
              Row(
                children: [
                  _buildStatusIcon(step.status.value),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      step.title.value,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (step.status.value == StepStatus.running)
                    SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                            _getStepColor(step.status.value)),
                      ),
                    ),
                ],
              ),

              // 步骤描述
              if (step.description.value.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Text(
                  step.description.value,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],

              // 详细内容
              if (step.details.value.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '详细信息',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.copy, size: 16.sp),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: step.details.value));
                              Get.snackbar(
                                '已复制',
                                '详细信息已复制到剪贴板',
                                snackPosition: SnackPosition.BOTTOM,
                                duration: const Duration(seconds: 1),
                              );
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        step.details.value,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontFamily: 'monospace',
                          color: Colors.black87,
                        ),
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],

              // 错误信息
              if (step.error.value.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          step.error.value,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.red[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ));
  }

  Widget _buildStatusIcon(StepStatus status) {
    switch (status) {
      case StepStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          color: Colors.grey,
          size: 24.sp,
        );
      case StepStatus.running:
        return Icon(
          Icons.autorenew,
          color: Colors.blue,
          size: 24.sp,
        );
      case StepStatus.success:
        return Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 24.sp,
        );
      case StepStatus.error:
        return Icon(
          Icons.error,
          color: Colors.red,
          size: 24.sp,
        );
    }
  }

  Color _getStepColor(StepStatus status) {
    switch (status) {
      case StepStatus.pending:
        return Colors.grey;
      case StepStatus.running:
        return Colors.blue;
      case StepStatus.success:
        return Colors.green;
      case StepStatus.error:
        return Colors.red;
    }
  }
}

/// 生成步骤状态
enum StepStatus {
  pending, // 等待中
  running, // 进行中
  success, // 成功
  error, // 失败
}

/// 生成步骤
class GenerationStep {
  final RxString title;
  final RxString description;
  final RxString details;
  final RxString error;
  final Rx<StepStatus> status;

  GenerationStep({
    required String title,
    String description = '',
    String details = '',
    String error = '',
    StepStatus status = StepStatus.pending,
  })  : title = title.obs,
        description = description.obs,
        details = details.obs,
        error = error.obs,
        status = status.obs;

  /// 更新步骤
  void update({
    String? title,
    String? description,
    String? details,
    String? error,
    StepStatus? status,
  }) {
    if (title != null) this.title.value = title;
    if (description != null) this.description.value = description;
    if (details != null) this.details.value = details;
    if (error != null) this.error.value = error;
    if (status != null) this.status.value = status;
  }

  /// 标记为运行中
  void setRunning({String? description}) {
    status.value = StepStatus.running;
    if (description != null) this.description.value = description;
  }

  /// 标记为成功
  void setSuccess({String? description, String? details}) {
    status.value = StepStatus.success;
    if (description != null) this.description.value = description;
    if (details != null) this.details.value = details;
  }

  /// 标记为失败
  void setError(String error, {String? description}) {
    status.value = StepStatus.error;
    this.error.value = error;
    if (description != null) this.description.value = description;
  }
}
