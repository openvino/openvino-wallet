/*
Copyright Gen Digital Inc. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

import 'package:app/scenarios/handle_openid_url.dart';
import 'package:app/services/config_service.dart';
import 'package:app/theme/app_colors.dart';
import 'package:app/widgets/common_logo_appbar.dart';
import 'package:app/widgets/primary_input_field.dart';
import 'package:app/widgets/primary_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallet_sdk/wallet_sdk.dart';
import 'views/dashboard.dart';
import 'package:uni_links/uni_links.dart'
    if (dart.library.js_interop) 'stubs/uni_links_stub.dart';

final WalletSDKPlugin = WalletSDK();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.init();
  try {
    await WalletSDKPlugin.initSDK(ConfigService.config.didResolverURI);
  } catch (e) {
    debugPrint('WalletSDK initSDK failed: $e');
  }
  if (!kIsWeb) {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
    await Future.delayed(const Duration(seconds: 3));
    FlutterNativeSplash.remove();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: CustomLogoAppBar(),
        body: const MainWidget(),
        backgroundColor: AppColors.background,
      ),
      debugShowCheckedModeBanner: false, //Removing Debug Banner
    );
  }
}

class MainWidget extends StatefulWidget {
  const MainWidget({super.key});

  @override
  State<MainWidget> createState() => _MainWidgetState();
}

class _MainWidgetState extends State<MainWidget> {
  final TextEditingController _usernameController = TextEditingController();
  final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
  final LocalAuthentication _localAuth = LocalAuthentication();
  String? initialLink;
  String? _storedUsername;
  bool _biometricsAvailable = false;
  bool _checkingAuthState = true;

  @override
  void initState() {
    super.initState();

    _initAuthState();

    getInitialLink().then((value) {
      initialLink = value;
    });
  }

  Future<void> _initAuthState() async {
    final SharedPreferences pref = await prefs;
    final storedUsername = pref.getString('userLoggedIn');
    bool supported = false;
    try {
      supported = await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } catch (_) {}

    if (!mounted) {
      return;
    }

    setState(() {
      _storedUsername = storedUsername;
      _biometricsAvailable = supported;
      _checkingAuthState = false;
      if (storedUsername != null) {
        _usernameController.text = storedUsername;
      }
    });

    
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuthState) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Image(
                      image: AssetImage('lib/assets/images/aleph_logo.png'),
                      height: 50,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _storedUsername == null
                          ? 'Create your local profile and unlock with biometrics.'
                          : 'Welcome back, unlock with biometrics to continue.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14,
                        color: AppColors.textOnAccent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      decoration: BoxDecoration(
                        color: AppColors.textOnAccent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _storedUsername == null
                                ? 'Create Account'
                                : 'Unlock Wallet',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              fontFamily: 'SF Pro',
                              color: Color(0xff190C21),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_storedUsername == null)
                            PrimaryInputField(
                              textController: _usernameController,
                              titleTextAlign: TextAlign.center,
                              labelText: 'Username',
                              textInputFormatter: FilteringTextInputFormatter
                                  .singleLineFormatter,
                            )
                          else
                            Column(
                              children: [
                                Text(
                                  _storedUsername ?? '',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff190C21),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Biometrics required to unlock.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff6C6D7C),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          PrimaryButton(
                            width: double.infinity,
                            onPressed: () async {
                              // On web, biometrics are not available — skip straight to login.
                              if (kIsWeb) {
                                final username = _storedUsername ?? _usernameController.text.trim();
                                if (username.isEmpty) {
                                  _showMessage('Please enter a username.');
                                  return;
                                }
                                final SharedPreferences pref = await prefs;
                                await pref.setString('userLoggedIn', username);
                                setState(() => _storedUsername = username);
                                _loginCompleted();
                                return;
                              }

                              if (!_biometricsAvailable) {
                                _showMessage(
                                    'Biometric authentication is not available on this device.');
                                return;
                              }

                              if (_storedUsername == null) {
                                final username =
                                    _usernameController.text.trim();
                                if (username.isEmpty) {
                                  _showMessage('Please enter a username.');
                                  return;
                                }
                                final SharedPreferences pref = await prefs;
                                await pref.setString('userLoggedIn', username);
                                setState(() {
                                  _storedUsername = username;
                                });
                              }

                              await _authenticateAndLogin();
                            },
                            child: Text(
                              _storedUsername == null
                                  ? 'Register & Unlock'
                                  : 'Unlock',
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _authenticateAndLogin() async {
    bool authenticated = false;
    try {
      authenticated = await _localAuth.authenticate(
        localizedReason: 'Use biometrics to unlock your wallet.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      authenticated = false;
    }

    if (!mounted) {
      return;
    }

    if (!authenticated) {
      _showMessage('Authentication failed.');
      return;
    }

    _loginCompleted();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _decorativeBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }

  _loginCompleted() async {
    try {
      if (initialLink != null && !kIsWeb) {
        handleOpenIDUrl(context, initialLink!);
        return;
      }
    } on PlatformException {}

    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const Dashboard()));
  }
}
