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

/// ✨ REINVENTED UI COMPONENTS
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
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.15), // رمادي واضح في Light Mode
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Frosted Glass Effect
          child: TextFormField(
            controller: controller,
            obscureText: isSecure,
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
              suffixIcon: isSecure 
                  ? Icon(Icons.lock_outline, size: 18, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3))
                  : null,
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
  }) {
    // Primary Color: Light Blue
    final Color btnColor = isPrimary
        ? (isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A)) // معكوس: فاتح في داكن، غامق في فاتح
        : Colors.transparent;
        
    final Color textColor = isPrimary
        ? (isDark ? Colors.black : Colors.white) // النص معاكس أيضاً
        : (isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy);

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
            borderRadius: BorderRadius.circular(2), // Very sharp, high-end feel
            side: isPrimary 
              ? BorderSide.none 
              : BorderSide(color: isDark ? Colors.white24 : Colors.black.withOpacity(0.24)),
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 20, 
                width: 20, 
                child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
              )
            : Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 2.0, // W I D E letter spacing looks expensive
                ),
              ),
      ),
    );
  }

  /// 🛍️ CUSTOMER FORMS
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
          Expanded(child: luxuryInput(placeholder: "FIRST NAME", controller: nameController, isDark: isDark)),
          const SizedBox(width: 15),
          Expanded(child: luxuryInput(placeholder: "SURNAME", controller: surnameController, isDark: isDark)),
        ]),
        luxuryInput(placeholder: "NATIONAL ID / RESIDENCY", controller: nationalIdController, keyboardType: TextInputType.number, isDark: isDark),
        luxuryInput(placeholder: "PHONE NUMBER", controller: phoneController, keyboardType: TextInputType.phone, isDark: isDark),
        
        // Map Selection - Styled as a secondary luxury button
        Container(
          margin: const EdgeInsets.only(bottom: 15),
          child: prestigeButton(
            title: addressController.text.isEmpty ? "SELECT LOCATION ON MAP" : "📍 ${addressController.text}", 
            action: onSelectMap, 
            isLoading: false, 
            isDark: isDark,
            isPrimary: false
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
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  storeTypeController.text.isEmpty ? "SELECT BUSINESS CATEGORY" : storeTypeController.text.toUpperCase(),
                  style: TextStyle(
                    color: isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy,
                    letterSpacing: 1,
                    fontSize: 14,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: isDark ? LuxuryTheme.kLightBlueAccent : LuxuryTheme.kDeepNavy),
              ],
            ),
          ),
        ),

        // Map Button
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: prestigeButton(
            title: addressController.text.isEmpty ? "PINPOINT HEADQUARTERS" : "📍 ${addressController.text}", 
            action: onSelectMap, 
            isLoading: false, 
            isDark: isDark,
            isPrimary: false
          ),
        ),

        luxuryInput(placeholder: "OFFICIAL PHONE", controller: phoneController, keyboardType: TextInputType.phone, isDark: isDark),
        luxuryInput(placeholder: "BUSINESS EMAIL", controller: emailController, keyboardType: TextInputType.emailAddress, isDark: isDark),
        luxuryInput(placeholder: "ADMIN PASSWORD", controller: passwordController, isSecure: true, isDark: isDark),
        luxuryInput(placeholder: "CONFIRM", controller: confirmPasswordController, isSecure: true, onSubmitted: (_) => onRequest(), isDark: isDark),
        
        const SizedBox(height: 10),
        prestigeButton(title: "SUBMIT APPLICATION", action: onRequest, isLoading: isLoading, isDark: isDark),
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
      child: TextButton(
        onPressed: onToggle,
        child: Text(
          isStoreOwner ? "← Return to Customer Entrance" : "Are you a Merchant? Enter Here →",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
            fontSize: 13,
            letterSpacing: 0.5,
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: GestureDetector(
          onTap: onToggle,
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
                fontFamily: 'Arial',
              ),
              children: [
                TextSpan(text: showSignUp ? "Already a member? " : "New to YSHOP? "),
                TextSpan(
                  text: showSignUp ? "Sign In" : "Create Account",
                  style: TextStyle(
                    color: isDark ? LuxuryTheme.kLightBlueAccent : LuxuryTheme.kDeepNavy,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(forceStrutHeight: true),
          ),
        ),
      ),
    );
  }
}