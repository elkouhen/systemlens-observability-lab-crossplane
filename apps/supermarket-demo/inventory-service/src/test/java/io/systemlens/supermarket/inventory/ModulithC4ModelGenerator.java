package io.systemlens.supermarket.inventory;

import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

/** Generates the Spring Modulith C4 component model during the Maven build. */
public final class ModulithC4ModelGenerator {

    private ModulithC4ModelGenerator() {}

    public static void main(String[] arguments) {
        var outputDirectory = arguments.length == 0
                ? "target/spring-modulith-c4"
                : arguments[0];

        new Documenter(
                ApplicationModules.of(InventoryServiceApplication.class),
                outputDirectory
        ).writeDocumentation();
    }
}
