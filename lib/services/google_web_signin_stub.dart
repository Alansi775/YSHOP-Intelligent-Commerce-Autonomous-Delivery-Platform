// lib/services/google_web_signin_stub.dart — non-web platforms.
// Mobile uses the imperative GoogleSignIn().signIn() flow instead (it
// reliably returns an ID token there, unlike on web), so this widget is
// never actually rendered on those platforms.
import 'package:flutter/material.dart';

Widget buildGoogleWebSignInButton({
  required Widget child,
  double width = 400,
  double height = 52,
}) => const SizedBox.shrink();
