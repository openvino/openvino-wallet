/*
Copyright Gen Digital Inc. All Rights Reserved.

SPDX-License-Identifier: Apache-2.0
*/

// Web implementation of WalletSDK — bridges to the JS functions in web/script.js
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:app/wallet_sdk/wallet_sdk_model.dart';

import 'wallet_sdk_interface.dart';

// ---------------------------------------------------------------------------
// External JS function declarations (map to functions in web/script.js)
// ---------------------------------------------------------------------------

@JS('jsInitSDK')
external JSPromise<JSAny?> _jsInitSDK(JSString didResolverURI);

@JS('jsCreateDID')
external JSPromise<JSAny?> _jsCreateDID(JSString didMethod, JSString keyType);

@JS('jsCreateOpenID4CIInteraction')
external JSPromise<JSAny?> _jsCreateOpenID4CIInteraction(JSString initiateIssuanceURI);

@JS('jsRequestCredentialWithPreAuth')
external JSPromise<JSAny?> _jsRequestCredentialWithPreAuth(JSString userPinEntered);

@JS('jsIssuerURI')
external JSString _jsIssuerURI();

@JS('jsResolveDisplayData')
external JSPromise<JSAny?> _jsResolveDisplayData(JSString issuerURI, JSAny credentials);

@JS('jsGetCredentialID')
external JSPromise<JSAny?> _jsGetCredentialID(JSString credential);

@JS('jsParseResolvedDisplayData')
external JSPromise<JSAny?> _jsParseResolvedDisplayData(JSString resolvedData);

@JS('jsCreateOpenID4VPInteraction')
external JSPromise<JSAny?> _jsCreateOpenID4VPInteraction(JSString authorizationRequest);

@JS('jsGetSubmissionRequirements')
external JSPromise<JSAny?> _jsGetSubmissionRequirements(JSAny credentials);

@JS('jsPresentCredential')
external JSPromise<JSAny?> _jsPresentCredential(JSAny credentials);

@JS('jsVerifierDisplayData')
external JSPromise<JSAny?> _jsVerifierDisplayData();

@JS('jsVerifyCredentialsStatus')
external JSPromise<JSAny?> _jsVerifyCredentialsStatus(JSString credential);

@JS('jsWellKnownDidConfig')
external JSPromise<JSAny?> _jsWellKnownDidConfig(JSString issuerID);

@JS('jsGetIssuerMetadata')
external JSPromise<JSAny?> _jsGetIssuerMetadata();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts a JS object to a clean Dart Map via dartify + JSON round-trip.
Map<String, dynamic> _toMap(JSAny? jsObj) {
  return json.decode(json.encode(jsObj?.dartify())) as Map<String, dynamic>;
}

List<dynamic> _toList(JSAny? jsObj) {
  return json.decode(json.encode(jsObj?.dartify())) as List<dynamic>;
}

/// Converts a Dart List<String> to a JS array.
JSArray<JSString> _toJSArray(List<String> list) =>
    list.map((e) => e.toJS).toList().toJS;

// ---------------------------------------------------------------------------
// WalletSDK web implementation
// ---------------------------------------------------------------------------

class WalletSDK extends WalletPlatform {
  // --- Initialisation -------------------------------------------------------

  Future<void> initSDK(String didResolverURI) async {
    await _jsInitSDK(didResolverURI.toJS).toDart;
  }

  // --- DID ------------------------------------------------------------------

  Future<CreateDID> createDID(String didMethodType, String didKeyType) async {
    final result = await _jsCreateDID(didMethodType.toJS, didKeyType.toJS).toDart;
    final map = _toMap(result);
    return CreateDID(
      did: map['did'] as String,
      didDoc: json.encode(map['didDoc']),
    );
  }

  Future<String?> fetchStoredDID(String didID) async => null;

  // --- Issuance -------------------------------------------------------------

