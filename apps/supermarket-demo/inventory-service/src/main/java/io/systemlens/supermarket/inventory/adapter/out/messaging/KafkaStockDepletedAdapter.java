package io.systemlens.supermarket.inventory.adapter.out.messaging;

import io.systemlens.supermarket.inventory.application.port.out.StockDepletedPort;
import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@Component
class KafkaStockDepletedAdapter implements StockDepletedPort {
    private final KafkaTemplate<String, StockDepleted> kafkaTemplate;
    KafkaStockDepletedAdapter(KafkaTemplate<String, StockDepleted> kafkaTemplate) { this.kafkaTemplate=kafkaTemplate; }
    public void publish(StockDepleted event) {
        kafkaTemplate.send("supermarket.stock.depleted", event.getProductId(), event);
    }
}
