package io.systemlens.demo;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Points d'entrée de démonstration, instrumentés par l'agent Java OTel seul. */
@RestController
public class HelloController {

    private static final Logger LOGGER = LoggerFactory.getLogger(HelloController.class);

    /** Une transaction APM et un log INFO corrélé à la trace. */
    @GetMapping("/api/hello")
    public Map<String, String> hello(@RequestParam(defaultValue = "world") String name) {
        LOGGER.info("Hello demandé pour {}", name);
        return Map.of("message", "Hello " + name);
    }

    /**
     * Un log ERROR, puis une exception volontairement non traitée : elle
     * remonte jusqu'à l'instrumentation servlet de l'agent, qui l'enregistre
     * comme erreur APM et marque la transaction en échec (HTTP 500).
     */
    @GetMapping("/api/fail")
    public Map<String, String> fail(@RequestParam(defaultValue = "demo") String reason) {
        LOGGER.error("Échec contrôlé demandé : {}", reason);
        throw new DemoFailureException("Échec contrôlé : " + reason);
    }

    static class DemoFailureException extends RuntimeException {
        DemoFailureException(String message) {
            super(message);
        }
    }
}
