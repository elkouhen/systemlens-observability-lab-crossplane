package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.inventory.adapter.in.messaging.KafkaStockRestockConsumer;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class KafkaStockRestockConsumerTest {

    private final InventoryUseCase reservationService = mock(InventoryUseCase.class);
    private final KafkaStockRestockConsumer consumer = new KafkaStockRestockConsumer(reservationService);

    @Test
    void appliesRestockRequestToInventory() {
        consumer.consume(new StockRestockRequested("PASTA-500G", 500, OffsetDateTime.now()));

        verify(reservationService).restock("PASTA-500G", 500);
    }
}
