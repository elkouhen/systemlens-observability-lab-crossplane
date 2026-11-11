package io.systemlens.supermarket.inventory.application.port.out;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;

public interface StockDepletedPort {
    void publish(StockDepleted event);
}
