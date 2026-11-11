package io.systemlens.supermarket.inventory.application.port.out;

import java.time.Instant;

public interface StockMovementPort {
    void save(String orderId, String productId, int quantity, String channel,
              Instant requestedAt, Instant createdAt);
}
