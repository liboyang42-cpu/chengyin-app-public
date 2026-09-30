/// 锁屏/控制中心封面(`MediaItem.artUri`)取值口径:
/// 只有能解析为 http(s) 的真实图片地址才给,其余一律 null(不造假封面)。
Uri? mediaArtUri(String? url) {
  if (url == null || url.isEmpty) return null;
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return null;
  return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
}
