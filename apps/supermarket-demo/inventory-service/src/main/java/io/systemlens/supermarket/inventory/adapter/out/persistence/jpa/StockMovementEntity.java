package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity @Table(name = "stock_movements")
public class StockMovementEntity {
    @Id private String orderId; private String productId; private int quantity; private String channel; private Instant requestedAt; private Instant createdAt;
    protected StockMovementEntity() {}
    StockMovementEntity(String orderId, String productId, int quantity, String channel, Instant requestedAt, Instant createdAt) { this.orderId=orderId; this.productId=productId; this.quantity=quantity; this.channel=channel; this.requestedAt=requestedAt; this.createdAt=createdAt; }
}
