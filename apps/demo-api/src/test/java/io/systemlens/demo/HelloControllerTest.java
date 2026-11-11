package io.systemlens.demo;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HelloController.class)
class HelloControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void helloAnswers() throws Exception {
        mockMvc.perform(get("/api/hello").param("name", "lab"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.message").value("Hello lab"));
    }

    @Test
    void failPropagatesException() {
        // L'exception n'est pas traitée : elle atteint le conteneur de servlets.
        assertThatThrownBy(() -> mockMvc.perform(get("/api/fail").param("reason", "test")))
            .hasRootCauseInstanceOf(HelloController.DemoFailureException.class)
            .hasRootCauseMessage("Échec contrôlé : test");
    }
}
