package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import io.systemlens.supermarket.order.generated.model.ReservationResult;
import org.springframework.stereotype.Service;

/** Internal workflow step between the order controller and the REST client. */
@Service
public class OrderPlacementWorkflow {
    private final OrderReservationClient reservationClient;

    public OrderPlacementWorkflow(OrderReservationClient reservationClient) {
        this.reservationClient = reservationClient;
    }

    public ReservationResult reserve(OrderPlaced order) {
        return reservationClient.reserve(order);
    }
}
