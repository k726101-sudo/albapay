import 'package:flutter/material.dart';
import '../services/r2_storage_service.dart';

class R2Image extends StatelessWidget {
  final String storeId;
  final String imagePathOrId;
  final BoxFit? fit;
  final double? width;
  final double? height;

  const R2Image({
    super.key,
    required this.storeId,
    required this.imagePathOrId,
    this.fit,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePathOrId.isEmpty) {
      return _errorWidget();
    }

    if (imagePathOrId.startsWith('http://') || imagePathOrId.startsWith('https://')) {
      return Image.network(
        imagePathOrId,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }

    return FutureBuilder<String>(
      future: R2StorageService.instance.getSecureDownloadUrl(storeId: storeId, docId: imagePathOrId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: width ?? 48,
            height: height ?? 48,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _errorWidget();
        }
        return Image.network(
          snapshot.data!,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, __, ___) => _errorWidget(),
        );
      },
    );
  }

  Widget _errorWidget() {
    return Container(
      width: width ?? 48,
      height: height ?? 48,
      color: Colors.grey.shade100,
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
}
