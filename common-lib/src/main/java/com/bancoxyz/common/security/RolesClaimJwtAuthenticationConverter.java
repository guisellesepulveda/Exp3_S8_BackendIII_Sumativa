package com.bancoxyz.common.security;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

/**
 * Convierte el access token OAuth2 emitido por auth-service en las autoridades de Spring Security:
 * <ul>
 *   <li>claim {@code scope} (ej. "read write") -> {@code SCOPE_read}, {@code SCOPE_write} (conversion estandar);</li>
 *   <li>claim {@code roles} (lista, ej. ["ADMIN"]) agregado por auth-service -> {@code ROLE_ADMIN}.</li>
 * </ul>
 */
public class RolesClaimJwtAuthenticationConverter implements Converter<Jwt, AbstractAuthenticationToken> {

    private final JwtGrantedAuthoritiesConverter scopeConverter = new JwtGrantedAuthoritiesConverter();

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        Collection<GrantedAuthority> authorities = new ArrayList<>(scopeConverter.convert(jwt));
        List<String> roles = jwt.getClaimAsStringList("roles");
        if (roles != null) {
            roles.forEach(rol -> authorities.add(new SimpleGrantedAuthority("ROLE_" + rol)));
        }
        return new JwtAuthenticationToken(jwt, authorities, jwt.getSubject());
    }
}
