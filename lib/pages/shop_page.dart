import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/shop_controller.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/memphis_widgets.dart';
import '../widgets/module_background_scene.dart';

/// 孟菲斯（Memphis Milano）风格礼物商店页面
class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ShopController shopController = Get.find<ShopController>();
    final UserController userController = Get.find<UserController>();
    final AppModeController modeController = Get.find<AppModeController>();

    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        title: const Text("礼物商店"),
        actions: [
          // 显示当前宝宝星星与头像徽章
          Obx(() {
            final baby = userController.currentBaby.value;
            if (baby == null) return const SizedBox();
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: AppTheme.yellow,
                  borderRadius: BorderRadius.circular(999),
                  border: AppTheme.border(),
                  boxShadow: AppTheme.paperShadow(h: 8.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('⭐', style: TextStyle(fontSize: 14.sp)),
                    SizedBox(width: 4.w),
                    Text(
                      '${baby.starCount}',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      width: 28.w,
                      height: 28.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: AppTheme.border(),
                      ),
                      child: ClipOval(
                        child: ImageUtils.displayImage(
                          baby.avatarPath,
                          width: 26.w,
                          height: 26.w,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(width: 4.w),
          // 添加按钮（儿童模式隐藏）
          Obx(() => modeController.isChildMode
              ? const SizedBox()
              : Padding(
                  padding: EdgeInsets.only(right: 12.w),
                  child: MemphisIconButton(
                    icon: Icons.add_rounded,
                    bgColor: AppTheme.pink,
                    size: 36.w,
                    iconSize: 20.sp,
                    tooltip: '添加礼物',
                    onTap: () => _showAddProductDialog(shopController),
                  ),
                )),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(theme: ModuleBackgroundTheme.shop),
          ),
          SafeArea(
            child: Obx(() {
              if (shopController.products.isEmpty) {
                return _buildEmptyState(shopController);
              }

              final activeProducts = <Product>[];
              final redeemedProducts = <Product>[];
              for (int i = 0; i < shopController.products.length; i++) {
                final product = shopController.products[i];
                if (product.isRedeemed) {
                  redeemedProducts.add(product);
                } else {
                  activeProducts.add(product);
                }
              }

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (activeProducts.isNotEmpty) ...[
                      _buildSectionHeader(
                        '🎯 心愿清单',
                        '${activeProducts.length}件',
                        AppTheme.yellow,
                      ),
                      SizedBox(height: 14.h),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.67,
                          crossAxisSpacing: 14.w,
                          mainAxisSpacing: 14.w,
                        ),
                        itemCount: activeProducts.length,
                        itemBuilder: (context, index) {
                          final product = activeProducts[index];
                          final originalIndex =
                              shopController.products.indexOf(product);
                          return _buildNiceProductCard(shopController, product,
                              originalIndex, modeController);
                        },
                      ),
                    ],
                    if (redeemedProducts.isNotEmpty) ...[
                      SizedBox(height: 26.h),
                      _buildSectionHeader(
                        '✅ 已兑换',
                        '${redeemedProducts.length}件',
                        AppTheme.teal,
                      ),
                      SizedBox(height: 14.h),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.74,
                          crossAxisSpacing: 14.w,
                          mainAxisSpacing: 14.w,
                        ),
                        itemCount: redeemedProducts.length,
                        itemBuilder: (context, index) {
                          final product = redeemedProducts[index];
                          return _buildRedeemedProductCard(product);
                        },
                      ),
                    ],
                    SizedBox(height: 20.h),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String count, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12.r),
            border: AppTheme.border(),
            boxShadow: AppTheme.paperShadow(h: 8.0),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.ink,
            ),
          ),
        ),
        SizedBox(width: 10.w),
        MemphisTag(
          text: count,
          color: Colors.white,
          tiltDeg: -5.0,
          fontSize: 11.5.sp,
        ),
      ],
    );
  }

  Widget _buildEmptyState(ShopController controller) {
    final modeController = Get.find<AppModeController>();
    return Center(
      child: MemphisCard(
        margin: EdgeInsets.symmetric(horizontal: 32.w),
        padding: EdgeInsets.all(28.w),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76.w,
              height: 76.w,
              decoration: BoxDecoration(
                color: AppTheme.yellow,
                shape: BoxShape.circle,
                border: AppTheme.border(),
                boxShadow: AppTheme.paperShadow(h: 8.0),
              ),
              child: Center(
                child: Text('🎁', style: TextStyle(fontSize: 38.sp)),
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              modeController.isChildMode ? "暂时没有礼物哦~" : "快去给宝贝添加一些心仪的礼物吧！",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!modeController.isChildMode) ...[
              SizedBox(height: 20.h),
              MemphisButton(
                text: "＋ 添加第一件礼物",
                color: AppTheme.pink,
                onTap: () => _showAddProductDialog(controller),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建孟菲斯风格商品卡片（粗黑边 + 硬投影 + 歪斜价格贴纸）
  Widget _buildNiceProductCard(
    ShopController controller,
    Product product,
    int index,
    AppModeController modeController,
  ) {
    final progress = controller.getProgress(product);
    final isDone = progress >= 1.0;

    if (product.isRedeemed) {
      return _buildRedeemedProductCard(product);
    }

    final placeholderBg =
        AppTheme.candySoftColors[index % AppTheme.candySoftColors.length];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图片区域
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Container(
                  margin: EdgeInsets.all(9.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.r),
                    color: placeholderBg,
                    border: AppTheme.border(),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: product.imagePath.isEmpty
                        ? Center(
                            child: Text(
                              '🎁',
                              style: TextStyle(fontSize: 46.sp),
                            ),
                          )
                        : ImageUtils.displayImage(
                            product.imagePath,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                  ),
                ),
                // 左上角孟菲斯歪斜价格贴纸（规则 04：歪贴纸，但内部数字清晰）
                Positioned(
                  top: 14.h,
                  left: 14.w,
                  child: MemphisTag(
                    text:
                        '${product.priceType == 'star' ? '⭐' : '¥'} ${product.price.toInt()}',
                    color: AppTheme.yellow,
                    tiltDeg: -5.0,
                    fontSize: 11.sp,
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    shadowOffset: 2.5,
                  ),
                ),
                // 编辑和删除按钮
                Obx(() => !modeController.isChildMode
                    ? Positioned(
                        top: 13.h,
                        right: 13.w,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  _showEditProductDialog(controller, product),
                              child: Container(
                                padding: EdgeInsets.all(5.w),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: AppTheme.border(),
                                ),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 14.sp,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                            SizedBox(width: 5.w),
                            GestureDetector(
                              onTap: () =>
                                  _confirmDeleteProduct(controller, product),
                              child: Container(
                                padding: EdgeInsets.all(5.w),
                                decoration: BoxDecoration(
                                  color: AppTheme.tomatoSoft,
                                  shape: BoxShape.circle,
                                  border: AppTheme.border(),
                                ),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 14.sp,
                                  color: AppTheme.tomato,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
          // 信息区域（保持水平左对齐）
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 4.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.sp,
                    color: AppTheme.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Text(
                      isDone ? '🎉 已攒够！' : '进度',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textSub,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "${(progress * 100).toInt()}%",
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 5.h),
                // 孟菲斯黑边纯色进度条（不用渐变）
                Container(
                  height: 9.h,
                  decoration: BoxDecoration(
                    color: AppTheme.cream,
                    borderRadius: BorderRadius.circular(999),
                    border: AppTheme.border(),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: FractionallySizedBox(
                      widthFactor: (progress > 1 ? 1.0 : progress).clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        color: isDone ? AppTheme.teal : AppTheme.pink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 兑换按钮
          Obx(() => Padding(
                padding: EdgeInsets.fromLTRB(10.w, 6.h, 10.w, 10.h),
                child: MemphisButton(
                  text: modeController.isChildMode
                      ? "👀 仅供查看"
                      : (isDone ? "🎁 立刻兑换" : "努力积攒中..."),
                  color: isDone && !modeController.isChildMode
                      ? AppTheme.teal
                      : AppTheme.cream,
                  borderRadius: 11.r,
                  shadowOffset:
                      isDone && !modeController.isChildMode ? 3.0 : 0.0,
                  fontSize: 12.sp,
                  padding: EdgeInsets.symmetric(vertical: 6.h),
                  onTap: isDone && !modeController.isChildMode
                      ? () => controller.redeemProduct(index)
                      : null,
                ),
              )),
        ],
      ),
    );
  }

  /// 已兑换商品卡片
  Widget _buildRedeemedProductCard(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(20.r),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              margin: EdgeInsets.all(9.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.r),
                color: Colors.white,
                border: AppTheme.border(),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.grey,
                    BlendMode.saturation,
                  ),
                  child: product.imagePath.isEmpty
                      ? Center(
                          child: Text(
                            '🎁',
                            style: TextStyle(fontSize: 44.sp),
                          ),
                        )
                      : ImageUtils.displayImage(
                          product.imagePath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5.sp,
                    color: AppTheme.textSub,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Text(
                  "${product.priceType == 'star' ? '⭐' : '¥'} ${product.price.toInt()}",
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSub,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 4.h, 10.w, 10.h),
            child: Container(
              height: 30.h,
              decoration: BoxDecoration(
                color: AppTheme.tealSoft,
                borderRadius: BorderRadius.circular(10.r),
                border: AppTheme.border(),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14.sp,
                      color: AppTheme.ink,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      "已兑换",
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog(ShopController controller) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final RxString pType = 'star'.obs;
    final Rx<String?> selectedImage = Rx<String?>(null);

    final context = Get.context;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 22.w,
          right: 22.w,
          top: 22.h,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22.h,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          border: AppTheme.border(),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "🎁 添加心愿礼物",
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 18.h),
              GestureDetector(
                onTap: () async {
                  final img = await ImageUtils.pickImageAndToBase64();
                  if (img != null) selectedImage.value = img;
                },
                child: Obx(
                  () => Container(
                    width: 96.w,
                    height: 96.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: 8.0),
                    ),
                    child: selectedImage.value != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14.r),
                            child: ImageUtils.displayImage(selectedImage.value),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_rounded,
                                color: AppTheme.ink,
                                size: 28.sp,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                "上传图片",
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: AppTheme.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                decoration: const InputDecoration(
                  labelText: "或直接输入图片链接",
                  prefixIcon: Icon(Icons.link),
                ),
                style: TextStyle(fontSize: 12.sp),
                onChanged: (val) {
                  if (val.isNotEmpty) selectedImage.value = val;
                },
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "礼物名称"),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "目标数额 (星星/零花钱)"),
              ),
              SizedBox(height: 14.h),
              Obx(
                () => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "兑换类型: ",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    ChoiceChip(
                      label: const Text("⭐ 星星"),
                      selected: pType.value == 'star',
                      onSelected: (s) => pType.value = 'star',
                    ),
                    SizedBox(width: 10.w),
                    ChoiceChip(
                      label: const Text("💰 零花钱"),
                      selected: pType.value == 'money',
                      onSelected: (s) => pType.value = 'money',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 22.h),
              SizedBox(
                width: double.infinity,
                child: MemphisButton(
                  text: "确认添加心愿",
                  color: AppTheme.yellow,
                  onTap: () {
                    if (nameController.text.isNotEmpty &&
                        priceController.text.isNotEmpty) {
                      controller.addProduct(
                        Product(
                          name: nameController.text,
                          price: double.tryParse(priceController.text) ?? 50,
                          priceType: pType.value,
                          imagePath: selectedImage.value ?? '',
                        ),
                      );
                      Navigator.of(ctx).pop();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑商品对话框
  void _showEditProductDialog(ShopController controller, Product product) {
    final nameController = TextEditingController(text: product.name);
    final priceController =
        TextEditingController(text: product.price.toString());
    final Rx<String> pType = product.priceType.obs;
    final Rx<String?> selectedImage = Rx<String?>(product.imagePath);

    final context = Get.context;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 22.w,
          right: 22.w,
          top: 22.h,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22.h,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          border: AppTheme.border(),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "编辑商品",
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 18.h),
              GestureDetector(
                onTap: () async {
                  final img = await ImageUtils.pickImageAndToBase64();
                  if (img != null) selectedImage.value = img;
                },
                child: Obx(
                  () => Container(
                    width: 96.w,
                    height: 96.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: 8.0),
                    ),
                    child: selectedImage.value != null &&
                            selectedImage.value!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14.r),
                            child: ImageUtils.displayImage(selectedImage.value),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_rounded,
                                color: AppTheme.ink,
                                size: 28.sp,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                "上传图片",
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: AppTheme.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                decoration: const InputDecoration(
                  labelText: "或直接输入图片链接",
                  prefixIcon: Icon(Icons.link),
                ),
                style: TextStyle(fontSize: 12.sp),
                controller: TextEditingController(text: selectedImage.value),
                onChanged: (val) {
                  if (val.isNotEmpty) selectedImage.value = val;
                },
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "礼物名称"),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "目标数额 (星星/零花钱)"),
              ),
              SizedBox(height: 14.h),
              Obx(
                () => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "兑换类型: ",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    ChoiceChip(
                      label: const Text("⭐ 星星"),
                      selected: pType.value == 'star',
                      onSelected: (s) => pType.value = 'star',
                    ),
                    SizedBox(width: 10.w),
                    ChoiceChip(
                      label: const Text("💰 零花钱"),
                      selected: pType.value == 'money',
                      onSelected: (s) => pType.value = 'money',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 22.h),
              SizedBox(
                width: double.infinity,
                child: MemphisButton(
                  text: "保存修改",
                  color: AppTheme.teal,
                  onTap: () {
                    if (nameController.text.isNotEmpty &&
                        priceController.text.isNotEmpty) {
                      product.name = nameController.text;
                      product.price = double.tryParse(priceController.text) ??
                          product.price;
                      product.priceType = pType.value;
                      product.imagePath = selectedImage.value ?? '';

                      controller.updateProduct(product);
                      Navigator.of(ctx).pop();
                      Get.snackbar('成功', '商品信息已更新');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除商品确认对话框
  void _confirmDeleteProduct(ShopController controller, Product product) {
    Get.dialog(
      AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除商品 "${product.name}" 吗?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              controller.deleteProduct(product);
              Get.back();
              Get.snackbar('成功', '商品已删除');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.tomato),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
