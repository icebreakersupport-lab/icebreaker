/// The kind of image rendered for a user in the Nearby feed.  Nearby cards
/// use this to decorate the image differently — live selfies get a brand-pink
/// ring + "LIVE" pill, profile photos render as plain framed images.
enum NearbyImageKind {
  /// The recipient's currently-active live verification selfie.  Always
  /// listed first in the image rail so the first thing the viewer sees is
  /// the fresh proof-of-life capture.
  liveSelfie,

  /// One of the recipient's curated gallery photos (or their primary photo
  /// fallback).  Order matches the canonical `photoUrls` list.
  profilePhoto,
}

/// One entry in a recipient's Nearby image rail.  Carries just the URL +
/// kind — Flutter's `Image` handles fit/decoding, no precomputed dimensions
/// are needed.
class NearbyImage {
  const NearbyImage({required this.url, required this.kind});

  final String url;
  final NearbyImageKind kind;

  @override
  bool operator ==(Object other) =>
      other is NearbyImage && other.url == url && other.kind == kind;

  @override
  int get hashCode => Object.hash(url, kind);
}
