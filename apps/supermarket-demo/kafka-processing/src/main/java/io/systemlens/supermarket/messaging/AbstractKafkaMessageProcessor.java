package io.systemlens.supermarket.messaging;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

/** Shared timing/delegation boundary for application Kafka consumers. */
public abstract class AbstractKafkaMessageProcessor<T> {

    private final MeterRegistry meterRegistry;

    protected AbstractKafkaMessageProcessor(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    protected AbstractKafkaMessageProcessor() {
        this(new SimpleMeterRegistry());
    }

    protected final MeterRegistry meterRegistry() {
        return meterRegistry;
    }

    protected final void consumeMessage(T message, String consumer, String topic) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            processMessage(message);
        } finally {
            sample.stop(meterRegistry.timer(
                    "business.kafka.message.processing",
                    "consumer", consumer,
                    "topic", topic));
        }
    }

    protected abstract void processMessage(T message);
}
