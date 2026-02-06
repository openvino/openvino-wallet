import 'package:app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/views/dashboard.dart';

class CustomTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? pageTitle;
  final bool? addCloseIcon;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  const CustomTitleAppBar(
      {super.key,
      required this.height,
      required this.pageTitle,
      this.addCloseIcon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        automaticallyImplyLeading: false,
        title: Text(pageTitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro',
                color: AppColors.textOnAccent)),
        backgroundColor: AppColors.background,
        actions: addCloseIcon == true
            ? [
                IconButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const Dashboard())),
                  icon: const Icon(Icons.close),
                  color: AppColors.textOnAccent,
                ),
              ]
            : [],
        flexibleSpace: Container(
          height: 200,
          color: AppColors.background,
        ),
      ),
    );
  }
}
