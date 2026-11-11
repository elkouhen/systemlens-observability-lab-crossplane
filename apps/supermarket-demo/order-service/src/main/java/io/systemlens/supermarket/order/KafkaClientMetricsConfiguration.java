package io.systemlens.supermarket.order;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

/** Expose les paramètres Kafka du producer pour les corréler à ses métriques runtime. */
@Configuration
public class KafkaClientMetricsConfiguration implements MeterBinder {
    private final double lingerMs;
    private final double batchSizeBytes;

    public KafkaClientMetricsConfiguration(
            @Value("${spring.kafka.producer.properties.linger.ms:5}") double lingerMs,
            @Value("${spring.kafka.producer.properties.batch.size:16384}") double batchSizeBytes) {
        this.lingerMs = lingerMs;
        this.batchSizeBytes = batchSizeBytes;
    }

    @Override
    public void bindTo(MeterRegistry registry) {
        Gauge.builder("kafka.producer.linger", () -> lingerMs)
                .description("Configured Kafka producer linger time")
                .baseUnit("milliseconds")
                .register(registry);
        Gauge.builder("kafka.producer.batch.size.configured", () -> batchSizeBytes)
                .description("Configured Kafka producer batch size")
                .baseUnit("bytes")
                .register(registry);
    }
}
