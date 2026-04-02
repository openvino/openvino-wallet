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
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        automaticallyImplyLeading: false,
        title: Text(pageTitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro',
                color: Color(0xff190c21))),
        backgroundColor: const Color(0xfffcca40),
        actions: addCloseIcon == true
            ? [
                IconButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const Dashboard())),
                  icon: const Icon(Icons.close),
                  color: const Color(0xff190c21),
                ),
              ]
            : [],
        flexibleSpace: Container(
          height: 130,
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: ExactAssetImage('lib/assets/images/glow.png'),
              opacity: 0.55,
              alignment: Alignment.topCenter,
              fit: BoxFit.fill,
            ),
            color: Color(0xfffcca40),
          ),
        ),
      ),
    );
  }
}
