// Canonical catalog of in-app products sold through the Shop.
//
// The product IDs in [ProductCatalog.allIds] must match exactly the
// product IDs configured in App Store Connect (iOS) and Google Play
// Console (Android).  Both stores use the same string IDs so the client
// can pass a single ID through the in_app_purchase plugin and the
// server-side `redeemPurchase` Cloud Function can route on the same key.
//
// Each [ProductDefinition] also encodes the credit grant the SKU is
// worth, so the Cloud Function can look the SKU up in the catalog and
// increment `users/{uid}.icebreakerCredits` / `liveSessionCredits`
// without trusting any client-supplied amounts.

class ProductDefinition {
  const ProductDefinition({
    required this.productId,
    required this.icebreakers,
    required this.liveSessions,
    required this.displayPrice,
    required this.title,
  });

  /// Store SKU — must match App Store Connect + Google Play Console exactly.
  final String productId;

  /// Icebreaker credits granted on successful purchase.
  final int icebreakers;

  /// Live session credits granted on successful purchase.
  final int liveSessions;

  /// Fallback price string used when the store hasn't returned localised
  /// pricing yet (cold app start, no network).  Real pricing comes from
  /// `ProductDetails.price` once the store query completes.
  final String displayPrice;

  /// Short title rendered in the Shop and in receipts.
  final String title;
}

class ProductCatalog {
  ProductCatalog._();

  // Icebreaker packs (consumable).
  static const icebreakers1 = ProductDefinition(
    productId: 'icebreakers_1',
    icebreakers: 1,
    liveSessions: 0,
    displayPrice: r'$0.99',
    title: '1 Icebreaker',
  );
  static const icebreakers5 = ProductDefinition(
    productId: 'icebreakers_5',
    icebreakers: 5,
    liveSessions: 0,
    displayPrice: r'$2.99',
    title: '5 Icebreakers',
  );
  static const icebreakers10 = ProductDefinition(
    productId: 'icebreakers_10',
    icebreakers: 10,
    liveSessions: 0,
    displayPrice: r'$4.99',
    title: '10 Icebreakers',
  );

  // Live session packs (consumable).
  static const live1 = ProductDefinition(
    productId: 'live_1',
    icebreakers: 0,
    liveSessions: 1,
    displayPrice: r'$0.99',
    title: '1 Live Session',
  );
  static const live5 = ProductDefinition(
    productId: 'live_5',
    icebreakers: 0,
    liveSessions: 5,
    displayPrice: r'$4.99',
    title: '5 Live Sessions',
  );
  static const live10 = ProductDefinition(
    productId: 'live_10',
    icebreakers: 0,
    liveSessions: 10,
    displayPrice: r'$8.99',
    title: '10 Live Sessions',
  );

  // Best-value bundle (consumable).
  static const bundle55 = ProductDefinition(
    productId: 'bundle_5_5',
    icebreakers: 5,
    liveSessions: 5,
    displayPrice: r'$6.99',
    title: '5 Icebreakers + 5 Live Sessions',
  );

  static const List<ProductDefinition> all = [
    icebreakers1,
    icebreakers5,
    icebreakers10,
    live1,
    live5,
    live10,
    bundle55,
  ];

  static Set<String> get allIds => {for (final p in all) p.productId};

  static ProductDefinition? byId(String productId) {
    for (final p in all) {
      if (p.productId == productId) return p;
    }
    return null;
  }
}
