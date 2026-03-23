/*
Copyright Gen Digital Inc. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

import 'dart:convert';
import 'dart:developer';

import 'package:app/main.dart';
import 'package:app/models/store_credential_data.dart';
import 'package:app/services/storage_service.dart';
import 'package:app/theme/app_colors.dart';
import 'package:flutter/material.dart';

import 'package:app/widgets/primary_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/wallet_sdk/wallet_sdk.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsState createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  final TextEditingController usernameController = TextEditingController();
  final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
  final StorageService _storageService = StorageService();
  bool isSwitched = false;
  String walletSDKVersion = '';
  String gitRevision = '';
  String buildTimeRev = '';

  final List<String> supportedDids = [
    'jwk',
    'key',
    'ion',
  ];
  final List<String> supportedKeyTypes = [
    'ECDSAP384IEEEP1363',
    'ECDSAP256IEEEP1363',
    'ECDSAP521IEEEP1363',
    'ED25519',
    'ECDSAP256DER',
    'ECDSAP384DER',
    'ECDSAP521DER'
  ];
  String? selectedDIDType;
  String? selectedKeyType;

  @override
  initState() {
    checkDevMode();
    checkDidSelected();
    checkKeyTypeSelected();
    getUserDetails();
    getVersionDetails();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          toolbarHeight: 50,
          automaticallyImplyLeading: false,
          title: const Text(
            'Settings',
            style: TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro',
                color: AppColors.textOnAccent),
          ),
          backgroundColor: AppColors.background,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Account',
                  style: TextStyle(
                    letterSpacing: 1.2,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.person, color: AppColors.textOnAccent),
                    ),
                    title: Text(
                      usernameController.text.isEmpty
                          ? 'Guest'
                          : usernameController.text,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Username',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Actions',
                  style: TextStyle(
                    letterSpacing: 1.2,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: Column(
                      children: [
                        PrimaryButton(
                          width: double.infinity,
                          onPressed: signOut,
                          child: const Text(
                            'Sign Out',
                            style: TextStyle(
                                fontSize: 16, color: AppColors.textOnAccent),
                          ),
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          width: double.infinity,
                          onPressed: _confirmRestore,
                          child: const Text(
                            'Restore Application',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.red,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This removes local credentials and settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }

  saveDevMode() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool('devmode', isSwitched);
  }

  getVersionDetails() async {
    var walletSDKPlugin = WalletSDK();
    var versionDetailResp = await walletSDKPlugin.getVersionDetails();
    if (versionDetailResp == null) return;
    var didDocEncoded = json.encode(versionDetailResp);
    Map<String, dynamic> responseJson = json.decode(didDocEncoded);
    walletSDKVersion = responseJson['walletSDKVersion'];
    gitRevision = responseJson['gitRevision'];
    buildTimeRev = responseJson['buildTimeRev'];
  }

  getUserDetails() async {
    UserLoginDetails userLoginDetails = await getUser();
    log('userLoginDetails -> $userLoginDetails');
    if (!mounted) {
      return;
    }
    setState(() {
      usernameController.text = userLoginDetails.username ?? '';
    });
  }

  saveDidSelection() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString('didType', selectedDIDType!);
  }

  saveDidKeySelection() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString('keyType', selectedKeyType!);
  }

  checkDevMode() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    setState(() {
      isSwitched = preferences.getBool('devmode') ?? false;
    });
  }

  checkDidSelected() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    setState(() {
      selectedDIDType = preferences.getString('didType') ?? supportedDids.first;
    });
  }

  checkKeyTypeSelected() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    setState(() {
      selectedKeyType =
          preferences.getString('keyType') ?? supportedKeyTypes.first;
    });
  }

  signOut() async {
    Navigator.push(
        context, MaterialPageRoute(builder: (context) => const MyApp()));
  }

  Future<void> _confirmRestore() async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Application'),
        content: const Text(
            'This will delete all local data and credentials. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (restore == true) {
      await _restoreApplication();
    }
  }

  Future<void> _restoreApplication() async {
    final SharedPreferences pref = await prefs;
    await _storageService.deleteAllData();
    await pref.clear();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MyApp()),
      (_) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Application data cleared.')),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: child,
    );
  }
}
