package io.systemlens.supermarket.restock;

import io.micrometer.core.instrument.MeterRegistry;
import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/** Observe les commandes en ligne pour rendre visible le fan-out du flux métier. */
@Component
public class OrderPlacedConsumer extends AbstractKafkaMessageProcessor<OrderPlaced> {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderPlacedConsumer.class);

    @Autowired
    public OrderPlacedConsumer(MeterRegistry meterRegistry) {
        super(meterRegistry);
    }

    public OrderPlacedConsumer() {
        super();
    }

    @KafkaListener(topics = "supermarket.order.placed", groupId = "restock-order-observer")
    public void observeOrder(OrderPlaced event) {
        consumeMessage(event, "order-observer", "supermarket.order.placed");
    }

    @Override
    protected void processMessage(OrderPlaced event) {
        meterRegistry().counter("business.orders.observed", "consumer", "restock-service").increment();
        LOGGER.info("Commande observee pour le graphe d'appel: orderId={}, productId={}, quantity={}",
                event.getOrderId(), event.getProductId(), event.getQuantity());
    }
}
