package com.bancoxyz.auth.web;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * redirect_uri de demostracion para el flujo Authorization Code: muestra el {@code code} recibido para
 * poder canjearlo por un token con curl (no hay una SPA real que lo haga).
 */
@RestController
public class AuthorizedController {

    @GetMapping("/authorized")
    public Map<String, String> authorized(@RequestParam(required = false) String code,
                                          @RequestParam(required = false) String state,
                                          @RequestParam(required = false) String error) {
        Map<String, String> body = new LinkedHashMap<>();
        if (error != null) {
            body.put("error", error);
            return body;
        }
        body.put("code", code);
        body.put("state", state);
        body.put("siguiente_paso", "Canjear el code en POST /oauth2/token (grant_type=authorization_code) antes de 5 minutos");
        return body;
    }
}