  /// Maps jsCreateOpenID4CIInteraction → {pinRequired, authorizationURLLink}
  /// to stay compatible with the mobile flow handler.
  Future<Map<Object?, Object?>?> initialize(
      String qrCode, Map<String, dynamic>? authCodeArgs) async {
    final result = await _jsCreateOpenID4CIInteraction(qrCode.toJS).toDart;
    final map = _toMap(result);
    return <Object?, Object?>{
      'pinRequired': map['userPINRequired'] as bool? ?? false,
      'authorizationURLLink': '',
    };
  }

  Future<List<CredentialWithId>> requestCredential(String userPinEntered,
      {String? attestationVC}) async {
    final credResult =
        await _jsRequestCredentialWithPreAuth(userPinEntered.toJS).toDart;
    final credStr = credResult?.dartify() as String;
    final idResult = await _jsGetCredentialID(credStr.toJS).toDart;
    final credID = idResult?.dartify() as String;
    return [CredentialWithId(id: credID, content: credStr)];
  }

  Future<bool> requireAcknowledgment() async => false;

  Future<String> noConsentAcknowledgement() async => '';

  void acknowledgeSuccess() {}

  void acknowledgeReject() {}

  Future<WalletSDKError> parseWalletSDKError(
      {required String localizedErrorMessage}) async {
    return WalletSDKError(
        code: '', category: '', details: localizedErrorMessage, traceID: '');
  }

  Future<String> requestCredentialWithAuth(String redirectURIWithParams) async {
    throw UnimplementedError('requestCredentialWithAuth is not supported on web');
  }

  Future<String> requestCredentialWithWalletInitiatedFlow(
      String redirectURIWithParams) async {
    throw UnimplementedError(
        'requestCredentialWithWalletInitiatedFlow is not supported on web');
  }

  Future<String?> issuerURI() async => _jsIssuerURI().toDart;

  Future<CredentialsDisplayData> resolveDisplayData(
      List<String> credentials, String issuerURI) async {
    final result = await _jsResolveDisplayData(
        issuerURI.toJS, _toJSArray(credentials)).toDart;
    return CredentialsDisplayData.fromMap(_toMap(result));
  }

  Future<CredentialDisplayData> parseCredentialDisplayData(
      String resolvedCredentialDisplayData) async {
    final result = await _jsParseResolvedDisplayData(
        resolvedCredentialDisplayData.toJS).toDart;
    return CredentialDisplayData.fromMap(_toMap(result));
  }

  Future<IssuerDisplayData> parseIssuerDisplay(String issuerDisplayData) async {
    return IssuerDisplayData.fromMap(
        json.decode(issuerDisplayData) as Map<String, dynamic>);
  }

  Future<CredentialOfferDisplayData> getCredentialOfferDisplayData() async {
    final result = await _jsGetIssuerMetadata().toDart;
    final map = _toMap(result);
    final displays = (map['localizedIssuerDisplays'] as List<dynamic>?) ?? [];
    final first = displays.isNotEmpty
        ? displays.first as Map<String, dynamic>
        : <String, dynamic>{};
    return CredentialOfferDisplayData(
      issuer: IssuerDisplayData(
        name: first['name'] as String? ?? '',
        locale: first['locale'] as String? ?? '',
        url: map['credentialIssuer'] as String? ?? '',
        logo: first['logo']?['url'] as String?,
        textColor: first['style']?['text']?['color'] as String?,
        backgroundColor: first['style']?['background']?['color'] as String?,
      ),
      offeredCredentials: [],
    );
  }

  // --- Presentation ---------------------------------------------------------

  Future<List<String>> processAuthorizationRequest(
      {required String authorizationRequest,
      List<String>? storedCredentials}) async {
    await _jsCreateOpenID4VPInteraction(authorizationRequest.toJS).toDart;
    return [];
  }

  Future<List<Object?>> getCustomScope() async => [];

