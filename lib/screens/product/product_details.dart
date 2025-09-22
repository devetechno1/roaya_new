// ignore_for_file: unused_field

import 'dart:async';
import 'dart:math';

import 'package:active_ecommerce_cms_demo_app/helpers/num_ex.dart';
import 'package:animated_text_lerp/animated_text_lerp.dart';
import 'package:badges/badges.dart' as badges;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:active_ecommerce_cms_demo_app/locale/custom_localization.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app_config.dart';
import '../../custom/box_decorations.dart';
import '../../custom/btn.dart';
import '../../custom/device_info.dart';
import '../../custom/error_widget.dart';
import '../../custom/quantity_input.dart';
import '../../custom/toast_component.dart';
import '../../data_model/product_details_response.dart';
import '../../helpers/color_helper.dart';
import '../../helpers/main_helpers.dart';
import '../../helpers/shared_value_helper.dart';
import '../../helpers/shimmer_helper.dart';
import '../../helpers/system_config.dart';
import '../../main.dart';
import '../../my_theme.dart';
import '../../presenter/cart_counter.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/wishlist_repository.dart';
import '../../services/navigation_service.dart';
import '../../ui_elements/mini_product_card.dart';
import '../../ui_elements/top_selling_products_card.dart';
import '../brand_products.dart';
import '../chat/chat.dart';
import '../checkout/cart.dart';
import '../seller_details.dart';
import '../video_description_screen.dart';
import 'product_reviews.dart';
import 'widgets/product_slider_image_widget.dart';
import 'widgets/tappable_icon_widget.dart';
import 'package:one_context/one_context.dart';

class ProductDetails extends StatefulWidget {
  final String slug;

  const ProductDetails({Key? key, required this.slug}) : super(key: key);

  @override
  _ProductDetailsState createState() => _ProductDetailsState();
}

