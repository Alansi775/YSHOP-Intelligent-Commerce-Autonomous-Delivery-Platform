// pricing.js — single source of truth for how a store owner's entered
// product price becomes what the customer actually pays.
//
// The price a store owner enters (products.price) is their guaranteed
// take-home per unit. Fees are added ON TOP of that, not deducted from it:
//   in-store / dine-in (no driver):  charged = base * (1 + PLATFORM_FEE_RATE)
//   online / delivered:              charged = base * (1 + PLATFORM_FEE_RATE + DELIVERY_FEE_RATE)
//
// This must be the ONLY place that computes a charged price from a base
// price, and the ONLY place that reverses a charged total back into its
// base/platform/driver components for reporting — every call site (order
// creation, analytics, receipts) should go through here so the numbers can
// never drift apart from each other.

export const PLATFORM_FEE_RATE = 0.25;
export const DELIVERY_FEE_RATE = 0.10;

/**
 * What the customer pays for one unit, given the store owner's base price.
 */
export function chargedPrice(basePrice, { isLocal }) {
  const base = Number(basePrice) || 0;
  const multiplier = 1 + PLATFORM_FEE_RATE + (isLocal ? 0 : DELIVERY_FEE_RATE);
  return Math.round(base * multiplier * 100) / 100;
}

/**
 * Reverses an already-charged total back into what the store owner's base
 * price would have been, plus the platform/driver amounts implied by it.
 * Used for analytics/reporting, where all we have is the historical
 * charged total stored on the order.
 */
export function splitFromCharged(chargedTotal, { isLocal }) {
  const charged = Number(chargedTotal) || 0;
  const multiplier = 1 + PLATFORM_FEE_RATE + (isLocal ? 0 : DELIVERY_FEE_RATE);
  const base = multiplier > 0 ? charged / multiplier : 0;
  const platform = base * PLATFORM_FEE_RATE;
  const driver = isLocal ? 0 : base * DELIVERY_FEE_RATE;
  return {
    base: Math.round(base * 100) / 100,
    platform: Math.round(platform * 100) / 100,
    driver: Math.round(driver * 100) / 100,
  };
}
