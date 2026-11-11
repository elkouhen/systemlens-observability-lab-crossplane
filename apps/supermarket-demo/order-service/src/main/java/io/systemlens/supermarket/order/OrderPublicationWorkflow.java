package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import org.springframework.stereotype.Service;

/** Internal workflow step before publishing a scheduled order. */
@Service
public class OrderPublicationWorkflow {
    private final OrderEventPublisher eventPublisher;

    public OrderPublicationWorkflow(OrderEventPublisher eventPublisher) {
        this.eventPublisher = eventPublisher;
    }

    public void publish(OrderPlaced order) {
        eventPublisher.publish(order);
    }
}
