package io.systemlens.supermarket.inventory;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.core.domain.JavaModifier;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

class ArchitectureTest {

    private static final String DOMAIN = "..domain..";
    private static final String APPLICATION = "..application..";
    private static final String ADAPTER = "..adapter..";

    static final ArchRule domain_is_independent_from_frameworks = noClasses()
            .that().resideInAPackage(DOMAIN)
            .should().dependOnClassesThat().resideInAnyPackage(
                    "org.springframework..",
                    "jakarta..",
                    "org.apache.kafka..",
                    "org.slf4j..",
                    "io.micrometer.."
            );

    static final ArchRule domain_does_not_depend_on_outer_layers = noClasses()
            .that().resideInAPackage(DOMAIN)
            .should().dependOnClassesThat().resideInAnyPackage(APPLICATION, ADAPTER);

    static final ArchRule application_does_not_depend_on_adapters = noClasses()
            .that().resideInAPackage(APPLICATION)
            .should().dependOnClassesThat().resideInAPackage(ADAPTER);

    static final ArchRule ports_are_interfaces = classes()
            .that().areTopLevelClasses()
            .and().resideInAnyPackage("..application.port.in", "..application.port.out")
            .should().beInterfaces();

    static final ArchRule domain_types_are_final = classes()
            .that().resideInAPackage(DOMAIN)
            .and().areNotAssignableTo(RuntimeException.class)
            .should().haveModifier(JavaModifier.FINAL);

    @Test
    void respectsHexagonalAndDddBoundaries() {
        JavaClasses inventoryClasses = new ClassFileImporter()
                .importPackages("io.systemlens.supermarket.inventory");

        domain_is_independent_from_frameworks.check(inventoryClasses);
        domain_does_not_depend_on_outer_layers.check(inventoryClasses);
        application_does_not_depend_on_adapters.check(inventoryClasses);
        ports_are_interfaces.check(inventoryClasses);
        domain_types_are_final.check(inventoryClasses);
    }

    @Test
    void respectsSpringModulithBoundaries() {
        ApplicationModules.of(InventoryServiceApplication.class).verify();
    }
}
