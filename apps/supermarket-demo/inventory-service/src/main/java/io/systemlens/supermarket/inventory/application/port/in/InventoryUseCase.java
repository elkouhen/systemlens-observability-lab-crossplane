package io.systemlens.supermarket.inventory.application.port.in;

import java.time.Instant;
import io.systemlens.supermarket.inventory.domain.Product;

public interface InventoryUseCase {
    Product findProduct(String productId);
    ReservationResult reserve(String orderId, String productId, int quantity, String channel, Instant requestedAt);
    void restock(String productId, int quantity);

    record ReservationResult(String orderId, String productId, String productName, int quantity,
                             int remainingStock, String channel, long durationMs) {}
}
