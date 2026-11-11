package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;

/** Internal workflow step between the Kafka consumer and the output publisher. */
@Service
public class RestockRequestWorkflow {
    private static final int RESTOCK_QUANTITY = 500;
    private final RestockRequestPublisher requestPublisher;

    public RestockRequestWorkflow(RestockRequestPublisher requestPublisher) {
        this.requestPublisher = requestPublisher;
    }

    public StockRestockRequested publishRequest(StockDepleted event) {
        StockRestockRequested request = new StockRestockRequested(
                event.getProductId(), RESTOCK_QUANTITY, OffsetDateTime.now());
        requestPublisher.publish(request);
        return request;
    }
}
