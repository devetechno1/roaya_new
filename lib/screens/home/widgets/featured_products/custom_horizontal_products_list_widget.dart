import 'package:active_ecommerce_cms_demo_app/constants/app_dimensions.dart';
import 'package:active_ecommerce_cms_demo_app/custom/featured_products/product_horizontal_list_widget.dart';
import 'package:flutter/material.dart';
import 'package:active_ecommerce_cms_demo_app/data_model/product_mini_response.dart';

class CustomHorizontalProductsListSectionWidget extends StatelessWidget {
  const CustomHorizontalProductsListSectionWidget({
    super.key,
    required this.title,
    required this.isProductInitial,
    required this.productList,
    required this.numberOfTotalProducts,
    required this.onArriveTheEndOfList,
    this.priceTextStyle,
    this.nameTextStyle,
  });

  final String title;
  final bool isProductInitial;
  final List<Product> productList;

  final int numberOfTotalProducts;
  final void Function() onArriveTheEndOfList;
  final TextStyle? priceTextStyle;
  final TextStyle? nameTextStyle;
  @override
  Widget build(BuildContext context) {
    if (!isProductInitial && productList.isEmpty) return const SizedBox();
    return Container(
      height: 305,
      width: double.maxFinite,
      margin:
          const EdgeInsets.only(top: AppDimensions.paddingSupSmall, bottom: 5),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              top: 20,
              start: 20,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xff000000),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: ProductHorizontalListWidget(
              isProductInitial: isProductInitial,
              productList: productList,
              numberOfTotalProducts: numberOfTotalProducts,
              onArriveTheEndOfList: onArriveTheEndOfList,
              nameTextStyle: nameTextStyle,
              priceTextStyle: priceTextStyle,
            ),
          ),
        ],
      ),
    );
  }
}
