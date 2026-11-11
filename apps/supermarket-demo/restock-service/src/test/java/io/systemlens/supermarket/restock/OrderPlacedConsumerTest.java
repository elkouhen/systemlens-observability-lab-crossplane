package io.systemlens.supermarket.restock;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OrderPlacedConsumerTest {

    @Test
    void observesOnlineOrder() {
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        OrderPlacedConsumer consumer = new OrderPlacedConsumer(meterRegistry);

        consumer.observeOrder(new OrderPlaced(
                "order-1", "PASTA-500G", 2, OffsetDateTime.parse("2026-08-26T10:00:00Z")));

        assertEquals(1.0, meterRegistry.get("business.orders.observed")
                .tag("consumer", "restock-service").counter().count());
    }
}
