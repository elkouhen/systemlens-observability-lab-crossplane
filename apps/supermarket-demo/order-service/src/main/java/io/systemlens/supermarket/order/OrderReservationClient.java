package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import io.systemlens.supermarket.order.generated.model.ReservationResult;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

/** External inventory call kept separate from the order workflow method. */
@Component
public class OrderReservationClient {
    private final RestTemplate restTemplate;

    @Value("${order-service.inventory-service-url}")
    private String inventoryServiceUrl;

    public OrderReservationClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public ReservationResult reserve(OrderPlaced order) {
        return restTemplate.postForObject(
                inventoryServiceUrl + "/api/reservations", order, ReservationResult.class);
    }
}