class _ProductDetailsState extends State<ProductDetails>
    with TickerProviderStateMixin {
  bool _showCopied = false;
  String? _appbarPriceString = ". . .";
  int _currentImage = 0;
  final ScrollController _mainScrollController =
      ScrollController(initialScrollOffset: 0.0);
  final ScrollController _colorScrollController = ScrollController();
  final ScrollController _variantScrollController = ScrollController();
  final ScrollController _imageScrollController = ScrollController();
  TextEditingController sellerChatTitleController = TextEditingController();
  TextEditingController sellerChatMessageController = TextEditingController();

  double _scrollPosition = 0.0;

  Animation? _colorTween;
  late AnimationController _ColorAnimationController;
  WebViewController controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..enableZoom(false);
  double? webViewHeight;
  double height = 100;
  bool isExpanded = false;

  final CarouselSliderController _carouselController =
      CarouselSliderController();
  late BuildContext loadingcontext;

  //init values

  bool _isInWishList = false;
  var _productDetailsFetched = false;
  DetailedProduct? _productDetails;
  final _productImageList = [];
  final _colorList = [];
  int _selectedColorIndex = 0;
  final _selectedChoices = [];
  var _choiceString = "";
  String? _variant = "";
  String? _totalPrice = "...";
  double _basePrice = 0;
  var _singlePrice;
  var _singlePriceString;
  int _stock = 0;
  int _quantity = 1;
  int _inCart = 0;
  String? _stock_txt;

  int get _s => _stock.onlyPositive?.toInt() ?? 0;

  int get maxQuantity => min(_s, _productDetails?.maxQty ?? _s);
  int get minQuantity => _productDetails?.minQty ?? 1;

  double get totalBasePrice => _basePrice * _quantity;
  String? error;
  bool get productHasError => error?.trim().isNotEmpty == true;

  T whenItemInCart<T>(T inCart, T notInCart) {
    if (_inCart > 0) {
      return inCart;
    } else {
      return notInCart;
    }
  }

  double opacity = 0;

  final List<dynamic> _relatedProducts = [];
  bool _relatedProductInit = false;
  final List<dynamic> _topProducts = [];
  bool _topProductInit = false;
  bool _isInitialLoadDone = false;
  @override
  void initState() {
    quantityText.text = "$_quantity";
    _ColorAnimationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 0));

    _colorTween = ColorTween(begin: Colors.transparent, end: Colors.white)
        .animate(_ColorAnimationController);

    _mainScrollController.addListener(() {
      _scrollPosition = _mainScrollController.position.pixels;

      if (_mainScrollController.position.userScrollDirection ==
          ScrollDirection.forward) {
        if (100 > _scrollPosition && _scrollPosition > 1) {
          opacity = _scrollPosition / 100;
        }
      }

      if (_mainScrollController.position.userScrollDirection ==
          ScrollDirection.reverse) {
        if (100 > _scrollPosition && _scrollPosition > 1) {
          opacity = _scrollPosition / 100;

          if (100 > _scrollPosition) {
            opacity = 1;
          }
        }
      }

      setState(() {});
    });
    fetchAll();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final Uri? uri = Uri.tryParse(request.url);
            if (uri != null && _isInitialLoadDone) {
              final bool handled = await NavigationService.handleUrls(
                request.url,
                callBackDeepLink: Navigator.of(context).pop,
              );
              if (handled) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            _isInitialLoadDone = true;
            getDescriptionHeight();
          },
          onPageStarted: (url) => _isInitialLoadDone = false,
        ),
      );
    });
  }

  @override
  void dispose() {
    controller.clearCache();
    controller.clearLocalStorage();
    quantityText.dispose();
    _mainScrollController.dispose();
    _variantScrollController.dispose();
    _imageScrollController.dispose();
    _colorScrollController.dispose();
    _ColorAnimationController.dispose();
    super.dispose();
  }

  fetchAll() {
    fetchProductDetails();
    if (is_logged_in.$ == true) {
      fetchWishListCheckInfo();
    }
    fetchRelatedProducts();
    fetchTopProducts();
  }

  fetchProductDetails() async {
    try {
      final productDetailsResponse =
          await ProductRepository().getProductDetails(slug: widget.slug);

      if (productDetailsResponse.detailed_products!.isNotEmpty) {
        _productDetails = productDetailsResponse.detailed_products![0];
        sellerChatTitleController.text =
            productDetailsResponse.detailed_products![0].name!;
      }

      setProductDetailValues();
      error = null;
    } catch (e) {
      error = e.toString();
    }

    setState(() {});
  }

  fetchRelatedProducts() async {
    final relatedProductResponse =
        await ProductRepository().getFrequentlyBoughProducts(slug: widget.slug);
    _relatedProducts.addAll(relatedProductResponse.products!);
    _relatedProductInit = true;

    setState(() {});
  }

  fetchTopProducts() async {
    final topProductResponse = await ProductRepository()
        .getTopFromThisSellerProducts(slug: widget.slug);
    _topProducts.addAll(topProductResponse.products!);
    _topProductInit = true;
  }

  setProductDetailValues() {
    if (_productDetails != null) {
      controller.loadHtmlString(makeHtml(_productDetails!.description!));
      // .then(
      //   (value) {
      //     WidgetsBinding.instance.addPostFrameCallback((_) async {
      //       getDescriptionHeight();
      //     });
      //   },
      // );
      _appbarPriceString = _productDetails!.price_high_low;
      _singlePrice = _productDetails!.calculable_price;
      _singlePriceString = _productDetails!.main_price;
      // fetchVariantPrice();
      _stock = _productDetails!.current_stock ?? _stock;
      _productDetails!.photos?.forEach((photo) {
        _productImageList.add(photo.path);
      });

      _productDetails!.choice_options?.forEach((choiceOpiton) {
        _selectedChoices.add(choiceOpiton.options![0]);
      });
      _productDetails!.colors?.forEach((color) {
        _colorList.add(color);
      });
      setChoiceString();
      fetchAndSetVariantWiseInfo(change_appbar_string: true, inInit: true);
      _productDetailsFetched = true;

      setState(() {});
    }
  }

  setChoiceString() {
    _choiceString = _selectedChoices.join(",").toString();
    print(_choiceString);
    setState(() {});
  }

  // fetchWishListCheckInfo() async {
  //   var wishListCheckResponse =
  //       await WishListRepository().isProductInUserWishList(
  //     product_slug: widget.slug,
  //   );

  //   //print("p&u:" + widget.slug.toString() + " | " + _user_id.toString());
  //   _isInWishList = wishListCheckResponse.is_in_wishlist;
  //   setState(() {});
  // }

  fetchWishListCheckInfo() async {
    final wishListCheckResponse =
        await WishListRepository().isProductInUserWishList(
      product_slug: widget.slug,
    );

    if (wishListCheckResponse.is_in_wishlist != null) {
      _isInWishList = wishListCheckResponse.is_in_wishlist!;
    } else {
      _isInWishList = false; // or handle this case differently
    }

    setState(() {});
  }

  addToWishList() async {
    final wishListCheckResponse =
        await WishListRepository().add(product_slug: widget.slug);

    //print("p&u:" + widget.slug.toString() + " | " + _user_id.toString());
    _isInWishList = wishListCheckResponse.is_in_wishlist == true;
    setState(() {});
  }

  removeFromWishList() async {
    final wishListCheckResponse =
        await WishListRepository().remove(product_slug: widget.slug);

    //print("p&u:" + widget.slug.toString() + " | " + _user_id.toString());
    _isInWishList = wishListCheckResponse.is_in_wishlist;
    setState(() {});
  }

  void onWishTap() {
    if (is_logged_in.$ == false) {
      ToastComponent.showDialog(
        'you_need_to_log_in'.tr(context: context),
        isError: true,
      );
      return;
    }

    if (_isInWishList) {
      _isInWishList = false;
      setState(() {});
      removeFromWishList();
    } else {
      _isInWishList = true;
      setState(() {});
      addToWishList();
    }
  }

  Future<void> fetchAndSetVariantWiseInfo({
    bool change_appbar_string = true,
    bool inInit = false,
  }) async {
    final colorString = _colorList.isNotEmpty
        ? _colorList[_selectedColorIndex].toString().replaceAll("#", "")
        : "";

    if (inInit) _quantity = minQuantity;

    final variantResponse = await ProductRepository().getVariantWiseInfo(
      slug: widget.slug,
      color: colorString,
      variants: _choiceString,
      qty: _quantity,
    );
    _stock = variantResponse.variantData!.stock ?? _stock;
    _stock_txt = variantResponse.variantData!.stockTxt;
    _inCart = variantResponse.variantData!.inCart ?? 0;

    if (inInit && _inCart > 0) {
      _quantity = _inCart;
      return fetchAndSetVariantWiseInfo();
    }

    if (_quantity > maxQuantity) {
      _quantity = maxQuantity;
    } else if (_quantity < minQuantity) {
      _quantity = minQuantity;
    }

    _variant = variantResponse.variantData!.variant;
    _totalPrice = variantResponse.variantData!.price;
    _basePrice = variantResponse.variantData!.basePrice;

    int pindex = 0;
    _productDetails!.photos?.forEach((photo) {
      if (photo.variant == _variant &&
          variantResponse.variantData!.image != "") {
        _currentImage = pindex;
        _carouselController.animateToPage(pindex);
      }
      pindex++;
    });
    quantityText.text = "$_quantity";
    setState(() {});
  }

  void reset() {
    restProductDetailValues();
    _currentImage = 0;
    _productImageList.clear();
    _colorList.clear();
    _selectedChoices.clear();
    _relatedProducts.clear();
    _topProducts.clear();
    _choiceString = "";
    _variant = "";
    _selectedColorIndex = 0;
    _quantity = _inCart == 0 ? minQuantity : _inCart;
    _productDetailsFetched = false;
    _isInWishList = false;
    sellerChatTitleController.clear();
    setState(() {});
  }

  void restProductDetailValues() {
    _appbarPriceString = " . . .";
    _productDetails = null;
    _productImageList.clear();
    _currentImage = 0;
    setState(() {});
  }

  Future<void> _onPageRefresh() async {
    reset();
    fetchAll();
  }

  void _onVariantChange(_choice_options_index, value) {
    _selectedChoices[_choice_options_index] = value;
    setChoiceString();
    setState(() {});
    fetchAndSetVariantWiseInfo(inInit: true);
  }

  void _onColorChange(index) {
    _selectedColorIndex = index;
    setState(() {});
    fetchAndSetVariantWiseInfo(inInit: true);
  }

  void onPressAddToCart(context, snackbar) {
    addToCart(mode: "add_to_cart", context: context, snackbar: snackbar);
  }

  void onPressBuyNow(context) {
    addToCart(mode: "buy_now", context: context);
  }

  Future<void> addToCart({
    mode,
    required BuildContext context,
    snackbar = null,
  }) async {
    // if (is_logged_in.$ == false) {
    //   // ToastComponent.showDialog('common_login_warning'.tr(context: context), context,
    //   //     gravity: Toast.center, duration: Toast.lengthLong);
    //   //Navigator.push(context, MaterialPageRoute(builder: (context) => Login()));
    //   context?.go("/login");
    //   return;
    // }

    if (!AppConfig.businessSettingsData.guestCheckoutStatus) {
      if (is_logged_in.$ == false) {
        context.push("/login");
        return;
      }
    }
    await fetchAndSetVariantWiseInfo();

    final cartAddResponse = await CartRepository().getCartAddResponse(
      _productDetails?.id,
      _variant,
      _quantity,
    );

    temp_user_id.$ = cartAddResponse?.tempUserId ?? '';
    await temp_user_id.save();

    if (cartAddResponse.result == false) {
      ToastComponent.showDialog(
        cartAddResponse.message,
        isError: true,
      );
      return;
    } else {
      Provider.of<CartCounter>(context, listen: false).getCount();

      if (mode == "add_to_cart") {
        if (snackbar != null) {
          ScaffoldMessenger.of(context).showSnackBar(snackbar);
        }
        reset();
        fetchAll();
      } else if (mode == 'buy_now') {
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return const Cart(has_bottomnav: false);
        })).then((value) {
          onPopped(value);
        });
      }
    }
  }

  void onPopped(value) {
    reset();
    fetchAll();
  }

  void onCopyTap(setState) {
    setState(() {
      _showCopied = true;
    });
    Timer(const Duration(seconds: 3), () {
      setState(() {
        _showCopied = false;
      });
    });
  }

  Future onPressShare(context) {
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, StateSetter setState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 10),
              contentPadding: const EdgeInsets.only(
                  top: 36.0, left: 36.0, right: 36.0, bottom: 2.0),
              content: Container(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: AppDimensions.paddingSmall),
                        child: Btn.minWidthFixHeight(
                          minWidth: 75,
                          height: 26,
                          color: const Color.fromRGBO(253, 253, 253, 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusSmall),
                              side: const BorderSide(
                                  color: Colors.black, width: 1.0)),
                          child: Text(
                            'copy_product_link_ucf'.tr(context: context),
                            style: const TextStyle(
                              color: MyTheme.medium_grey,
                            ),
                          ),
                          onPressed: () {
                            onCopyTap(setState);
                            Clipboard.setData(ClipboardData(
                                text: _productDetails!.link ?? ""));
                            Clipboard.setData(ClipboardData(
                              text: _productDetails!.link!,
                            )).then((_) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
                                content: Text("Copied to clipboard"),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(milliseconds: 300),
                              ));
                            });
                          },
                        ),
                      ),
                      _showCopied
                          ? Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppDimensions.paddingSmall),
                              child: Text(
                                'copied_ucf'.tr(context: context),
                                style: const TextStyle(
                                    color: MyTheme.medium_grey, fontSize: 12),
                              ),
                            )
                          : Container(),
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: AppDimensions.paddingSmall),
                        child: Btn.minWidthFixHeight(
                          minWidth: 75,
                          height: 26,
                          color: Colors.blue,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusSmall),
                              side: const BorderSide(
                                  color: Colors.black, width: 1.0)),
                          child: Text(
                            'share_options_ucf'.tr(context: context),
                            style: const TextStyle(color: Colors.white),
                          ),
                          onPressed: () async {
                            Share.share(_productDetails!.link!,
                                sharePositionOrigin: Rect.fromLTWH(
                                    0,
                                    0,
                                    MediaQuery.sizeOf(context).width,
                                    MediaQuery.sizeOf(context).height / 1.92));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Padding(
                      padding: app_language_rtl.$!
                          ? const EdgeInsets.only(
                              left: AppDimensions.paddingSmall)
                          : const EdgeInsets.only(right: 8.0),
                      child: Btn.minWidthFixHeight(
                        minWidth: 75,
                        height: 30,
                        color: const Color.fromRGBO(253, 253, 253, 1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppDimensions.radiusSmall),
                            side: const BorderSide(
                                color: MyTheme.font_grey, width: 1.0)),
                        child: Text(
                          'close_all_capital'.tr(context: context),
                          style: const TextStyle(
                            color: MyTheme.font_grey,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                      ),
                    ),
                  ],
                )
              ],
            );
          });
        });
  }

  Future onTapSellerChat() {
    return showDialog(
        context: context,
        builder: (_) => Directionality(
              textDirection:
                  app_language_rtl.$! ? TextDirection.rtl : TextDirection.ltr,
              child: AlertDialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 10),
                contentPadding: const EdgeInsets.only(
                    top: 36.0, left: 36.0, right: 36.0, bottom: 2.0),
                content: Container(
                  width: 400,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingSmall),
                          child: Text('title_ucf'.tr(context: context),
                              style: const TextStyle(
                                  color: MyTheme.font_grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingDefault),
                          child: Container(
                            height: 40,
                            child: TextField(
                              controller: sellerChatTitleController,
                              autofocus: false,
                              decoration: InputDecoration(
                                  hintText:
                                      'enter_title_ucf'.tr(context: context),
                                  hintStyle: const TextStyle(
                                      fontSize: 12.0,
                                      color: MyTheme.textfield_grey),
                                  enabledBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: MyTheme.textfield_grey,
                                        width: 0.5),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(
                                          AppDimensions.radiusSmall),
                                    ),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: MyTheme.textfield_grey,
                                        width: 1.0),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(
                                          AppDimensions.radiusSmall),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8.0)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingSmall),
                          child: Text("${'message_ucf'.tr(context: context)} *",
                              style: const TextStyle(
                                  color: MyTheme.font_grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingDefault),
                          child: Container(
                            height: 55,
                            child: TextField(
                              controller: sellerChatMessageController,
                              autofocus: false,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              decoration: InputDecoration(
                                  hintText:
                                      'enter_message_ucf'.tr(context: context),
                                  hintStyle: const TextStyle(
                                      fontSize: 12.0,
                                      color: MyTheme.textfield_grey),
                                  enabledBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: MyTheme.textfield_grey,
                                        width: 0.5),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(
                                          AppDimensions.radiusSmall),
                                    ),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: MyTheme.textfield_grey,
                                        width: 1.0),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(
                                          AppDimensions.radiusSmall),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.only(
                                      right: 16.0,
                                      left: 8.0,
                                      top: 16.0,
                                      bottom: 16.0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Btn.minWidthFixHeight(
                          minWidth: 75,
                          height: 30,
                          color: const Color.fromRGBO(253, 253, 253, 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusSmall),
                              side: const BorderSide(
                                  color: MyTheme.light_grey, width: 1.0)),
                          child: Text(
                            'close_all_capital'.tr(context: context),
                            style: const TextStyle(
                              color: MyTheme.font_grey,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).pop();
                          },
                        ),
                      ),
                      const SizedBox(
                        width: 1,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Btn.minWidthFixHeight(
                          minWidth: 75,
                          height: 30,
                          color: Theme.of(context).primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusSmall),
                              side: const BorderSide(
                                  color: MyTheme.light_grey, width: 1.0)),
                          child: Text(
                            'send_all_capital'.tr(context: context),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).pop();
                            onPressSendMessage();
                          },
                        ),
                      )
                    ],
                  )
                ],
              ),
            ));
  }

  loading() {
    showDialog(
        context: context,
        builder: (context) {
          loadingcontext = context;
          return AlertDialog(
              content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(
                width: 10,
              ),
              Text("${'please_wait_ucf'.tr(context: context)}"),
            ],
          ));
        });
  }

  dynamic showLoginWarning() {
    return ToastComponent.showDialog(
      'you_need_to_log_in'.tr(context: context),
      isError: true,
    );
  }

  Future<void> onPressSendMessage() async {
    if (!is_logged_in.$) {
      showLoginWarning();
      return;
    }
    loading();
    final title = sellerChatTitleController.text.toString();
    final message = sellerChatMessageController.text.toString();

    if (title == "" || message == "") {
      ToastComponent.showDialog(
        'title_or_message_empty_warning'.tr(context: context),
        isError: true,
      );
      return;
    }

    final conversationCreateResponse = await ChatRepository()
        .getCreateConversationResponse(
            product_id: _productDetails!.id, title: title, message: message);

    Navigator.of(loadingcontext).pop();

    if (conversationCreateResponse.result == false) {
      ToastComponent.showDialog(
        'could_not_create_conversation'.tr(context: context),
        isError: true,
      );
      return;
    }

    sellerChatTitleController.clear();
    sellerChatMessageController.clear();
    setState(() {});

    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return Chat(
        conversation_id: conversationCreateResponse.conversation_id,
        messenger_name: conversationCreateResponse.shop_name,
        messenger_title: conversationCreateResponse.title,
        messenger_image: conversationCreateResponse.shop_logo,
      );
    })).then((value) {
      onPopped(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isWholesale = makeNewVisualWholesale(_productDetails?.wholesale);
    final SnackBar _addedToCartSnackbar = SnackBar(
      content: Text(
        whenItemInCart<String>(
          'update_cart_ucf'.tr(context: context),
          'added_to_cart'.tr(context: context),
        ),
        style: const TextStyle(color: MyTheme.font_grey),
      ),
      backgroundColor: MyTheme.soft_accent_color,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'show_cart_all_capital'.tr(context: context),
        onPressed: () {
          Navigator.push(OneContext().context!,
              MaterialPageRoute(builder: (context) {
            return const Cart(has_bottomnav: false);
          })).then((value) {
            onPopped(value);
          });
        },
        textColor: Theme.of(context).primaryColor,
        disabledTextColor: Colors.grey,
      ),
    );

    return Directionality(
      textDirection:
          app_language_rtl.$! ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
          extendBody: true,
          backgroundColor: MyTheme.mainColor,
          bottomNavigationBar: buildBottomAppBar(_addedToCartSnackbar),
          body: RefreshIndicator(
            color: Theme.of(context).primaryColor,
            backgroundColor: Colors.white,
            onRefresh: _onPageRefresh,
            child: CustomScrollView(
              controller: _mainScrollController,
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: <Widget>[
                SliverAppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0.0,
                  backgroundColor: MyTheme.mainColor,
                  pinned: true,
                  automaticallyImplyLeading:
                      _scrollPosition > 250 || productHasError,
                  expandedHeight: productHasError ? null : 375.0,
                  title: AnimatedOpacity(
                      opacity: _scrollPosition > 250 ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingSmall),
                          width: DeviceInfo(context).width! / 2,
                          child: Text(
                            "${_productDetails != null ? _productDetails!.name : ''}",
                            style: const TextStyle(
                                color: MyTheme.dark_font_grey,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ))),
                  flexibleSpace: productHasError
                      ? null
                      : FlexibleSpaceBar(
                          background: Stack(
                            children: [
                              Positioned.fill(
                                child: SafeArea(
                                  child: ProductSliderImageWidget(
                                    productImageList: _productImageList,
                                    currentImage: _currentImage,
                                    carouselController: _carouselController,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 48,
                                  left: 33,
                                  right: 33,
                                ),
                                child: Row(
                                  children: [
                                    Builder(
                                      builder: (context) => InkWell(
                                        onTap: () {
                                          return Navigator.pop(context);
                                        },
                                        child: Container(
                                          decoration: BoxDecorations
                                              .buildCircularButtonDecoration_for_productDetails(),
                                          width: 36,
                                          height: 36,
                                          child: Center(
                                            child: Icon(
                                              app_language_rtl.$!
                                                  ? CupertinoIcons.arrow_right
                                                  : CupertinoIcons.arrow_left,
                                              color: MyTheme.dark_font_grey,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Show product name in appbar

                                    const Spacer(),
                                    // Cart button at top
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(context,
                                            MaterialPageRoute(
                                                builder: (context) {
                                          return const Cart(
                                              has_bottomnav: false);
                                        })).then((value) {
                                          onPopped(value);
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecorations
                                            .buildCircularButtonDecoration_for_productDetails(),
                                        width: 32,
                                        height: 32,
                                        padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmallExtra),
                                        child: badges.Badge(
                                          position: badges.BadgePosition.topEnd(
                                            top: -6,
                                            end: -6,
                                          ),
                                          badgeStyle: badges.BadgeStyle(
                                            shape: badges.BadgeShape.circle,
                                            badgeColor:
                                                Theme.of(context).primaryColor,
                                            borderRadius: BorderRadius.circular(
                                                AppDimensions.radiusNormal),
                                          ),
                                          badgeAnimation:
                                              const badges.BadgeAnimation.slide(
                                            toAnimate: true,
                                          ),
                                          stackFit: StackFit.loose,
                                          child: Center(
                                            child: Image.asset(
                                              "assets/cart.png",
                                              color: MyTheme.dark_font_grey,
                                              height: 16,
                                            ),
                                          ),
                                          badgeContent: Consumer<CartCounter>(
                                            builder: (context, cart, child) {
                                              return Text(
                                                "${cart.cartCounter}",
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    InkWell(
                                      onTap: () {
                                        onPressShare(context);
                                      },
                                      child: const TappableIconWidget(
                                        icon: Icons.share_outlined,
                                        color: MyTheme.dark_font_grey,
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    InkWell(
                                      onTap: onWishTap,
                                      borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusVeryExtra),
                                      child: _isInWishList
                                          ? const TappableIconWidget(
                                              icon: Icons.favorite,
                                              color:
                                                  Color.fromRGBO(230, 46, 4, 1),
                                            )
                                          : const TappableIconWidget(
                                              icon: Icons.favorite_border,
                                              color: MyTheme.dark_font_grey,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (productHasError)
                  SliverFillRemaining(
                    child: CustomErrorWidget(errorMessage: error),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusHalfSmall),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .08),
                              blurRadius: 20,
                              spreadRadius: 0.0,
                              offset: const Offset(
                                  0.0, 0.0), // shadow direction: bottom right
                            )
                          ],
                        ),
                        // margin: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(
                                  AppDimensions.paddingDefault),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _productDetails != null
                                      ? Text(
                                          _productDetails!.name!,
                                          style: const TextStyle(
                                              color: Color(0xff3E4447),
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Public Sans',
                                              fontSize: 13),
                                          maxLines: 2,
                                        )
                                      : ShimmerHelper().buildBasicShimmer(
                                          height: 30.0,
                                        ),
                                  const SizedBox(height: 13),
                                  _productDetails != null
                                      ? buildRatingAndWishButtonRow()
                                      : ShimmerHelper().buildBasicShimmer(
                                          height: 30.0,
                                        ),
                                  if (_productDetails != null &&
                                      _productDetails!.estShippingTime !=
                                          null &&
                                      _productDetails!.estShippingTime! > 0)
                                    _productDetails != null
                                        ? buildShippingTime()
                                        : ShimmerHelper().buildBasicShimmer(
                                            height: 30.0,
                                          ),
                                  if (!isWholesale) ...[
                                    const SizedBox(height: 12),
                                    _productDetails != null
                                        ? buildMainPriceRow()
                                        : ShimmerHelper().buildBasicShimmer(
                                            height: 30.0,
                                          ),
                                  ],
                                  const SizedBox(height: 14),
                                  Visibility(
                                    visible: club_point_addon_installed.$,
                                    child: _productDetails != null
                                        ? buildClubPointRow()
                                        : ShimmerHelper().buildBasicShimmer(
                                            height: 30.0,
                                          ),
                                  ),
                                  const SizedBox(height: 9),
                                  _productDetails != null
                                      ? buildBrandRow()
                                      : ShimmerHelper().buildBasicShimmer(
                                          height: 50.0,
                                        ),
                                ],
                              ),
                            ),
                            _productDetails != null
                                ? buildSellerRow(context)
                                : ShimmerHelper().buildBasicShimmer(
                                    height: 50.0,
                                  ),
                            if (isWholesale)
                              wholeSalePackingWidget()
                            else
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 0, 14, 0),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 11),

                                    _productDetails != null
                                        ? buildChoiceOptionList()
                                        : buildVariantShimmers(),

                                    _productDetails != null
                                        ? (_colorList.isNotEmpty
                                            ? buildColorRow()
                                            : const SizedBox())
                                        : ShimmerHelper().buildBasicShimmer(
                                            height: 30.0,
                                          ),
                                    const SizedBox(height: 20),

                                    ///whole sale
                                    Visibility(
                                      visible: whole_sale_addon_installed.$,
                                      child: _productDetails != null
                                          ? _productDetails!
                                                      .wholesale?.isNotEmpty ==
                                                  true
                                              ? buildWholeSaleQuantityPrice()
                                              : const SizedBox.shrink()
                                          : ShimmerHelper().buildBasicShimmer(
                                              height: 30.0,
                                            ),
                                    ),

                                    _productDetails != null
                                        ? buildQuantityRow()
                                        : ShimmerHelper().buildBasicShimmer(
                                            height: 30.0,
                                          ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 27),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: _productDetails != null
                                  ? buildTotalPriceRow()
                                  : ShimmerHelper().buildBasicShimmer(
                                      height: 30.0,
                                    ),
                            ),
                            const SizedBox(height: 10)
                          ],
                        ),
                      ),
                    ),
                  ),

                  ////////////////////////for description//////////////////
                  SliverToBoxAdapter(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  spreadRadius: 0,
                                  blurRadius: 16,
                                  offset: const Offset(
                                      0, 0), // changes position of shadow
                                ),
                              ],
                            ),
                            //  margin: EdgeInsets.only(top: AppDimensions.paddingsupsmall),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16.0,
                                    20.0,
                                    16.0,
                                    0.0,
                                  ),
                                  child: Text(
                                    'description_ucf'.tr(context: context),
                                    style: const TextStyle(
                                        color: Color(0xff3E4447),
                                        fontFamily: 'Public Sans',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0,
                                    0.0,
                                    8.0,
                                    8.0,
                                  ),
                                  child: _productDetails != null
                                      ? buildExpandableDescription()
                                      : Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0, vertical: 8.0),
                                          child:
                                              ShimmerHelper().buildBasicShimmer(
                                            height: 60.0,
                                          )),
                                ),
                              ],
                            ),
                          ),
                          if (_productDetails?.downloads != null)
                            Column(
                              children: [
                                const SizedBox(
                                  height: 16,
                                ),
                                InkWell(
                                  onTap: () async {
                                    print(_productDetails?.downloads);
                                    final url = Uri.parse(
                                        _productDetails?.downloads ?? "");
                                    print(url);
                                    launchUrl(url,
                                        mode: LaunchMode.externalApplication);
                                  },
                                  child: Container(
                                    color: MyTheme.white,
                                    height: 48,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        18.0,
                                        14.0,
                                        18.0,
                                        14.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            'downloads_ucf'
                                                .tr(context: context),
                                            style: const TextStyle(
                                                color: MyTheme.dark_font_grey,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600),
                                          ),
                                          const Spacer(),
                                          Image.asset(
                                            "assets/arrow.png",
                                            height: 11,
                                            width: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_productDetails?.video_link?.isNotEmpty ==
                              true) ...[
                            const SizedBox(
                              height: 16,
                            ),
                            // if (_productDetails?.video_link != null &&
                            //     _productDetails!.video_link!.isNotEmpty)
                            InkWell(
                              onTap: () {
                                if (_productDetails!.video_link == "") {
                                  ToastComponent.showDialog(
                                    'video_not_available'.tr(context: context),
                                    isError: true,
                                  );
                                  return;
                                }

                                Navigator.push(context,
                                    MaterialPageRoute(builder: (context) {
                                  return VideoDescription(
                                    url: _productDetails!.video_link,
                                  );
                                })).then((value) {
                                  onPopped(value);
                                });
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      spreadRadius: 0,
                                      blurRadius: 16,
                                      offset: const Offset(
                                          0, 0), // changes position of shadow
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18.0,
                                    14.0,
                                    18.0,
                                    14.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        'video_ucf'.tr(context: context),
                                        style: const TextStyle(
                                            color: Color(0xff3E4447),
                                            fontSize: 13,
                                            fontFamily: 'Public Sans',
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      Image.asset(
                                        "assets/arrow.png",
                                        color: const Color(0xff6B7377),
                                        height: 11,
                                        width: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(
                            height: 16,
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (context) {
                                return ProductReviews(id: _productDetails!.id);
                              })).then((value) {
                                onPopped(value);
                              });
                            },
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    spreadRadius: 0,
                                    blurRadius: 16,
                                    offset: const Offset(
                                        0, 0), // changes position of shadow
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18.0,
                                  14.0,
                                  18.0,
                                  14.0,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'reviews_ucf'.tr(context: context),
                                      style: const TextStyle(
                                          color: Color(0xff3E4447),
                                          fontFamily: 'Public Sans',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const Spacer(),
                                    Image.asset(
                                      "assets/arrow.png",
                                      height: 11,
                                      width: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ]),
                  ),
                  if (_relatedProducts.isNotEmpty ||
                      _relatedProductInit == false)
                    SliverList(
                      delegate: SliverChildListDelegate([
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            18.0,
                            22.0,
                            18.0,
                            0.0,
                          ),
                          child: Text(
                            'products_you_may_also_like'.tr(context: context),
                            style: const TextStyle(
                                color: Colors.black,
                                fontFamily: 'Roboto',
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        buildProductsMayLikeList()
                      ]),
                    ),

                  //Top selling product
                  SliverList(
                    delegate: SliverChildListDelegate([
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          16.0,
                          24.0,
                          16.0,
                          0.0,
                        ),
                        child: Text(
                          'top_selling_products_ucf'.tr(context: context),
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      buildTopSellingProductList(),
                      Container(height: 120)
                    ]),
                  ),
                ],
              ],
            ),
          )),
    );
  }

  Widget wholeSalePackingWidget() {
    final List<Wholesale> wholesaleList = _productDetails!.wholesale!;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Text(
        //   "Quantity : $_quantity",
        //   textAlign: TextAlign.center,
        //   style: const TextStyle(color: Color(0xff6B7377), fontSize: 14),
        // ),
        const SizedBox(height: AppDimensions.paddingDefault),
        Text(
          _stock_txt ?? '',
          // _stock > 0
          //     ? "${'in_stock'.tr(context: context)}: $_stock_txt"
          //     : 'out_of_stock'.tr(context: context),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _stock > 0 ? null : Colors.red,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingDefault),
        ...List.generate(
          wholesaleList.length,
          (index) {
            final Wholesale wholeSale = wholesaleList[index];
            final int quantityText = distributeWholesale(
              index: index,
              total: _quantity,
              list: wholesaleList,
            );
            return Card(
              margin: const EdgeInsets.all(AppDimensions.paddingNormal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        runSpacing: AppDimensions.paddingDefault,
                        spacing: AppDimensions.paddingDefault,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        runAlignment: WrapAlignment.spaceBetween,
                        alignment: WrapAlignment.spaceBetween,
                        direction: Axis.horizontal,
                        children: [
                          if (wholeSale.name?.trim().isNotEmpty == true)
                            _ItemDataWidget(
                              title: 'wholesale_pkg_name'.tr(context: context),
                              data: wholeSale.name!,
                            ),
                          if (AppConfig.businessSettingsData
                              .showPackingQtyWholesaleProduct)
                            _ItemDataWidget(
                              title: 'pkg_quantity'.tr(context: context),
                              data: wholeSale.minQty.withSeparator,
                            ),
                          if (AppConfig.businessSettingsData
                              .showPackingQtyPriceWholesaleProduct)
                            _ItemDataWidget(
                              title: 'unit_price_ucf'.tr(context: context),
                              data: wholeSale.priceDouble.withSeparator,
                            ),
                          Builder(builder: (context) {
                            final double firstPrice =
                                wholesaleList[0].priceDouble * wholeSale.minQty;
                            final double price =
                                wholeSale.minQty * wholeSale.priceDouble;
                            return _ItemDataWidget(
                              title: 'pkg_price'.tr(context: context),
                              data: price.withSeparator,
                              beforeDataInLine: [
                                if (AppConfig.businessSettingsData
                                        .showPackingBeforePriceWholesaleProduct &&
                                    index != 0 &&
                                    firstPrice != price) ...[
                                  TextSpan(
                                    text: firstPrice.withSeparator,
                                    style: const TextStyle(
                                      color: MyTheme.font_grey,
                                      decoration: TextDecoration.lineThrough,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  const WidgetSpan(
                                    child: SizedBox(
                                      width: AppDimensions.paddingSmall,
                                    ),
                                  )
                                ],
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimensions.paddingDefault),
                    buildQuantityWholeSale(
                      changedQuantity: wholeSale.minQty,
                      quantityText: quantityText,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget buildSellerRow(BuildContext context) {
    //print("sl:" +  _productDetails!.shop_logo);
    if (_productDetails?.shop_slug?.trim().isNotEmpty != true)
      return const SizedBox();
    return Container(
      color: const Color(0xffF6F7F8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _productDetails!.added_by == "admin"
              ? Container()
              : InkWell(
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => SellerDetails(
                                  slug: _productDetails?.shop_slug ?? "",
                                )));
                  },
                  child: Padding(
                    padding: app_language_rtl.$!
                        ? const EdgeInsets.only(
                            left: AppDimensions.paddingSmall)
                        : const EdgeInsets.only(right: 8.0),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            AppDimensions.radiusHalfSmall),
                        border: Border.all(
                            color: const Color.fromRGBO(112, 112, 112, 0.298),
                            width: 1),
                        //shape: BoxShape.rectangle,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            AppDimensions.radiusHalfSmall),
                        child: FadeInImage.assetNetwork(
                          placeholder: AppImages.placeholder,
                          imageErrorBuilder: (context, error, stackTrace) {
                            return Image.asset(AppImages.placeholder);
                          },
                          image: _productDetails?.shop_logo ?? '',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
          if (_productDetails?.shop_name != null)
            Container(
              width: MediaQuery.sizeOf(context).width * (.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('seller_ucf'.tr(context: context),
                      style: const TextStyle(
                          color: Color(0xff6B7377),
                          fontFamily: 'Public Sans',
                          fontSize: 10)),
                  Text(
                    _productDetails!.shop_name!,
                    style: const TextStyle(
                        color: Color(0xff3E4447),
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  )
                ],
              ),
            ),
          const Spacer(),
          Visibility(
            visible: AppConfig.businessSettingsData.conversationSystem,
            child: Container(
                padding: const EdgeInsets.all(AppDimensions.paddingNormal),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusVeryLarge),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 20,
                      spreadRadius: 0.0,
                      offset: const Offset(
                          0.0, 10.0), // shadow direction: bottom right
                    )
                  ],
                ),
                child: Row(
                  children: [
                    InkWell(
                        onTap: () {
                          if (is_logged_in.$ == false) {
                            ToastComponent.showDialog(
                              'you_need_to_log_in'.tr(context: context),
                              isError: true,
                            );
                            return;
                          }

                          onTapSellerChat();
                        },
                        child: Image.asset('assets/chat.png',
                            height: 16,
                            width: 16,
                            color: const Color(0xff6B7377))),
                  ],
                )),
          )
        ],
      ),
    );
  }

  Widget buildTotalPriceRow() {
    return Container(
      height: 40,
      color: const Color(0xffFEF0D7),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Container(
            child: Padding(
              padding: app_language_rtl.$!
                  ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                  : const EdgeInsets.only(right: 8.0),
              child: Container(
                width: 75,
                child: Text(
                  'total_price_ucf'.tr(context: context),
                  style:
                      const TextStyle(color: Color(0xff6B7377), fontSize: 10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              bottom: AppDimensions.paddingSmallExtra,
            ),
            child: AnimatedNumberText<double>(
              totalBasePrice,
              duration: const Duration(
                  milliseconds: AppDimensions.animationDefaultInMillis),
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
              ),
              formatter: (value) {
                return '${value.withSeparator} ${SystemConfig.systemCurrency?.symbol ?? ''}'
                    .trim();
              },
            ),
          )
        ],
      ),
    );
  }

  Widget buildQuantityWholeSale({
    int changedQuantity = 1,
    required int quantityText,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: AppDimensions.paddingSmall,
      children: [
        QuantityButtonWidget(
          icon: Icons.add,
          doWhen: (_quantity + changedQuantity) <= maxQuantity,
          textWhenDont: 'maxOrderQuantityLimit'.tr(
            context: context,
            args: {"maxQuantity": "$maxQuantity"},
          ),
          onPressed: () {
            _quantity = _quantity + changedQuantity;
            setState(() {});
            fetchAndSetVariantWiseInfo();
          },
        ),
        Text(
          quantityText.toString(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        QuantityButtonWidget(
          icon: Icons.remove,
          doWhen: (_quantity - changedQuantity) >= minQuantity,
          textWhenDont: 'minimumOrderQuantity'.tr(
            context: context,
            args: {"minQuantity": "$minQuantity"},
          ),
          onPressed: () {
            _quantity = _quantity - changedQuantity;
            setState(() {});
            fetchAndSetVariantWiseInfo();
          },
        ),
      ],
    );
  }

  Row buildQuantityRow() {
    return Row(
      children: [
        Padding(
          padding: app_language_rtl.$!
              ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
              : const EdgeInsets.only(right: 8.0),
          child: Container(
            width: 75,
            child: Text(
              'quantity_ucf'.tr(context: context),
              style: const TextStyle(
                  color: Color(0xff6B7377), fontFamily: 'Public Sans'),
            ),
          ),
        ),
        Container(
          height: 30,
          width: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              QuantityButtonWidget(
                icon: Icons.remove,
                doWhen: _quantity > minQuantity,
                textWhenDont: 'minimumOrderQuantity'.tr(
                  context: context,
                  args: {"minQuantity": "$minQuantity"},
                ),
                onPressed: () {
                  _quantity = _quantity - 1;
                  setState(() {});
                  fetchAndSetVariantWiseInfo();
                },
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: QuantityInputField.show(
                    quantityText,
                    isDisable: _stock == 0,
                    onChanged: (val) {
                      _quantity = int.parse(quantityText.text);
                      if (_quantity > maxQuantity) {
                        _quantity = maxQuantity;
                      } else if (_quantity < minQuantity) {
                        _quantity = minQuantity;
                      }
                      quantityText.text = _quantity.toString();
                    },
                    onSubmitted: () {
                      _quantity = int.parse(quantityText.text);
                      fetchAndSetVariantWiseInfo();
                    },
                  ),
                ),
              ),
              QuantityButtonWidget(
                icon: Icons.add,
                doWhen: _quantity < maxQuantity,
                textWhenDont: 'maxOrderQuantityLimit'.tr(
                  context: context,
                  args: {"maxQuantity": "$maxQuantity"},
                ),
                onPressed: () {
                  _quantity = _quantity + 1;
                  setState(() {});
                  fetchAndSetVariantWiseInfo();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Row(
              children: [
                Text(
                  "$_stock_txt",
                  style:
                      const TextStyle(color: Color(0xff6B7377), fontSize: 14),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(
                      milliseconds: AppDimensions.animationShortInMillis,
                    ),
                    child: Text('out_of_stock'.tr(context: context)),
                    textAlign: TextAlign.center,
                    style: _stock == 0
                        ? const TextStyle(color: Colors.red, fontSize: 15)
                        : const TextStyle(
                            color: Colors.transparent, fontSize: 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextEditingController quantityText = TextEditingController(text: "0");

  Padding buildVariantShimmers() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16.0,
        0.0,
        8.0,
        0.0,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppDimensions.paddingSmall),
            child: Row(
              children: [
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppDimensions.paddingSmall),
            child: Row(
              children: [
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                ),
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 30.0, width: 60),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  ListView buildChoiceOptionList() {
    return ListView.builder(
      itemCount: _productDetails!.choice_options?.length ?? 0,
      scrollDirection: Axis.vertical,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
          child: buildChoiceOpiton(_productDetails!.choice_options, index),
        );
      },
    );
  }

  Padding buildChoiceOpiton(choiceOptions, choiceOptionsIndex) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0.0,
        14.0,
        0.0,
        0.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: app_language_rtl.$!
                ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                : const EdgeInsets.only(right: 8.0),
            child: Container(
              width: 75,
              child: Text(
                choiceOptions[choiceOptionsIndex].title,
                style: const TextStyle(color: Color.fromRGBO(153, 153, 153, 1)),
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _variantScrollController,
              child: Wrap(
                alignment: WrapAlignment.spaceAround,
                children: List.generate(
                    choiceOptions[choiceOptionsIndex].options.length,
                    (index) => Container(
                          margin: const EdgeInsets.only(
                              bottom: AppDimensions.paddingSmall),
                          padding: const EdgeInsets.only(
                              bottom: AppDimensions.paddingSmall),
                          child: buildChoiceItem(
                              choiceOptions[choiceOptionsIndex].options[index],
                              choiceOptionsIndex,
                              index),
                        )),
              ),
            ),
          )
        ],
      ),
    );
  }

  Padding buildChoiceItem(option, choiceOptionsIndex, index) {
    return Padding(
      padding: app_language_rtl.$!
          ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
          : const EdgeInsets.only(right: AppDimensions.paddingSmall),
      child: InkWell(
        onTap: () {
          _onVariantChange(choiceOptionsIndex, option);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
          decoration: BoxDecoration(
            border: Border.all(
                color: _selectedChoices[choiceOptionsIndex] == option
                    ? Theme.of(context).primaryColor
                    : MyTheme.noColor,
                width: 1.5),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSmallExtra),
            color: MyTheme.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0.0, 3.0),
              )
            ],
          ),
          child: Text(
            option,
            style: TextStyle(
                color: _selectedChoices[choiceOptionsIndex] == option
                    ? Theme.of(context).primaryColor
                    : const Color.fromRGBO(224, 224, 225, 1),
                fontSize: 12.0,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Row buildColorRow() {
    return Row(
      children: [
        Padding(
          padding: app_language_rtl.$!
              ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
              : const EdgeInsets.only(right: 8.0),
          child: Container(
            width: 75,
            child: Text(
              'color_ucf'.tr(context: context),
              style: const TextStyle(color: Color.fromRGBO(153, 153, 153, 1)),
            ),
          ),
        ),
        Container(
          alignment: app_language_rtl.$!
              ? Alignment.centerRight
              : Alignment.centerLeft,
          height: 40,
          width: MediaQuery.sizeOf(context).width - (107 + 44),
          child: Scrollbar(
            controller: _colorScrollController,
            child: ListView.separated(
              separatorBuilder: (context, index) {
                return const SizedBox(
                  width: 10,
                );
              },
              itemCount: _colorList.length,
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildColorItem(index),
                  ],
                );
              },
            ),
          ),
        )
      ],
    );
  }

  Widget buildColorItem(index) {
    return InkWell(
      onTap: () {
        _onColorChange(index);
      },
      child: AnimatedContainer(
        duration: const Duration(
            milliseconds: AppDimensions.animationDefaultInMillis),
        width: _selectedColorIndex == index ? 21 : 18,
        height: _selectedColorIndex == index ? 21 : 18,
        decoration: BoxDecoration(
          border: _selectedColorIndex == index
              ? Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 3,
                )
              : Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          color: ColorHelper.getColorFromColorCode(_colorList[index]),
          boxShadow: [
            _selectedColorIndex == index
                ? BoxShadow(
                    color: Colors.black.withValues(
                        alpha: _selectedColorIndex == index ? 0.25 : 0.12),
                    blurRadius: 10,
                    spreadRadius: 2.0,
                    offset: const Offset(
                        0.0, 6.0), // shadow direction: bottom right
                  )
                : BoxShadow(
                    color: Colors.black.withValues(
                        alpha: _selectedColorIndex == index ? 0.25 : 0.16),
                    blurRadius: 6,
                    spreadRadius: 0.0,
                    offset: const Offset(0.0, 3.0),
                  )
          ],
        ),
      ),
    );
  }

  Widget buildWholeSaleQuantityPrice() {
    return DataTable(
      // clipBehavior:Clip.antiAliasWithSaveLayer,
      columnSpacing: DeviceInfo(context).width! * 0.125,

      columns: [
        DataColumn(
            label: Text('min_qty_ucf'.tr(context: context),
                style:
                    const TextStyle(fontSize: 12, color: MyTheme.dark_grey))),
        DataColumn(
            label: Text('max_qty_ucf'.tr(context: context),
                style:
                    const TextStyle(fontSize: 12, color: MyTheme.dark_grey))),
        DataColumn(
            label: Text('unit_price_ucf'.tr(context: context),
                style:
                    const TextStyle(fontSize: 12, color: MyTheme.dark_grey))),
      ],
      rows: List<DataRow>.generate(
        _productDetails!.wholesale!.length,
        (index) {
          return DataRow(cells: <DataCell>[
            DataCell(
              Text(
                '${_productDetails!.wholesale![index].minQty.toString()}',
                style: const TextStyle(
                    color: Color.fromRGBO(152, 152, 153, 1), fontSize: 12),
              ),
            ),
            DataCell(
              Text(
                '${_productDetails!.wholesale![index].maxQty.toString()}',
                style: const TextStyle(
                    color: Color.fromRGBO(152, 152, 153, 1), fontSize: 12),
              ),
            ),
            DataCell(
              Text(
                convertPrice(
                    _productDetails!.wholesale![index].price.toString()),
                style: const TextStyle(
                    color: Color.fromRGBO(152, 152, 153, 1), fontSize: 12),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget buildClubPointRow() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      //width: ,
      decoration: BoxDecoration(
          //border: Border.all(color: MyTheme.golden, width: 1),
          borderRadius: BorderRadius.circular(AppDimensions.radiusHalfSmall),
          color:
              //Colors.red,),
              const Color(0xffFFF4E8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Image.asset(
                  "assets/clubpoint.png",
                  width: 18,
                  height: 12,
                ),
                const SizedBox(
                  width: 4,
                ),
                Text(
                  'club_point_ucf'.tr(context: context),
                  style: const TextStyle(
                      color: Color(0xff6B7377),
                      fontSize: 10,
                      fontFamily: 'Public Sans',
                      fontWeight: FontWeight.normal),
                ),
              ],
            ),
            Text(
              _productDetails!.earn_point.toString(),
              style: const TextStyle(color: Color(0xffF7941D), fontSize: 12.0),
            ),
          ],
        ),
      ),
    );
  }

  Row buildMainPriceRow() {
    return Row(
      children: [
        AnimatedNumberText<double>(
          _basePrice,
          duration: const Duration(
              milliseconds: AppDimensions.animationDefaultInMillis),
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontFamily: 'Public Sans',
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
          ),
          formatter: (value) {
            return '${value.toStringAsFixed(2)} ${SystemConfig.systemCurrency?.symbol ?? ''}'
                .trim();
          },
        ),
        Visibility(
          visible: _productDetails!.has_discount!,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
            child: Text(
                SystemConfig.systemCurrency != null
                    ? _productDetails!.stroked_price!.replaceAll(
                        SystemConfig.systemCurrency!.code!,
                        SystemConfig.systemCurrency!.symbol!)
                    : _productDetails!.stroked_price!,
                style: const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Color(0xffA8AFB3),
                  fontFamily: 'Public Sans',
                  fontSize: 12.0,
                  fontWeight: FontWeight.normal,
                )),
          ),
        ),
        Visibility(
          visible: _productDetails!.has_discount!,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
            child: Text(
              "${_productDetails!.discount}",
              style: const TextStyle(
                  fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Text(
          "/${_productDetails!.unit}",
          // _singlePriceString,
          style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontSize: 16.0,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget buildBottomAppBar(_addedToCartSnackbar) {
    if (productHasError) return const SizedBox();
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: AppDimensions.paddingDefault),
      color: MyTheme.white.withValues(alpha: 0.9),
      child: AnimatedSwitcher(
        duration: const Duration(
          milliseconds: AppDimensions.animationDefaultInMillis,
        ),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: whenItemInCart(
          bottomTap(
            context,
            text: 'update_cart_ucf'.tr(context: context),
            color: Theme.of(context).primaryColor,
            shadowColor: MyTheme.accent_color_shadow,
            onTap: () => onPressAddToCart(context, _addedToCartSnackbar),
          ),
          Row(
            children: [
              Expanded(
                child: bottomTap(
                  context,
                  text: 'add_to_cart_ucf'.tr(context: context),
                  color: Theme.of(context).primaryColor,
                  shadowColor: MyTheme.accent_color_shadow,
                  onTap: () => onPressAddToCart(context, _addedToCartSnackbar),
                ),
              ),
              Expanded(
                child: bottomTap(
                  context,
                  text: 'buy_now_ucf'.tr(context: context),
                  color: MyTheme.golden,
                  shadowColor: MyTheme.golden_shadow,
                  onTap: () => onPressBuyNow(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget bottomTap(
    BuildContext context, {
    required String text,
    required Color color,
    required Color shadowColor,
    required void Function() onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingSmall,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusHalfSmall),
        child: AnimatedContainer(
          duration: const Duration(
            milliseconds: AppDimensions.animationDefaultInMillis,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusHalfSmall),
            color: _stock == 0 ? Colors.grey : color,
            boxShadow: _stock == 0
                ? null
                : [
                    BoxShadow(
                      color: color,
                      blurRadius: 20,
                      spreadRadius: 0.0,
                      offset: const Offset(0.0, 5.0),
                    )
                  ],
          ),
          height: 50,
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Row buildRatingAndWishButtonRow() {
    return Row(
      children: [
        RatingBar(
          itemSize: 15.0,
          ignoreGestures: true,
          initialRating: double.parse(_productDetails!.rating.toString()),
          direction: Axis.horizontal,
          allowHalfRating: false,
          itemCount: 5,
          ratingWidget: RatingWidget(
            full: const Icon(Icons.star, color: Colors.amber),
            half: const Icon(Icons.star_half, color: Colors.amber),
            empty:
                const Icon(Icons.star, color: Color.fromRGBO(224, 224, 225, 1)),
          ),
          itemPadding: const EdgeInsets.only(right: 1.0),
          onRatingUpdate: (rating) {
            //print(rating);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            "(" + _productDetails!.rating_count.toString() + ")",
            style: const TextStyle(
                color: Color.fromRGBO(152, 152, 153, 1), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Row buildShippingTime() {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            'estimate_shipping_time_ucf'.tr(context: context),
            style: const TextStyle(
                color: Color.fromRGBO(152, 152, 153, 1), fontSize: 10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            "${_productDetails!.estShippingTime}  ${'days_ucf'.tr(context: context)}",
            style: const TextStyle(
                color: Color.fromRGBO(152, 152, 153, 1), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget buildBrandRow() {
    return (_productDetails!.brand?.id ?? -1) > 0
        ? InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return BrandProducts(
                  slug: _productDetails!.brand!.slug!,
                );
              }));
            },
            child: Row(
              children: [
                Padding(
                  padding: app_language_rtl.$!
                      ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                      : const EdgeInsets.only(right: 8.0),
                  child: Container(
                    width: 75,
                    child: Text(
                      'brand_ucf'.tr(context: context),
                      style: const TextStyle(
                          color: Color(0xff6B7377),
                          fontSize: 10,
                          fontFamily: 'Public Sans'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    _productDetails!.brand!.name!,
                    style: const TextStyle(
                        color: Color(0xff3E4447),
                        fontFamily: 'Public Sans',
                        fontWeight: FontWeight.bold,
                        fontSize: 10),
                  ),
                ),
              ],
            ),
          )
        : Container();
  }

  Widget buildExpandableDescription() {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: AppDimensions.animationDefaultInMillis),
      width: DeviceInfo(context).width,
      height: isExpanded ? webViewHeight : min(height, webViewHeight ?? height),
      alignment: Alignment.topCenter,
      child: Stack(
        children: [
          WebViewWidget(controller: controller),
          AnimatedPositioned(
            duration: const Duration(
              milliseconds: AppDimensions.animationDefaultInMillis,
            ),
            top: (webViewHeight ?? 0) > height ? 0 : height,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              alignment: AlignmentDirectional.bottomEnd,
              decoration: !isExpanded
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.5, 1],
                        colors: [
                          Colors.transparent,
                          Theme.of(context).primaryColor,
                        ],
                      ),
                    )
                  : null,
              child: Btn.basic(
                onPressed: viewMore,
                child: Text(
                  isExpanded
                      ? 'less'.tr(context: context)
                      : 'view_more'.tr(context: context),
                  style: TextStyle(
                    color: isExpanded ? null : Colors.white,
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        spreadRadius: 1,
                        offset: const Offset(0.0, 3.0),
                      )
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  void viewMore() {
    setState(() {
      isExpanded = !isExpanded;
    });
    getDescriptionHeight();
  }

  int errorsTimes = 0;

  Future<void> getDescriptionHeight() async {
    if (errorsTimes > 3) return;

    errorsTimes++;
    try {
      final String value = (await controller.runJavaScriptReturningResult(
        "document.getElementById('scaled-frame').clientHeight",
      ))
          .toString();
      if (value.trim() == 'null' && webViewHeight == null) {
        throw "value (webViewHeight) is null";
      }
      webViewHeight = double.parse(value.toString());
      errorsTimes = 0;

      setState(() {});
    } catch (e) {
      recordError(e, StackTrace.current);
      print("Error in runJavaScriptReturningResult : $e - times $errorsTimes");
      return await getDescriptionHeight();
    }
  }

  Widget buildTopSellingProductList() {
    if (_topProductInit == false && _topProducts.isEmpty) {
      return Column(
        children: [
          Padding(
              padding: const EdgeInsets.only(top: AppDimensions.paddingSmall),
              child: ShimmerHelper().buildBasicShimmer(
                height: 75.0,
              )),
          Padding(
              padding: const EdgeInsets.only(top: AppDimensions.paddingSmall),
              child: ShimmerHelper().buildBasicShimmer(
                height: 75.0,
              )),
          Padding(
              padding: const EdgeInsets.only(top: AppDimensions.paddingSmall),
              child: ShimmerHelper().buildBasicShimmer(
                height: 75.0,
              )),
        ],
      );
    } else if (_topProducts.isNotEmpty) {
      return ListView.separated(
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemCount: _topProducts.length,
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(AppDimensions.paddingDefault),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemBuilder: (context, index) {
          return TopSellingProductsCard(
              id: _topProducts[index].id,
              slug: _topProducts[index].slug,
              image: _topProducts[index].thumbnail_image,
              name: _topProducts[index].name,
              main_price: _topProducts[index].main_price,
              stroked_price: _topProducts[index].stroked_price,
              has_discount: _topProducts[index].has_discount);
        },
      );
    } else {
      return Container(
          height: 100,
          child: Center(
              child: Text(
                  'no_top_selling_products_from_this_seller'
                      .tr(context: context),
                  style: const TextStyle(color: MyTheme.font_grey))));
    }
  }

  Widget buildProductsMayLikeList() {
    if (_relatedProductInit == false && _relatedProducts.isEmpty) {
      return Row(
        children: [
          Padding(
              padding: app_language_rtl.$!
                  ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                  : const EdgeInsets.only(right: 8.0),
              child: ShimmerHelper().buildBasicShimmer(
                  height: 120.0,
                  width: (MediaQuery.sizeOf(context).width - 32) / 3)),
          Padding(
              padding: app_language_rtl.$!
                  ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                  : const EdgeInsets.only(right: 8.0),
              child: ShimmerHelper().buildBasicShimmer(
                  height: 120.0,
                  width: (MediaQuery.sizeOf(context).width - 32) / 3)),
          Padding(
              padding: const EdgeInsets.only(right: 0.0),
              child: ShimmerHelper().buildBasicShimmer(
                  height: 120.0,
                  width: (MediaQuery.sizeOf(context).width - 32) / 3)),
        ],
      );
    } else if (_relatedProducts.isNotEmpty) {
      return SingleChildScrollView(
        child: SizedBox(
          height: 248,
          child: ListView.separated(
            separatorBuilder: (context, index) => const SizedBox(
              width: 16,
            ),
            padding: const EdgeInsets.all(AppDimensions.paddingDefault),
            itemCount: _relatedProducts.length,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              return MiniProductCard(
                  id: _relatedProducts[index].id,
                  slug: _relatedProducts[index].slug,
                  image: _relatedProducts[index].thumbnail_image,
                  name: _relatedProducts[index].name,
                  main_price: _relatedProducts[index].main_price,
                  stroked_price: _relatedProducts[index].stroked_price,
                  isWholesale: _relatedProducts[index].isWholesale,
                  has_discount: _relatedProducts[index].has_discount);
            },
          ),
        ),
      );
    } else {
      return Container(
          height: 100,
          child: Center(
              child: Text(
            'no_related_product'.tr(context: context),
            style: const TextStyle(color: MyTheme.font_grey),
          )));
    }
  }

  Row buildProductImageSection() {
    if (_productImageList.isEmpty) {
      return Row(
        children: [
          Container(
            width: 40,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSupSmall),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 40.0, width: 40.0),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSupSmall),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 40.0, width: 40.0),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSupSmall),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 40.0, width: 40.0),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSupSmall),
                  child: ShimmerHelper()
                      .buildBasicShimmer(height: 40.0, width: 40.0),
                ),
              ],
            ),
          ),
          Flexible(
            child: Padding(
              padding:
                  const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
              child: ShimmerHelper().buildBasicShimmer(
                height: 190.0,
              ),
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 250,
            width: 64,
            child: Scrollbar(
              controller: _imageScrollController,
              thumbVisibility: false,
              thickness: 4.0,
              child: Padding(
                padding: app_language_rtl.$!
                    ? const EdgeInsets.only(left: AppDimensions.paddingSmall)
                    : const EdgeInsets.only(right: 8.0),
                child: ListView.builder(
                    itemCount: _productImageList.length,
                    scrollDirection: Axis.vertical,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final int itemIndex = index;
                      return GestureDetector(
                        onTap: () {
                          _currentImage = itemIndex;
                          print(_currentImage);
                          setState(() {});
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          margin: const EdgeInsets.symmetric(
                              vertical: 4.0, horizontal: 2.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                AppDimensions.radiusNormal),
                            border: Border.all(
                                color: _currentImage == itemIndex
                                    ? Theme.of(context).primaryColor
                                    : const Color.fromRGBO(112, 112, 112, .3),
                                width: _currentImage == itemIndex ? 2 : 1),
                            //shape: BoxShape.rectangle,
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusNormal),
                              child:
                                  /*Image.asset(
                                        singleProduct.product_images[index])*/
                                  FadeInImage.assetNetwork(
                                placeholder: AppImages.placeholder,
                                image: _productImageList[index],
                                fit: BoxFit.contain,
                              )),
                        ),
                      );
                    }),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              openPhotoDialog(context, _productImageList[_currentImage]);
            },
            child: Container(
              height: 250,
              width: MediaQuery.sizeOf(context).width - 96,
              child: Container(
                  child: FadeInImage.assetNetwork(
                placeholder: AppImages.placeholderRectangle,
                image: _productImageList[_currentImage],
                fit: BoxFit.scaleDown,
              )),
            ),
          ),
        ],
      );
    }
  }

  Future openPhotoDialog(BuildContext context, path) => showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            child: Container(
                child: Stack(
              children: [
                PhotoView(
                  enableRotation: true,
                  heroAttributes: const PhotoViewHeroAttributes(tag: "someTag"),
                  imageProvider: NetworkImage(path),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    decoration: const ShapeDecoration(
                      color: MyTheme.medium_grey_50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(AppDimensions.radius),
                          bottomRight: Radius.circular(AppDimensions.radius),
                          topRight: Radius.circular(AppDimensions.radius),
                          topLeft: Radius.circular(AppDimensions.radius),
                        ),
                      ),
                    ),
                    width: 40,
                    height: 40,
                    child: IconButton(
                      icon: const Icon(Icons.clear, color: MyTheme.white),
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                    ),
                  ),
                ),
              ],
            )),
          );
        },
      );

  String makeHtml(String string) {
    return """
<!DOCTYPE html>
<html>

<head>

<meta name="viewport" content="width=device-width, initial-scale=1.0">

    <link rel="stylesheet" href="${AppConfig.RAW_BASE_URL}/public/assets/css/vendors.css">
  <style>
  *{
  margin:0 !important;
  padding:0 !important;
  }

    #scaled-frame {
    }
  </style>
</head>

<body id="main_id">
  <div id="scaled-frame">
$string
  </div>
</body>

</html>
""";
  }
}

class _ItemDataWidget extends StatelessWidget {
  const _ItemDataWidget({
    this.beforeDataInLine = const [],
    required this.title,
    required this.data,
  });

  final String title;
  final String data;
  final List<InlineSpan> beforeDataInLine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
          ),
        ),
        RichText(
          text: TextSpan(
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            children: [
              ...beforeDataInLine,
              TextSpan(text: data),
            ],
          ),
        ),
      ],
    );
  }
}

class QuantityButtonWidget extends StatelessWidget {
  const QuantityButtonWidget({
    super.key,
    required this.icon,
    required this.doWhen,
    required this.textWhenDont,
    required this.onPressed,
  });
  final IconData icon;
  final bool doWhen;
  final String textWhenDont;
  final void Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (doWhen) {
          onPressed();
        } else {
          ToastComponent.showDialog(textWhenDont, isError: true);
        }
      },
      borderRadius: BorderRadius.circular(100),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 6,
              spreadRadius: 0.0,
              offset: const Offset(0.0, 3.0),
            ),
          ],
        ),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: MyTheme.dark_grey),
      ),
    );
  }
}

int distributeWholesale({
  required int index,
  required int total,
  required List<Wholesale> list,
}) {
  int remainder = total;
  int resultCount = 0;

  for (int i = list.length - 1; i >= index; i--) {
    final int minQty = list[i].minQty;
    resultCount = 0;
    if (remainder < minQty) continue;

    resultCount = (remainder / minQty).floor();
    remainder = remainder % minQty;
  }

  return resultCount;
}

bool makeNewVisualWholesale(List<Wholesale>? wholesales) =>
    whole_sale_addon_installed.$ &&
    wholesales?.isNotEmpty == true &&
    AppConfig.businessSettingsData.usePackingWholesaleProduct;
