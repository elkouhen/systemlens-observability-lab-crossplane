package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaStockRestockConsumer extends AbstractKafkaMessageProcessor<StockRestockRequested> {
    private final InventoryUseCase inventory;
    public KafkaStockRestockConsumer(InventoryUseCase inventory) { this(inventory, new io.micrometer.core.instrument.simple.SimpleMeterRegistry()); }
    @Autowired
    public KafkaStockRestockConsumer(InventoryUseCase inventory, MeterRegistry meterRegistry) { super(meterRegistry); this.inventory=inventory; }
    @KafkaListener(topics="supermarket.stock.restock-requested", groupId="inventory-restock-service")
    public void consume(StockRestockRequested request) {
        consumeMessage(request, "restock", "supermarket.stock.restock-requested");
    }

    @Override
    protected void processMessage(StockRestockRequested request) {
        inventory.restock(request.getProductId(), request.getQuantity());
    }
}
