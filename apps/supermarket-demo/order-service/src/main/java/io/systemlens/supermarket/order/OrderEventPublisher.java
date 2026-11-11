package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/** Kafka output method for the scheduled order flow. */
@Component
public class OrderEventPublisher {
    private final KafkaTemplate<String, OrderPlaced> kafkaTemplate;

    public OrderEventPublisher(KafkaTemplate<String, OrderPlaced> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publish(OrderPlaced order) {
        kafkaTemplate.send("supermarket.order.placed", order.getOrderId(), order);
    }
}
