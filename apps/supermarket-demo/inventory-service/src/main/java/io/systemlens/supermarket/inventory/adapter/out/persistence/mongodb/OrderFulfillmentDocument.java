package io.systemlens.supermarket.inventory.adapter.out.persistence.mongodb;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.time.Instant;

@Document(collection = "order_fulfillments")
record OrderFulfillmentDocument(@Id String orderId, String productId, String productName, int quantity,
                                int remainingStock, String channel, Instant requestedAt, Instant createdAt) {}
