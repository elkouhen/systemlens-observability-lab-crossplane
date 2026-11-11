package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;


@Component
public class StockDepletedConsumer extends AbstractKafkaMessageProcessor<StockDepleted> {

    private static final Logger LOGGER = LoggerFactory.getLogger(StockDepletedConsumer.class);

    private final RestockRequestWorkflow requestWorkflow;
    private final Counter restocksRequested;
    @Autowired
    public StockDepletedConsumer(RestockRequestWorkflow requestWorkflow,
                                MeterRegistry meterRegistry) {
        super(meterRegistry);
        this.requestWorkflow = requestWorkflow;
        this.restocksRequested = Counter.builder("business.stock.restock.requested").description("Réassorts demandés").register(meterRegistry);
    }

    public StockDepletedConsumer(
            org.springframework.kafka.core.KafkaTemplate<String, StockRestockRequested> kafkaTemplate,
            MeterRegistry meterRegistry) {
        this(new RestockRequestWorkflow(new RestockRequestPublisher(kafkaTemplate)), meterRegistry);
    }

    @KafkaListener(topics = "supermarket.stock.depleted", groupId = "restock-service")
    public void requestRestock(StockDepleted event) {
        consumeMessage(event, "stock-depleted", "supermarket.stock.depleted");
    }

    @Override
    protected void processMessage(StockDepleted event) {
        StockRestockRequested request = requestWorkflow.publishRequest(event);
        restocksRequested.increment();
        LOGGER.info("Reassort demande: productId={}, quantity={}", request.getProductId(), request.getQuantity());
    }
}
