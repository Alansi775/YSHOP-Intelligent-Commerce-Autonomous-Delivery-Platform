import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui'; // For blur effects

//  COLOR PALETTE (Blue, Black, White)
class LuxuryTheme {
  // Dark Mode
  static const Color kDarkBackground = Color(0xFF0A0A0A); 
  static const Color kDarkSurface = Color(0xFF1A1A1A);
  static const Color kLightBlueAccent = Color(0xFF42A5F5); // Light Blue
  static const Color kPlatinum = Color(0xFFFFFFFF);
  
  // Light Mode
  static const Color kLightBackground = Color(0xFFFAFAFA);
  static const Color kLightSurface = Color(0xFFFFFFFF);
  static const Color kDeepNavy = Color(0xFF1A1A1A);
  
  static bool isDark(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark;
}

/// Password field with a working show/hide toggle. Split out as a
/// StatefulWidget (rather than inline in the static luxuryInput builder)
/// because each field needs its own independent obscure/visible state.
class _ObscurableLuxuryInput extends StatefulWidget {
  final String placeholder;
  final TextEditingController controller;
  final Function(String)? onSubmitted;
  final bool readOnly;
  final bool isDark;

  const _ObscurableLuxuryInput({
    required this.placeholder,
    required this.controller,
    required this.isDark,
    this.onSubmitted,
    this.readOnly = false,
  });

  @override
  State<_ObscurableLuxuryInput> createState() => _ObscurableLuxuryInputState();
}

class _ObscurableLuxuryInputState extends State<_ObscurableLuxuryInput> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    const double inputRadius = 18;
    final isDark = widget.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(inputRadius),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(inputRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextFormField(
            controller: widget.controller,
            obscureText: _obscure,
            readOnly: widget.readOnly,
            style: TextStyle(
              color: isDark ? LuxuryTheme.kPlatinum : Colors.black87,
              fontFamily: 'Didot',
              fontSize: 16,
              letterSpacing: 0.5,
            ),
            cursorColor: LuxuryTheme.kLightBlueAccent,
            decoration: InputDecoration(
              labelText: widget.placeholder,
              labelStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.black54,
                fontSize: 14,
                letterSpacing: 1,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onFieldSubmitted: widget.onSubmitted,
          ),
        ),
      ),
    );
  }
}

///  REINVENTED UI COMPONENTS
/// These are not widgets; they are architectural elements.
class SignInUIComponents {

