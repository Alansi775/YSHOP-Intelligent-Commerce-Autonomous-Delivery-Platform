// Shared Live Activity content-state builder.
// Used by OrderController (status changes) and DeliveryController (location updates).

// Haversine formula — returns straight-line distance in metres between two GPS points
function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6_371_000;
  const toRad = d => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

const STATUS_MAP = {
  pending:        { title: 'Order Placed',       step: 1 },
  confirmed:      { title: 'Confirmed by Store', step: 2 },
  processing:     { title: 'Being Prepared',     step: 2 },
  shipped:        { title: 'Out for Delivery',   step: 3 },
  outForDelivery: { title: 'Out for Delivery',   step: 3 },
  delivered:      { title: 'Delivered!',         step: 4 },
  cancelled:      { title: 'Order Cancelled',    step: 0 },
  failed:         { title: 'Order Failed',       step: 0 },
  return:         { title: 'Return Requested',   step: 0 },
};

const TERMINAL_STATUSES = new Set(['delivered', 'cancelled', 'failed']);

/**
 * Build the ContentState payload that matches OrderLiveActivityAttributes.ContentState in Swift.
 *
 * @param {object} order      - Raw DB row (snake_case fields)
 * @param {number} [driverLat] - Override driver latitude  (use when you already have fresh coords)
 * @param {number} [driverLon] - Override driver longitude
 */
export function buildLiveActivityState(order, driverLat, driverLon) {
  const mapped = STATUS_MAP[order.status] ?? { title: order.status, step: 0 };

  let proximityFraction = 0.0;
  let distanceText = null;

  if (order.status === 'delivered') {
    proximityFraction = 1.0;
  } else if (order.status === 'shipped' || order.status === 'outForDelivery') {
    const cLat = parseFloat(order.customer_latitude ?? order.location_Latitude);
    const cLon = parseFloat(order.customer_longitude ?? order.location_Longitude);

    // Prefer caller-supplied coordinates; fall back to what's stored in the DB row
    let dLat = driverLat != null ? parseFloat(driverLat) : NaN;
    let dLon = driverLon != null ? parseFloat(driverLon) : NaN;

    if ((isNaN(dLat) || isNaN(dLon)) && order.driver_location) {
      try {
        const loc =
          typeof order.driver_location === 'string'
            ? JSON.parse(order.driver_location)
            : order.driver_location;
        dLat = parseFloat(loc.latitude ?? loc.lat);
        dLon = parseFloat(loc.longitude ?? loc.lon ?? loc.lng);
      } catch {}
    }

    if (!isNaN(dLat) && !isNaN(dLon) && !isNaN(cLat) && !isNaN(cLon)) {
      const meters = haversineMeters(dLat, dLon, cLat, cLon);
      distanceText = meters < 1000
        ? `${Math.round(meters)} m away`
        : `${(meters / 1000).toFixed(1)} km away`;
      // 3 km → 0 %, 0 m → 95 % (100 % reserved for delivered)
      proximityFraction = Math.max(0, Math.min(0.95, 1.0 - meters / 3_000.0));
    }
  }

  return {
    statusTitle:       mapped.title,
    statusStep:        mapped.step,
    driverName:        order.driver_name ?? null,
    storeName:         order.store_name  ?? 'Store',
    storeType:         order.store_type  ?? 'Food',
    isDelivered:       order.status === 'delivered',
    isCancelled:       ['cancelled', 'failed'].includes(order.status),
    proximityFraction,
    distanceText,
  };
}

export { TERMINAL_STATUSES };
