import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for AI/product images with aggressive caching settings
class ImageCacheManager {
  static final CacheManager instance = CacheManager(
    Config(
      'aiImageCache',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 500,
      repo: JsonCacheInfoRepository(databaseName: 'aiImageCache'),
      fileService: HttpFileService(),
    ),
  );
}
