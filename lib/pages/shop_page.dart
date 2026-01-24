import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/shop_controller.dart';
import '../controllers/user_controller.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ShopController shopController = Get.find<ShopController>();
    final UserController userController = Get.find<UserController>();

    return Scaffold(
      backgroundColor: AppTheme.bgYellow,
      appBar: AppBar(
        title: const Text("礼物商店"),
        actions: [
          // 宝宝切换按钮
          Obx(() {
            final baby = userController.currentBaby.value;
            if (baby == null) return const SizedBox();
            return GestureDetector(
              onTap: () => _showBabySwitcher(userController),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(
                  children: [
                    Text(
                      baby.name,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      width: 36.w,
                      height: 36.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
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
                    Icon(Icons.arrow_drop_down, color: AppTheme.textSub),
                  ],
                ),
              ),
            );
          }),
          SizedBox(width: 4.w),
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppTheme.textSub,
            ),
            onPressed: () => _showAddProductDialog(shopController),
          ),
          SizedBox(width: 8.w),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          if (shopController.products.isEmpty) {
            return _buildEmptyState(shopController);
          }
          return GridView.builder(
            padding: EdgeInsets.all(16.w),
            physics: const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16.w,
              mainAxisSpacing: 16.w,
            ),
            itemCount: shopController.products.length,
            itemBuilder: (context, index) {
              final product = shopController.products[index];
              return _buildNiceProductCard(shopController, product, index);
            },
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState(ShopController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.redeem_rounded, size: 80.sp, color: Colors.grey.shade300),
          SizedBox(height: 20.h),
          Text(
            "快去给宝贝添加一些心仪的礼物吧！",
            style: TextStyle(color: Colors.grey.shade600),
          ),
          SizedBox(height: 30.h),
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
            child: Container(
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
          // 兑换按钮
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 4.h, 10.w, 10.h),
            child: SizedBox(
              height: 32.h,
              child: ElevatedButton(
                onPressed:
                    isDone ? () => controller.redeemProduct(index) : null,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: isDone ? Colors.green : Colors.grey.shade200,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                child: Text(
                  isDone ? "立刻兑换" : "努力中...",
                  style: TextStyle(fontSize: 12.sp),
                ),
              ),
            ),
          ),
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

    Get.bottomSheet(
      Container(
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
                      Get.back();
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

  /// 宝宝切换底部弹出选择器
  void _showBabySwitcher(UserController userController) {
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              '切换宝宝',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20.h),
            // 宝宝列表
            Obx(() => Wrap(
                  spacing: 16.w,
                  runSpacing: 16.h,
                  children: userController.babies.map((baby) {
                    final isSelected =
                        userController.currentBaby.value?.id == baby.id;
                    return GestureDetector(
                      onTap: () {
                        userController.switchBaby(baby.id);
                        Get.back();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64.w,
                            height: 64.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B9D),
                                        Color(0xFFFF8E53),
                                        Color(0xFFFFC371),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isSelected ? null : Colors.grey.shade200,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFF6B9D)
                                            .withOpacity(0.4),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Container(
                              margin: EdgeInsets.all(3.w),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: ClipOval(
                                child: ImageUtils.displayImage(
                                  baby.avatarPath,
                                  width: 58.w,
                                  height: 58.w,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            baby.name,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textMain,
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 18.sp),
                        ],
                      ),
                    );
                  }).toList(),
                )),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }
}
