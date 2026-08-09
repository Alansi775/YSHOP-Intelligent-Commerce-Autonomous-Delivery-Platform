// lib/services/google_web_signin_web.dart — web only.
//
// google_sign_in_web's own source is explicit about this: the imperative
// `GoogleSignIn().signIn()` popup flow "can't reliably provide an idToken"
// on web — Google's Identity Services requires their own rendered button
// (this widget) to deliver a real ID-token-bearing credential. Sign-in
// completion is delivered via AuthManager's GoogleSignIn instance's
// `onCurrentUserChanged` stream, which the caller must already be
// listening to (see AuthManager.googleSignInInstance).
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;

Widget buildGoogleWebSignInButton({double minimumWidth = 380}) {
  return web_gis.renderButton(
    configuration: web_gis.GSIButtonConfiguration(
      type: web_gis.GSIButtonType.standard,
      theme: web_gis.GSIButtonTheme.filledBlack,
      size: web_gis.GSIButtonSize.large,
      text: web_gis.GSIButtonText.continueWith,
      shape: web_gis.GSIButtonShape.pill,
      logoAlignment: web_gis.GSIButtonLogoAlignment.left,
      minimumWidth: minimumWidth,
    ),
  );
}
