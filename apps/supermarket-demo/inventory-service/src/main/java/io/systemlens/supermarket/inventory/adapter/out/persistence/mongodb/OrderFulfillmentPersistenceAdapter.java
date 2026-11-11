package io.systemlens.supermarket.inventory.adapter.out.persistence.mongodb;

import io.systemlens.supermarket.inventory.application.port.out.OrderFulfillmentPort;
import org.springframework.stereotype.Component;
import java.time.Instant;

@Component
class OrderFulfillmentPersistenceAdapter implements OrderFulfillmentPort {
    private final SpringDataOrderFulfillmentRepository repository;
    OrderFulfillmentPersistenceAdapter(SpringDataOrderFulfillmentRepository repository) { this.repository=repository; }
    public void save(String orderId, String productId, String productName, int quantity, int remainingStock, String channel, Instant requestedAt, Instant createdAt) {
        repository.save(new OrderFulfillmentDocument(orderId, productId, productName, quantity, remainingStock, channel, requestedAt, createdAt));
    }
    public void deleteById(String orderId) { repository.deleteById(orderId); }
}
