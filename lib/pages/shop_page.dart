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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Area
              Expanded(
                flex: 4,
                child: Container(
                  margin: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: AppTheme.bgYellow.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(22.r),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20.r),
                    child: product.imagePath.isEmpty
                        ? Icon(
                            Icons.favorite,
                            color: AppTheme.primary.withOpacity(0.3),
                            size: 40.sp,
                          )
                        : ImageUtils.displayImage(
                            product.imagePath,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              ),
              // Info Area
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.sp,
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
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSub,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // Progress Bar
                    Container(
                      height: 8.h,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: progress > 1 ? 1 : progress,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppTheme.primary, AppTheme.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Center(
                      child: Text(
                        isDone ? "达成！去兑换吧" : "${(progress * 100).toInt()}% 进度",
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: isDone ? Colors.green : AppTheme.textSub,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Action Button
              Padding(
                padding: EdgeInsets.all(8.w),
                child: ElevatedButton(
                  onPressed: (isDone && !product.isRedeemed)
                      ? () => controller.redeemProduct(index)
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    backgroundColor:
                        isDone ? Colors.green : Colors.grey.shade200,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade100,
                  ),
                  child: Text(
                    product.isRedeemed ? "奖励已发" : "立刻兑换",
                    style: TextStyle(fontSize: 12.sp),
                  ),
                ),
              ),
            ],
          ),
          if (product.isRedeemed)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(28.r),
                ),
                child: Center(
                  child: RotationTransition(
                    turns: const AlwaysStoppedAnimation(-15 / 360),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: const Text(
                        "COUPON USED",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
