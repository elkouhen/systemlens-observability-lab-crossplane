package io.systemlens.supermarket.inventory.application;

import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import org.springframework.stereotype.Service;

import java.time.Instant;

/** Internal workflow step between an adapter entry point and the reservation effect. */
@Service
public class InventoryReservationWorkflow {
    private final InventoryUseCase inventory;

    public InventoryReservationWorkflow(InventoryUseCase inventory) {
        this.inventory = inventory;
    }

    public InventoryUseCase.ReservationResult reserve(
            String orderId, String productId, int quantity, String channel, Instant requestedAt) {
        return inventory.reserve(orderId, productId, quantity, channel, requestedAt);
    }
}