  // --- 1. THE ARCHITECTURAL INPUT FIELD ---
  // Replaces the boring 'UnderlinedTextField'
  static Widget luxuryInput({
    required String placeholder,
    required TextEditingController controller,
    bool isSecure = false,
    TextInputType? keyboardType,
    Function(String)? onSubmitted,
    bool readOnly = false,
    required bool isDark,
  }) {
    if (isSecure) {
      return _ObscurableLuxuryInput(
        placeholder: placeholder,
        controller: controller,
        onSubmitted: onSubmitted,
        readOnly: readOnly,
        isDark: isDark,
      );
    }

    const double inputRadius = 18;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.15), // رمادي واضح في Light Mode
        borderRadius: BorderRadius.circular(inputRadius),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(inputRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Frosted Glass Effect
          child: TextFormField(
            controller: controller,
            obscureText: false,
            keyboardType: keyboardType,
            readOnly: readOnly,
            style: TextStyle(
              color: isDark ? LuxuryTheme.kPlatinum : Colors.black87,
              fontFamily: 'Didot', // Or a serif font if available, adds elegance
              fontSize: 16,
              letterSpacing: 0.5,
            ),
            cursorColor: LuxuryTheme.kLightBlueAccent,
            decoration: InputDecoration(
              labelText: placeholder,
              labelStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.black54,
                fontSize: 14,
                letterSpacing: 1,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
            ),
            onFieldSubmitted: onSubmitted,
          ),
        ),
      ),
    );
  }

  // --- 2. THE PRESTIGE BUTTON ---
  // Replaces the standard 'ElevatedButton'
  static Widget prestigeButton({
    required String title,
    required VoidCallback action,
    required bool isLoading,
    required bool isDark,
    bool isPrimary = true,
    IconData? leadingIcon,
  }) {
    // Primary Color: Light Blue
    final Color btnColor = isPrimary
        ? (isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A)) // معكوس: فاتح في داكن، غامق في فاتح
        : (isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.82));
        
    final Color textColor = isPrimary
        ? (isDark ? Colors.black : Colors.white) // النص معاكس أيضاً
        : (isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy);
    final double borderRadius = 18;

    return Container(
      width: double.infinity,
      height: 55,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        boxShadow: isPrimary && !isLoading ? [
          BoxShadow(
            color: btnColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 5),
          )
        ] : [],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : action,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: isPrimary 
              ? BorderSide.none 
              : BorderSide(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: isLoading
            ? SizedBox(
                height: 20, 
                width: 20, 
                child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (leadingIcon != null) ...[
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      child: Icon(leadingIcon, size: 17, color: textColor),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  ///  CUSTOMER FORMS
  static Widget loginCustomerForm({
    required TextEditingController emailController,
    required TextEditingController passwordController,
    required VoidCallback onLogin,
    required bool isLoading,
    required BuildContext context, // Added Context for Theme access
  }) {
    bool isDark = LuxuryTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        luxuryInput(placeholder: "EMAIL ADDRESS", controller: emailController, isDark: isDark, keyboardType: TextInputType.emailAddress),
        luxuryInput(placeholder: "PASSWORD", controller: passwordController, isSecure: true, onSubmitted: (_) => onLogin(), isDark: isDark),
        const SizedBox(height: 10),
        prestigeButton(title: "ENTER BOUTIQUE", action: onLogin, isLoading: isLoading, isDark: isDark),
      ],
    );
  }

  static Widget googleSignInDivider({required bool isDark}) {
    final line = (isDark ? Colors.white : Colors.black).withOpacity(0.12);
    final label = (isDark ? Colors.white : Colors.black).withOpacity(0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: line, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: label, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: line, thickness: 1)),
        ],
      ),
    );
  }

  static Widget googleSignInButton({
    required VoidCallback onTap,
    required bool isLoading,
    required bool isDark,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: googleSignInButtonFace(isDark: isDark, isLoading: isLoading),
      ),
    );
  }

  /// The visual "face" of the Google button — same dark, pill-free luxury
  /// styling as the other form fields/buttons on this screen. Split out
  /// from [googleSignInButton] because web needs this exact look WITHOUT
  /// its own tap handler: the actual click there has to land on Google's
  /// real rendered button (stacked invisibly on top, see
  /// google_web_signin_web.dart) rather than on this widget, since only
  /// Google's own button reliably returns an ID token in a browser.
  static Widget googleSignInButtonFace({
    required bool isDark,
    required bool isLoading,
  }) {
    return Container(
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (isDark ? Colors.white : Colors.black).withOpacity(0.15)),
      ),
      child: isLoading
          ? Center(
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.white70 : Colors.black54),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GooglePainter())),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                ),
              ],
            ),
    );
  }

  static Widget signUpCustomerForm({
    required TextEditingController nameController,
    required TextEditingController surnameController,
    required TextEditingController nationalIdController,
    required TextEditingController phoneController,
    required TextEditingController addressController,
    required TextEditingController buildingInfoController,
    required TextEditingController apartmentNumberController,
    required TextEditingController deliveryInstructionsController,
    required TextEditingController emailController,
    required TextEditingController passwordController,
    required TextEditingController confirmPasswordController,
    required VoidCallback onSelectMap,
    required VoidCallback onSignUp,
    required bool isLoading,
    required BuildContext context,
  }) {
    bool isDark = LuxuryTheme.isDark(context);
    return Column(
      children: [
        Row(children: [
          Expanded(child: luxuryInput(placeholder: "NAME", controller: nameController, isDark: isDark)),
          const SizedBox(width: 15),
          Expanded(child: luxuryInput(placeholder: "SURNAME", controller: surnameController, isDark: isDark)),
        ]),
        luxuryInput(placeholder: "NATIONAL ID / RESIDENCY", controller: nationalIdController, keyboardType: TextInputType.number, isDark: isDark),
        luxuryInput(placeholder: "PHONE NUMBER", controller: phoneController, keyboardType: TextInputType.phone, isDark: isDark),
        
        // Map Selection - Styled as a secondary luxury button
        Container(
          margin: const EdgeInsets.only(bottom: 15),
          child: prestigeButton(
            title: addressController.text.isEmpty ? "PICK ON MAP" : "📍 ${addressController.text}", 
            action: onSelectMap, 
            isLoading: false, 
            isDark: isDark,
              isPrimary: false,
              leadingIcon: Icons.location_on,
          ),
        ),

        
        luxuryInput(placeholder: "BUILDING NAME (NUMBER)", controller: buildingInfoController, isDark: isDark), 
        luxuryInput(placeholder: "APARTMENT NUMBER", controller: apartmentNumberController, isDark: isDark),
        luxuryInput(placeholder: "DELIVERY INSTRUCTIONS", controller: deliveryInstructionsController, isDark: isDark),
        luxuryInput(placeholder: "EMAIL ACCESS", controller: emailController, keyboardType: TextInputType.emailAddress, isDark: isDark),
        luxuryInput(placeholder: "CREATE PASSWORD", controller: passwordController, isSecure: true, isDark: isDark),
        luxuryInput(placeholder: "CONFIRM PASSWORD", controller: confirmPasswordController, isSecure: true, onSubmitted: (_) => onSignUp(), isDark: isDark),
        
        const SizedBox(height: 10),
        prestigeButton(title: "INITIATE MEMBERSHIP", action: onSignUp, isLoading: isLoading, isDark: isDark),
      ],
    );
  }

  /// 🏢 STORE OWNER FORMS
  static Widget loginStoreOwnerForm({
    required TextEditingController emailController,
    required TextEditingController passwordController,
    required VoidCallback onLogin,
    required bool isLoading,
    required BuildContext context,
  }) {
    bool isDark = LuxuryTheme.isDark(context);
    return Column(
      children: [
        luxuryInput(placeholder: "BUSINESS EMAIL", controller: emailController, keyboardType: TextInputType.emailAddress, isDark: isDark),
        luxuryInput(placeholder: "ACCESS KEY", controller: passwordController, isSecure: true, onSubmitted: (_) => onLogin(), isDark: isDark),
        const SizedBox(height: 10),
        prestigeButton(title: "ACCESS DASHBOARD", action: onLogin, isLoading: isLoading, isDark: isDark),
      ],
    );
  }

  static Widget requestStoreOwnerForm({
    required TextEditingController storeNameController,
    required TextEditingController storeTypeController,
    required TextEditingController addressController,
    required TextEditingController phoneController,
    required TextEditingController emailController,
    required TextEditingController passwordController,
    required TextEditingController confirmPasswordController,
    required VoidCallback onSelectStoreType,
    required VoidCallback onSelectMap,
    required VoidCallback onRequest,
    required bool isLoading,
    required BuildContext context,
  }) {
    bool isDark = LuxuryTheme.isDark(context);
    return Column(
      children: [
        luxuryInput(placeholder: "BRAND NAME", controller: storeNameController, isDark: isDark),
        
        // Store Type Selector
        GestureDetector(
          onTap: onSelectStoreType,
          child: Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    storeTypeController.text.isEmpty ? "SELECT BUSINESS TYPE" : storeTypeController.text.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                      letterSpacing: 1,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_drop_down, color: isDark ? LuxuryTheme.kLightBlueAccent : LuxuryTheme.kDeepNavy),
              ],
            ),
          ),
        ),

        // Map Button
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: prestigeButton(
            title: addressController.text.isEmpty ? "PICK ON MAP" : "📍 ${addressController.text}", 
            action: onSelectMap, 
            isLoading: false, 
            isDark: isDark,
            isPrimary: false,
            leadingIcon: Icons.location_on
          ),
        ),

        luxuryInput(placeholder: "OFFICIAL PHONE", controller: phoneController, keyboardType: TextInputType.phone, isDark: isDark),
        luxuryInput(placeholder: "BUSINESS EMAIL", controller: emailController, keyboardType: TextInputType.emailAddress, isDark: isDark),
        luxuryInput(placeholder: "ADMIN PASSWORD", controller: passwordController, isSecure: true, isDark: isDark),
        luxuryInput(placeholder: "CONFIRM", controller: confirmPasswordController, isSecure: true, onSubmitted: (_) => onRequest(), isDark: isDark),
        
        const SizedBox(height: 10),
        prestigeButton(title: "SUBMIT", action: onRequest, isLoading: isLoading, isDark: isDark),
      ],
    );
  }

  /// 📟 MESSAGE DISPLAY (The Notification Bar)
  static Widget messageDisplay({
    required String message,
    required bool isDark,
  }) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: LuxuryTheme.kLightBlueAccent, width: 3)),
        gradient: LinearGradient(
          colors: isDark 
            ? [Color(0xFF2C2C2E), Color(0xFF1C1C1E)] 
            : [Color(0xFFF0F0F0), Color(0xFFFFFFFF)],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: LuxuryTheme.kLightBlueAccent, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
                fontFamily: 'Courier', // Tech feel
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Centered error dialog — replaces the old bottom-of-form message that
  /// required scrolling to see, especially on long forms (store signup) and
  /// small Android screens.
  static Future<void> showMessageDialog(
    BuildContext context, {
    required String message,
    required bool isDark,
    bool isSuccess = false,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? LuxuryTheme.kDarkSurface : LuxuryTheme.kLightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: Icon(
          isSuccess ? Icons.mark_email_read_outlined : Icons.error_outline,
          color: isSuccess ? Colors.greenAccent : Colors.redAccent,
          size: 32,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 15,
            fontFamily: 'Courier',
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onDismiss?.call();
            },
            style: TextButton.styleFrom(
              backgroundColor: isSuccess ? Colors.greenAccent.shade700 : LuxuryTheme.kLightBlueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 🎚️ STORE OWNER SECTION HEADER
  static Widget storeOwnerSectionHeader({
    required bool isNewStoreOwner,
    required VoidCallback onToggleNewStoreOwner,
    required bool isDark,
  }) {
    return Column(
      children: [
        Text(
          "PARTNER PORTAL",
          style: TextStyle(
            color: LuxuryTheme.kLightBlueAccent,
            letterSpacing: 3,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Business Access",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 32,
            fontFamily: 'Didot', // Serif for luxury
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 20),
        
        // Custom Segmented Switch
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () { if(isNewStoreOwner) onToggleNewStoreOwner(); },
                  child: Container(
                    decoration: BoxDecoration(
                      color: !isNewStoreOwner 
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "LOGIN",
                      style: TextStyle(
                        color: !isNewStoreOwner 
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.grey : Colors.grey),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () { if(!isNewStoreOwner) onToggleNewStoreOwner(); },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isNewStoreOwner 
                          ? (isDark ? Colors.white : Colors.black)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "APPLY TO JOIN",
                      style: TextStyle(
                        color: isNewStoreOwner 
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.grey : Colors.grey),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  ///  TOGGLE BUTTONS (Minimalist)
  static Widget toggleOwnershipButton({
    required bool isStoreOwner,
    required VoidCallback onToggle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                ),
              ),
              child: Text(
                isStoreOwner ? "← Return to Customer Entrance" : "Are you a Store Owner?\n Enter Here →",
                softWrap: true,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget toggleSignUpLoginButton({
    required bool showSignUp,
    required VoidCallback onToggle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 14,
                    fontFamily: 'Arial',
                  ),
                  children: [
                    TextSpan(text: showSignUp ? "Already a member?\n " : "New to YSHOP?\n "),
                    TextSpan(
                      text: showSignUp ? "Sign In" : "Create Account",
                      style: TextStyle(
                        color: isDark ? LuxuryTheme.kLightBlueAccent : LuxuryTheme.kDeepNavy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                strutStyle: const StrutStyle(forceStrutHeight: true),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hand-painted Google "G" mark (four-color arcs) — avoids bundling the
/// official asset while still reading unmistakably as the Google logo.
class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.22;
    final radius = (size.width - strokeWidth) / 2;
    final center = rect.center;

    Paint arcPaint(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    void drawArc(Color color, double startDeg, double sweepDeg) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startDeg * 3.1415926535 / 180,
        sweepDeg * 3.1415926535 / 180,
        false,
        arcPaint(color),
      );
    }

    drawArc(const Color(0xFF4285F4), -45, 95);   // blue (right)
    drawArc(const Color(0xFF34A853), 55, 80);    // green (bottom)
    drawArc(const Color(0xFFFBBC05), 135, 80);   // yellow (left)
    drawArc(const Color(0xFFEA4335), 215, 90);   // red (top)

    // Horizontal bar (the "G" crossbar)
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - strokeWidth * 0.28, radius * 0.95, strokeWidth * 0.56),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GooglePainter oldDelegate) => false;
}