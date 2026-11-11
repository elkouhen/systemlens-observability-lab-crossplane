package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.core.KafkaTemplate;

import java.time.OffsetDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class StockDepletedConsumerTest {

    @SuppressWarnings("unchecked")
    private final KafkaTemplate<String, StockRestockRequested> kafkaTemplate = mock(KafkaTemplate.class);
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
    private final StockDepletedConsumer consumer = new StockDepletedConsumer(kafkaTemplate, meterRegistry);

    @Test
    void requestsRestockForDepletedProduct() {
        consumer.requestRestock(new StockDepleted("PASTA-500G", OffsetDateTime.parse("2026-08-26T10:00:00Z")));

        ArgumentCaptor<StockRestockRequested> request = ArgumentCaptor.forClass(StockRestockRequested.class);
        verify(kafkaTemplate).send(eq("supermarket.stock.restock-requested"), eq("PASTA-500G"), request.capture());
        assertEquals(500, request.getValue().getQuantity());
        assertEquals(1.0, meterRegistry.get("business.stock.restock.requested").counter().count());
    }
}
