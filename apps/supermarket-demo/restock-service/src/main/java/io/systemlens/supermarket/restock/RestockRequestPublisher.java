package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/** Kafka output method for the restock flow. */
@Component
public class RestockRequestPublisher {
    private final KafkaTemplate<String, StockRestockRequested> kafkaTemplate;

    public RestockRequestPublisher(KafkaTemplate<String, StockRestockRequested> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publish(StockRestockRequested request) {
        kafkaTemplate.send("supermarket.stock.restock-requested", request.getProductId(), request);
    }
}
