package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import io.systemlens.supermarket.inventory.application.port.out.StockMovementPort;
import org.springframework.stereotype.Component;
import java.time.Instant;

@Component
class StockMovementPersistenceAdapter implements StockMovementPort {
    private final SpringDataStockMovementRepository repository;
    StockMovementPersistenceAdapter(SpringDataStockMovementRepository repository) { this.repository=repository; }
    public void save(String orderId, String productId, int quantity, String channel, Instant requestedAt, Instant createdAt) { repository.saveAndFlush(new StockMovementEntity(orderId, productId, quantity, channel, requestedAt, createdAt)); }
}
