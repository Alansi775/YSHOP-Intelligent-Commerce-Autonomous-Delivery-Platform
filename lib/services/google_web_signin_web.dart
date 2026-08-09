// lib/services/google_web_signin_web.dart — web only.
//
// google_sign_in_web's own source is explicit about this: the imperative
// `GoogleSignIn().signIn()` popup flow "can't reliably provide an idToken"
// on web — Google's Identity Services requires their own rendered button
// to deliver a real ID-token-bearing credential.
//
// An earlier version of this tried to fully re-skin the button by stacking
// a transparent copy of the real Google button on top of a custom-styled
// widget (Opacity(0) + Stack, relying on hit-testing still working through
// zero opacity). That broke the button entirely: `renderButton()` returns a
// platform view (a real DOM node Flutter overlays on the canvas), and
// Flutter Web's Opacity/Stack compositing doesn't reliably carry over to
// that separate DOM layer, so the "invisible" real button ended up
// unclickable. Rendering it directly, visible, is what's actually reliable
// — it's already themed dark/pill via GSIButtonConfiguration below.
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;

Widget buildGoogleWebSignInButton({double width = 300}) {
  return web_gis.renderButton(
    configuration: web_gis.GSIButtonConfiguration(
      type: web_gis.GSIButtonType.standard,
      theme: web_gis.GSIButtonTheme.filledBlack,
      size: web_gis.GSIButtonSize.large,
      text: web_gis.GSIButtonText.continueWith,
      shape: web_gis.GSIButtonShape.pill,
      // Centered (not left) — at 400px width (Google's own max) with a
      // left-aligned logo, the icon+text cluster stayed pinned to the left
      // edge with a big dead zone on the right, reading as "icon far away,
      // button too wide". A narrower, centered button matches the rest of
      // the form's compact luxury inputs much better.
      logoAlignment: web_gis.GSIButtonLogoAlignment.center,
      minimumWidth: width,
    ),
  );
}
