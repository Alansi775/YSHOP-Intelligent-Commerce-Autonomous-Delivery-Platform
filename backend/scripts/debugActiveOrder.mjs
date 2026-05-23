import dotenv from 'dotenv';
import Order from '../src/models/Order.js';

dotenv.config();

const UID = 'driver_1779038181514_m9s66uu8t';

(async () => {
  try {
    console.log('Running debugActiveOrder for uid=', UID);
    const order = await Order.findActiveByDriverId(UID);
    console.log('Result:');
    console.log(JSON.stringify(order, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('Error running debugActiveOrder:', err);
    process.exit(1);
  }
})();
