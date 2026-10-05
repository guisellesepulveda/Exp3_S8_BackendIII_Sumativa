package com.bancoxyz.intereses.security;

import com.bancoxyz.common.security.RolesClaimJwtAuthenticationConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Resource Server OAuth2: valida el access token (JWT RS256) contra el JWKS de auth-service
 * ({@code spring.security.oauth2.resourceserver.jwt.jwk-set-uri}, servido por el Config Server) y
 * autoriza por scope (read/write) y por rol (ADMIN).
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        .requestMatchers("/api/migracion/rerun").hasRole("ADMIN")
                        .requestMatchers(HttpMethod.GET, "/api/**").hasAuthority("SCOPE_read")
                        .requestMatchers("/api/**").hasAuthority("SCOPE_write")
                        .anyRequest().authenticated()
                )
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt
                        .jwtAuthenticationConverter(new RolesClaimJwtAuthenticationConverter())
                ));
        return http.build();
    }
}
