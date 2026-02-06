
import 'package:app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomLogoAppBar extends AppBar {
  CustomLogoAppBar({super.key})
      : super(
          systemOverlayStyle: SystemUiOverlayStyle.light, // 2
          automaticallyImplyLeading: false,
          toolbarHeight: 50,
          flexibleSpace: Container(
            height: 200,
            color: AppColors.background,
          ),
        );
}
