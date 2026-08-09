// lib/services/google_web_signin_web.dart — web only.
//
// google_sign_in_web's own source is explicit about this: the imperative
// `GoogleSignIn().signIn()` popup flow "can't reliably provide an idToken"
// on web — Google's Identity Services requires their own rendered button
// to deliver a real ID-token-bearing credential. `renderButton()` doesn't
// give any styling hooks beyond its own theme presets though, which is why
// the plain button looked like a floating, disconnected image instead of
// matching the rest of the dark form.
//
// The fix: keep the REAL Google button in the DOM (so the click still lands
// on Google's own element and still returns a real token), but make it
// fully transparent and stack it on top of a normal Flutter widget that's
// styled to match the form exactly. `Opacity` hides it visually without
// disabling hit-testing, so the invisible top layer is what actually
// receives the click, while what the user sees is the custom-styled child
// underneath. This is the standard way production apps re-skin a GIS
// button. Sign-in completion is still delivered via AuthManager's
// GoogleSignIn instance's `onCurrentUserChanged` stream, same as before.
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;

Widget buildGoogleWebSignInButton({
  required Widget child,
  double width = 400,
  double height = 52,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: child),
        Opacity(
          opacity: 0.0,
          child: web_gis.renderButton(
            configuration: web_gis.GSIButtonConfiguration(
              type: web_gis.GSIButtonType.standard,
              theme: web_gis.GSIButtonTheme.filledBlack,
              size: web_gis.GSIButtonSize.large,
              text: web_gis.GSIButtonText.continueWith,
              shape: web_gis.GSIButtonShape.pill,
              logoAlignment: web_gis.GSIButtonLogoAlignment.left,
              minimumWidth: width,
            ),
          ),
        ),
      ],
    ),
  );
}
