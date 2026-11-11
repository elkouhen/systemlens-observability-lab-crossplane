package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.inventory.application.InventoryReservationWorkflow;
import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaOrderConsumer extends AbstractKafkaMessageProcessor<OrderPlaced> {
    private final InventoryReservationWorkflow reservationWorkflow;
    public KafkaOrderConsumer(InventoryReservationWorkflow reservationWorkflow) {
        this(reservationWorkflow, new io.micrometer.core.instrument.simple.SimpleMeterRegistry());
    }
    @Autowired
    public KafkaOrderConsumer(InventoryReservationWorkflow reservationWorkflow, MeterRegistry meterRegistry) {
        super(meterRegistry);
        this.reservationWorkflow = reservationWorkflow;
    }
    @KafkaListener(topics="supermarket.order.placed", groupId="inventory-service")
    public void consume(OrderPlaced order) {
        consumeMessage(order, "orders", "supermarket.order.placed");
    }

    @Override
    protected void processMessage(OrderPlaced order) {
        reservationWorkflow.reserve(order.getOrderId(), order.getProductId(), order.getQuantity(), "kafka", order.getRequestedAt().toInstant());
    }
}
