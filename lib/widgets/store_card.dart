// lib/widgets/store_card.dart

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
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
                                  // Plain Image.network, not
                                  // CachedNetworkImage — this icon kept
                                  // disappearing after navigating away and
                                  // back even after sizing/memory fixes,
                                  // while nothing else about this app (e.g.
                                  // the native iOS build, a different
                                  // image-loading stack entirely) has that
                                  // problem at all. cached_network_image
                                  // adds its own disk-cache/state layer on
                                  // top of Flutter's normal image loading;
                                  // dropping that extra layer for this
                                  // specific icon is worth testing as a
                                  // more primitive, more reliable path —
                                  // relies on the browser's own HTTP cache
                                  // plus Flutter's built-in image cache
                                  // instead.
                                  child: Image.network(
                                    widget.store.storeIconUrl,
                                    width: 82,
                                    height: 82,
                                    fit: BoxFit.cover,
                                    cacheWidth: 164,
                                    cacheHeight: 164,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(color: textColor.withOpacity(0.08));
                                    },
                                    errorBuilder: (context, error, stack) => Container(
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