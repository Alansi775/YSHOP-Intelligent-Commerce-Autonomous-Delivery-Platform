// lib/widgets/store_card.dart

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/store.dart';
import '../screens/auth/sign_in_ui.dart'; // LuxuryTheme
import '../state_management/theme_manager.dart';
import 'package:provider/provider.dart';
import './shimmer_effect.dart';

class StoreCard extends StatefulWidget {
  final Store store;
  final VoidCallback onTap;

  const StoreCard({Key? key, required this.store, required this.onTap}) : super(key: key);

  @override
  State<StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<StoreCard> {
  bool _isHovering = false;
  
  // مكافئ لـ shimmerPlaceholder
  Widget _buildImagePlaceholder() {
    //  نستخدم ShimmerEffect كما هو
    return ShimmerEffect(
      child: Container(
        height: 136,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final isDark = themeManager.isDarkMode;
    
    // Luxury Colors
    final textColor = isDark ? LuxuryTheme.kPlatinum : LuxuryTheme.kDeepNavy;
    final secondaryText = isDark ? LuxuryTheme.kPlatinum.withOpacity(0.7) : LuxuryTheme.kDeepNavy.withOpacity(0.7);
    final liquidBgColor = isDark 
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.05);
    final liquidBorderColor = isDark
        ? Colors.white.withOpacity(0.15)
        : Colors.black.withOpacity(0.1);

    // مكافئ لـ scaleEffect و .animation(.spring) في Swift
    final scale = _isHovering ? 0.97 : 1.0; 

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: liquidBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: liquidBorderColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: LuxuryTheme.kLightBlueAccent.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image with Circular Icon Overlay
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background Gradient - Neutral
                        Container(
                          width: double.infinity,
                          height: 136,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                textColor.withOpacity(0.08),
                                textColor.withOpacity(0.02),
                              ],
                            ),
                          ),
                        ),
                        
                        // Circular Icon Badge (Center)
                        Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: textColor.withOpacity(0.3),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: textColor.withOpacity(0.15),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: widget.store.storeIconUrl.isEmpty
                              ? Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: textColor.withOpacity(0.08),
                                  ),
                                  child: Icon(Icons.store, size: 40, color: textColor.withOpacity(0.6)),
                                )
                              : ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: widget.store.storeIconUrl,
                                    width: 82,
                                    height: 82,
                                    fit: BoxFit.cover,
                                    // Decoding at full original resolution
                                    // (some of these are multi-MB photos)
                                    // for an 82x82 circle was pushing a lot
                                    // of memory into Flutter's image cache,
                                    // which evicts older entries under
                                    // pressure — including this same icon
                                    // after browsing product-heavy screens,
                                    // which is what made it "disappear"
                                    // until a full refresh.
                                    memCacheWidth: 164,
                                    memCacheHeight: 164,
                                    placeholder: (context, url) => Container(
                                      color: textColor.withOpacity(0.08),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: textColor.withOpacity(0.08),
                                      child: Icon(Icons.store, size: 40, color: textColor.withOpacity(0.6)),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),

                          const SizedBox(height: 2),

                    // Store Info
                    Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.store.storeName,
                            style: TextStyle(
                              fontFamily: 'TenorSans',
                                    fontSize: 15, 
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          
                          // Address
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 14, color: secondaryText),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.store.address ?? "No address",
                                  style: TextStyle(
                                    fontFamily: 'TenorSans',
                                    fontSize: 12,
                                    color: secondaryText,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Rating
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: secondaryText.withOpacity(0.5),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}