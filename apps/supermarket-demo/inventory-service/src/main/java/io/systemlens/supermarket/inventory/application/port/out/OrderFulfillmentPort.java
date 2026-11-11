package io.systemlens.supermarket.inventory.application.port.out;

import java.time.Instant;

public interface OrderFulfillmentPort {
    void save(String orderId, String productId, String productName, int quantity,
              int remainingStock, String channel, Instant requestedAt, Instant createdAt);
    void deleteById(String orderId);
}