  Future<List<SubmissionRequirement>> getSubmissionRequirements(
      {required List<String>? storedCredentials}) async {
    final result = await _jsGetSubmissionRequirements(
        _toJSArray(storedCredentials ?? [])).toDart;
    return _toList(result)
        .map((obj) =>
            SubmissionRequirement.fromMap(obj as Map<String, dynamic>))
        .toList();
  }

  Future<void> presentCredential(
      {required List<String> selectedCredentials,
      Map<String, dynamic>? customScopeList,
      String? attestationVC}) async {
    await _jsPresentCredential(_toJSArray(selectedCredentials)).toDart;
  }

  Future<VerifierDisplayData> getVerifierDisplayData() async {
    final result = await _jsVerifierDisplayData().toDart;
    final map = _toMap(result);
    return VerifierDisplayData(
      name: map['name'] as String? ?? '',
      did: map['did'] as String? ?? '',
      logoURI: (map['logoURI'] ?? map['logoUri']) as String? ?? '',
      purpose: map['purpose'] as String? ?? '',
    );
  }

  // --- Trust & status -------------------------------------------------------

  Future<bool> credentialStatusVerifier(String credential) async {
    try {
      final result =
          await _jsVerifyCredentialsStatus(credential.toJS).toDart;
      return result?.dartify() as bool? ?? true;
    } catch (e) {
      if (e.toString().contains('revoked')) return false;
      rethrow;
    }
  }

  Future<WellKnownDidConfig> wellKnownDidConfig(String issuerID) async {
    final result = await _jsWellKnownDidConfig(issuerID.toJS).toDart;
    final map = _toMap(result);
    return WellKnownDidConfig(
      isValid: map['isValid'] as bool? ?? false,
      serviceURL: map['serviceURL'] as String? ?? '',
    );
  }

  Future<EvaluationResult?> evaluateIssuanceTrustInfo() async => null;

  Future<EvaluationResult?> evaluatePresentationTrustInfo() async => null;

  Future<String?> verifyIssuer() async => null;

  // --- Attestation ----------------------------------------------------------

  Future<String> getAttestationVC(
      {required String attestationURL,
      bool disableTLSVerify = false,
      required String attestationPayload,
      String? attestationToken}) async {
    throw UnimplementedError('getAttestationVC is not supported on web');
  }

  // --- Credentials ----------------------------------------------------------

  Future<String?> getCredID(List<String> credentials) async {
    if (credentials.isEmpty) return null;
    final result = await _jsGetCredentialID(credentials.first.toJS).toDart;
    return result?.dartify() as String?;
  }

  Future<String?> getIssuerID(List<String> credentials) async => null;

  // --- Activity logger (no-ops on web) --------------------------------------

  Future<List<Object?>> storeActivityLogger() async => [];

  Future<List<Object?>> parseActivities(List<dynamic> activities) async => [];

  // --- Version --------------------------------------------------------------

  Future<Map<Object?, Object?>?> getVersionDetails() async => null;

  // --- Wallet-initiated flow (not in JS SDK) --------------------------------

  Future<List<SupportedCredentials>> initializeWalletInitiatedFlow(
      String issuerURI, List<String> credentialTypes) async {
    throw UnimplementedError(
        'initializeWalletInitiatedFlow is not supported on web');
  }

  Future<String> createAuthorizationURLWalletInitiatedFlow(
      List<String> scopes,
      List<String> credentialTypes,
      String credentialFormat,
      clientID,
      redirectURI,
      issuerURI) async {
    throw UnimplementedError(
        'createAuthorizationURLWalletInitiatedFlow is not supported on web');
  }
}

String generateRandomString(int length) {
  const characters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  math.Random random = math.Random();
  StringBuffer randomString = StringBuffer();
  for (int i = 0; i < length; i++) {
    randomString.write(characters[random.nextInt(characters.length)]);
  }
  return randomString.toString();
}
