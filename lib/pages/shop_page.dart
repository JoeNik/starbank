import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/shop_controller.dart';
import '../controllers/user_controller.dart';
// 引入 AppModeController
import '../controllers/app_mode_controller.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/module_background_scene.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ShopController shopController = Get.find<ShopController>();
    final UserController userController = Get.find<UserController>();
    // 获取模式控制器
    final AppModeController modeController = Get.find<AppModeController>();

    return Scaffold(
      backgroundColor: AppTheme.bgYellow,
      appBar: AppBar(
        title: const Text("礼物商店"),
        actions: [
          // 显示当前宝宝信息（只读，不可切换）
          Obx(() {
            final baby = userController.currentBaby.value;
            if (baby == null) return const SizedBox();
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Row(
                children: [
                  // 星星数量
                  Text(
                    '${baby.starCount}',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // 头像
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary, width: 2),
                    ),
                    child: ClipOval(
                      child: ImageUtils.displayImage(
                        baby.avatarPath,
                        width: 36.w,
                        height: 36.w,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          SizedBox(width: 4.w),
          // 添加按钮（儿童模式隐藏）
          Obx(() => modeController.isChildMode
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppTheme.textSub,
                  ),
                  onPressed: () => _showAddProductDialog(shopController),
                )),
          SizedBox(width: 8.w),
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

              // 分离未兑换和已兑换商品
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
                    // 心愿商品
                    if (activeProducts.isNotEmpty) ...[
                      _buildSectionHeader(
                        '🎯 心愿清单',
                        '${activeProducts.length}件',
                      ),
                      SizedBox(height: 12.h),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.68, // 更大的图片
                          crossAxisSpacing: 12.w,
                          mainAxisSpacing: 12.w,
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
                    // 已兑换商品
                    if (redeemedProducts.isNotEmpty) ...[
                      SizedBox(height: 24.h),
                      _buildSectionHeader(
                        '✅ 已兑换',
                        '${redeemedProducts.length}件',
                      ),
                      SizedBox(height: 12.h),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 12.w,
                          mainAxisSpacing: 12.w,
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

  Widget _buildSectionHeader(String title, String count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMain,
          ),
        ),
        SizedBox(width: 8.w),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Text(
            count,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ShopController controller) {
    final modeController = Get.find<AppModeController>();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.redeem_rounded, size: 80.sp, color: Colors.grey.shade300),
          SizedBox(height: 20.h),
          Text(
            modeController.isChildMode ? "暂时没有礼物哦~" : "快去给宝贝添加一些心仪的礼物吧！",
            style: TextStyle(color: Colors.grey.shade600),
          ),
          SizedBox(height: 30.h),
          // 儿童模式隐藏添加按钮
          if (!modeController.isChildMode)
            ElevatedButton(
              onPressed: () => _showAddProductDialog(controller),
              child: const Text("添加第一件礼物"),
            ),
        ],
      ),
    );
  }

  Widget _buildNiceProductCard(
    ShopController controller,
    Product product,
    int index,
    AppModeController modeController,
  ) {
    final progress = controller.getProgress(product);
    final isDone = progress >= 1.0;

    // 已兑换商品单独样式
    if (product.isRedeemed) {
      return _buildRedeemedProductCard(product);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图片区域 - 增大显示
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Container(
                  margin: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18.r),
                    gradient: product.imagePath.isEmpty
                        ? LinearGradient(
                            colors: [
                              Colors.pink.shade100,
                              Colors.orange.shade100,
                              Colors.amber.shade100,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: product.imagePath.isNotEmpty
                        ? AppTheme.bgYellow.withOpacity(0.3)
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18.r),
                    child: product.imagePath.isEmpty
                        ? Center(
                            child: Text(
                              '🎁',
                              style: TextStyle(fontSize: 48.sp),
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
                // 编辑和删除按钮 - 使用 Obx 包裹以响应模式变化
                Obx(() => !modeController.isChildMode
                    ? Positioned(
                        top: 14.h,
                        right: 14.w,
                        child: Row(
                          children: [
                            // 编辑按钮
                            GestureDetector(
                              onTap: () =>
                                  _showEditProductDialog(controller, product),
                              child: Container(
                                padding: EdgeInsets.all(6.w),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 16.sp,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            SizedBox(width: 6.w),
                            // 删除按钮
                            GestureDetector(
                              onTap: () =>
                                  _confirmDeleteProduct(controller, product),
                              child: Container(
                                padding: EdgeInsets.all(6.w),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  size: 16.sp,
                                  color: Colors.red,
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
          // 信息区域
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.sp,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(
                      product.priceType == 'star'
                          ? Icons.stars
                          : Icons.monetization_on,
                      size: 14.sp,
                      color: product.priceType == 'star'
                          ? Colors.amber
                          : Colors.orange,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      "${product.price.toInt()}",
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSub,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "${(progress * 100).toInt()}%",
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        color: isDone ? Colors.green : AppTheme.textSub,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                // 进度条
                Container(
                  height: 6.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(3.r),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: progress > 1 ? 1 : progress,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDone
                              ? [Colors.green, Colors.teal]
                              : [AppTheme.primary, AppTheme.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(3.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 兑换按钮 - 使用 Obx 包裹以响应模式变化
          Obx(() => Padding(
                padding: EdgeInsets.fromLTRB(10.w, 4.h, 10.w, 10.h),
                child: SizedBox(
                  height: 32.h,
                  child: ElevatedButton(
                    // 只有在非儿童模式且进度达到100%时才可点击
                    onPressed: isDone && !modeController.isChildMode
                        ? () {
                            controller.redeemProduct(index);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: isDone && !modeController.isChildMode
                          ? Colors.green
                          : Colors.grey.shade200,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: Text(
                      modeController.isChildMode
                          ? "仅供查看"
                          : (isDone ? "立刻兑换" : "努力中..."),
                      style: TextStyle(fontSize: 12.sp),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// 已兑换商品卡片 - 单独展示
  Widget _buildRedeemedProductCard(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图片区域
              Expanded(
                flex: 5,
                child: Container(
                  margin: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18.r),
                    color: Colors.grey.shade100,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18.r),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.grey,
                        BlendMode.saturation,
                      ),
                      child: product.imagePath.isEmpty
                          ? Center(
                              child: Text(
                                '🎁',
                                style: TextStyle(fontSize: 48.sp),
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
              // 信息区域
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(
                          product.priceType == 'star'
                              ? Icons.stars
                              : Icons.monetization_on,
                          size: 14.sp,
                          color: Colors.grey.shade400,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          "${product.price.toInt()}",
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 已兑换标签
              Padding(
                padding: EdgeInsets.fromLTRB(10.w, 4.h, 10.w, 10.h),
                child: Container(
                  height: 32.h,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14.sp,
                          color: Colors.green,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          "已兑换",
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog(ShopController controller) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    String pType = 'star';

    // Reactive variable for the image
    final Rx<String?> selectedImage = Rx<String?>(null);

    // 使用原生 showModalBottomSheet 替代 Get.bottomSheet
    final context = Get.context;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "添加心愿礼物",
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 20.h),

              // Image Picker
              GestureDetector(
                onTap: () async {
                  final img = await ImageUtils.pickImageAndToBase64();
                  if (img != null) selectedImage.value = img;
                },
                child: Obx(
                  () => Container(
                    width: 100.w,
                    height: 100.w,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: selectedImage.value != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16.r),
                            child: ImageUtils.displayImage(selectedImage.value),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo,
                                color: Colors.grey.shade400,
                                size: 30.sp,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                "传图",
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                decoration: InputDecoration(
                  labelText: "或直接输入图片链接",
                  prefixIcon: const Icon(Icons.link),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 5.h,
                  ),
                ),
                style: TextStyle(fontSize: 12.sp),
                onChanged: (val) {
                  if (val.isNotEmpty) selectedImage.value = val;
                },
              ),
              SizedBox(height: 20.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "礼物名称"),
              ),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "目标数额 (星星/零花钱)"),
              ),
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("兑换类型: "),
                  ChoiceChip(
                    label: const Text("星星"),
                    selected: pType == 'star',
                    onSelected: (s) => pType = 'star',
                  ),
                  SizedBox(width: 10.w),
                  ChoiceChip(
                    label: const Text("零花钱"),
                    selected: pType == 'money',
                    onSelected: (s) => pType = 'money',
                  ),
                ],
              ),
              SizedBox(height: 30.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty &&
                        priceController.text.isNotEmpty) {
                      controller.addProduct(
                        Product(
                          name: nameController.text,
                          price: double.tryParse(priceController.text) ?? 50,
                          priceType: pType,
                          imagePath: selectedImage.value ?? '',
                        ),
                      );
                      // 使用 Navigator.pop 替代 Get.back
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text("添加心愿"),
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

    // Reactive variable for the image
    final Rx<String?> selectedImage = Rx<String?>(product.imagePath);

    // 使用原生 showModalBottomSheet
    final context = Get.context;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "编辑商品",
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 20.h),

              // Image Picker
              GestureDetector(
                onTap: () async {
                  final img = await ImageUtils.pickImageAndToBase64();
                  if (img != null) selectedImage.value = img;
                },
                child: Obx(
                  () => Container(
                    width: 100.w,
                    height: 100.w,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: selectedImage.value != null &&
                            selectedImage.value!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16.r),
                            child: ImageUtils.displayImage(selectedImage.value),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo,
                                color: Colors.grey.shade400,
                                size: 30.sp,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                "传图",
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                decoration: InputDecoration(
                  labelText: "或直接输入图片链接",
                  prefixIcon: const Icon(Icons.link),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 5.h,
                  ),
                ),
                style: TextStyle(fontSize: 12.sp),
                controller: TextEditingController(text: selectedImage.value),
                onChanged: (val) {
                  if (val.isNotEmpty) selectedImage.value = val;
                },
              ),
              SizedBox(height: 20.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "礼物名称"),
              ),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "目标数额 (星星/零花钱)"),
              ),
              SizedBox(height: 16.h),
              Obx(
                () => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("兑换类型: "),
                    ChoiceChip(
                      label: const Text("星星"),
                      selected: pType.value == 'star',
                      onSelected: (s) => pType.value = 'star',
                    ),
                    SizedBox(width: 10.w),
                    ChoiceChip(
                      label: const Text("零花钱"),
                      selected: pType.value == 'money',
                      onSelected: (s) => pType.value = 'money',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 30.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty &&
                        priceController.text.isNotEmpty) {
                      // 更新商品信息
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
                  child: const Text("保存修改"),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
