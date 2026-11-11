package io.systemlens.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * API de démonstration minimale : une seule route, instrumentée sans code par
 * l'agent Java OpenTelemetry (traces, logs et métriques JVM).
 */
@SpringBootApplication
public class DemoApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(DemoApiApplication.class, args);
    }
}
