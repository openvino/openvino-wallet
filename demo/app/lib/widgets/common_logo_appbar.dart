import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomLogoAppBar extends AppBar {
  CustomLogoAppBar({super.key})
      : super(
          systemOverlayStyle: SystemUiOverlayStyle.light, // 2
          automaticallyImplyLeading: false,
          title: Image.asset(
            'lib/assets/images/logo.png',
            fit: BoxFit.contain,
            height: 24,
            width: 144,
          ),
          toolbarHeight: 50,
          flexibleSpace: Container(
            height: 200,
            decoration: const BoxDecoration(
                gradient: LinearGradient(
              colors: [Color(0xff691631), Color(0xff8a204b)],
              stops: [0, 1],
            )),
          ),
        );
}
