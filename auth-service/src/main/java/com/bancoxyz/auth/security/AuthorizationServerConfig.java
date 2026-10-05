package com.bancoxyz.auth.security;

import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.SecurityContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.core.oidc.OidcScopes;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.config.annotation.web.configuration.OAuth2AuthorizationServerConfiguration;
import org.springframework.security.oauth2.server.authorization.config.annotation.web.configurers.OAuth2AuthorizationServerConfigurer;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Duration;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Servidor de autorizacion OAuth2 / OpenID Connect (Spring Authorization Server).
 *
 * <ul>
 *   <li>{@code client_credentials}: comunicacion maquina a maquina (clientes {@code banco-admin} y
 *       {@code banco-reader}).</li>
 *   <li>{@code authorization_code} + {@code refresh_token}: usuarios finales (cliente {@code banco-web}),
 *       con pantalla de login y de consentimiento.</li>
 * </ul>
 *
 * Los access token son JWT firmados con RS256; los resource servers validan la firma con la clave publica
 * publicada en {@code /oauth2/jwks}, sin compartir ningun secreto con este servicio.
 */
@Configuration
@EnableWebSecurity
public class AuthorizationServerConfig {

    static final String ROLES_CLAIM = "roles";
    private static final String CLIENT_ROLES_SETTING = "banco.roles";

    /** Cadena 1: endpoints del protocolo (/oauth2/**, /.well-known/**, /userinfo, /connect/**). */
    @Bean
    @Order(1)
    public SecurityFilterChain authorizationServerFilterChain(HttpSecurity http) throws Exception {
        OAuth2AuthorizationServerConfiguration.applyDefaultSecurity(http);
        http.getConfigurer(OAuth2AuthorizationServerConfigurer.class)
                .oidc(Customizer.withDefaults());
        http
                // Peticiones del navegador sin sesion -> pantalla de login
                .exceptionHandling(ex -> ex.defaultAuthenticationEntryPointFor(
                        new LoginUrlAuthenticationEntryPoint("/login"),
                        new MediaTypeRequestMatcher(MediaType.TEXT_HTML)))
                // /userinfo exige un access token valido
                .oauth2ResourceServer(rs -> rs.jwt(Customizer.withDefaults()));
        return http.build();
    }

    /** Cadena 2: login de usuarios (formulario) y resto de endpoints propios. */
    @Bean
    @Order(2)
    public SecurityFilterChain defaultFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health", "/actuator/health/**", "/authorized", "/error").permitAll()
                        .anyRequest().authenticated())
                .formLogin(Customizer.withDefaults());
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return PasswordEncoderFactories.createDelegatingPasswordEncoder();
    }

    @Bean
    public RegisteredClientRepository registeredClientRepository(
            PasswordEncoder encoder,
            @Value("${app.oauth.clients.admin.secret}") String adminSecret,
            @Value("${app.oauth.clients.reader.secret}") String readerSecret,
            @Value("${app.oauth.clients.web.secret}") String webSecret,
            @Value("${app.oauth.access-token-ttl-minutes}") long ttlMinutes) {

        TokenSettings tokens = TokenSettings.builder()
                .accessTokenTimeToLive(Duration.ofMinutes(ttlMinutes))
                .refreshTokenTimeToLive(Duration.ofHours(8))
                .build();

        // Cliente de servicio con privilegios de administracion (scopes read+write, rol ADMIN)
        RegisteredClient admin = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId("banco-admin")
                .clientSecret(encoder.encode(adminSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .scope("read").scope("write")
                .clientSettings(ClientSettings.builder().setting(CLIENT_ROLES_SETTING, List.of("ADMIN", "USER")).build())
                .tokenSettings(tokens)
                .build();

        // Cliente de servicio de solo lectura (scope read, rol USER)
        RegisteredClient reader = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId("banco-reader")
                .clientSecret(encoder.encode(readerSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .scope("read")
                .clientSettings(ClientSettings.builder().setting(CLIENT_ROLES_SETTING, List.of("USER")).build())
                .tokenSettings(tokens)
                .build();

        // Aplicacion web: usuarios finales via Authorization Code (+ PKCE opcional) y refresh token
        RegisteredClient web = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId("banco-web")
                .clientSecret(encoder.encode(webSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
                .redirectUri("http://127.0.0.1:8081/authorized")
                .redirectUri("https://oauth.pstmn.io/v1/callback")
                .scope(OidcScopes.OPENID).scope("read").scope("write")
                .clientSettings(ClientSettings.builder().requireAuthorizationConsent(true).build())
                .tokenSettings(tokens)
                .build();

        return new InMemoryRegisteredClientRepository(admin, reader, web);
    }

    /** Agrega el claim {@code roles} (consumido por los resource servers) a cada access token. */
    @Bean
    public OAuth2TokenCustomizer<JwtEncodingContext> rolesTokenCustomizer() {
        return context -> {
            if (!OAuth2TokenType.ACCESS_TOKEN.equals(context.getTokenType())) {
                return;
            }
            Set<String> roles;
            if (AuthorizationGrantType.CLIENT_CREDENTIALS.equals(context.getAuthorizationGrantType())) {
                List<String> clientRoles = context.getRegisteredClient().getClientSettings().getSetting(CLIENT_ROLES_SETTING);
                roles = clientRoles == null ? Set.of() : Set.copyOf(clientRoles);
            } else {
                Authentication user = context.getPrincipal();
                roles = user.getAuthorities().stream()
                        .map(GrantedAuthority::getAuthority)
                        .filter(a -> a.startsWith("ROLE_"))
                        .map(a -> a.substring(5))
                        .collect(Collectors.toSet());
            }
            context.getClaims().claim(ROLES_CLAIM, roles);
        };
    }

    @Bean
    public AuthorizationServerSettings authorizationServerSettings(@Value("${app.oauth.issuer}") String issuer) {
        return AuthorizationServerSettings.builder().issuer(issuer).build();
    }

    /** Par de claves RSA generado al arrancar (demo). En produccion se carga desde un keystore/secret. */
    @Bean
    public JWKSource<SecurityContext> jwkSource() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair keyPair = generator.generateKeyPair();
        RSAKey rsaKey = new RSAKey.Builder((RSAPublicKey) keyPair.getPublic())
                .privateKey((RSAPrivateKey) keyPair.getPrivate())
                .keyID(UUID.randomUUID().toString())
                .build();
        return new ImmutableJWKSet<>(new JWKSet(rsaKey));
    }

    @Bean
    public JwtDecoder jwtDecoder(JWKSource<SecurityContext> jwkSource) {
        return OAuth2AuthorizationServerConfiguration.jwtDecoder(jwkSource);
    }
}
