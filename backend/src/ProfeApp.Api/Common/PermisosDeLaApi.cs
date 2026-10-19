namespace ProfeApp.Api.Common;

/// <summary>
/// Lo mínimo que necesita el usuario de la API (profeapp_app) en la base: leer y escribir
/// datos, nunca crear, alterar ni borrar tablas. Lo aplica el dueño del esquema después de
/// cada migración, así que es idempotente. Ver docs/despliegue.md (Base de datos).
/// </summary>
public static class PermisosDeLaApi
{
    public const string Sql = """
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'profeapp_app') THEN
            GRANT USAGE ON SCHEMA public TO profeapp_app;
            GRANT SELECT, INSERT, UPDATE, DELETE ON
              clases, clase_columnas, clase_alumnos, clase_valores, registros,
              asp_net_users, asp_net_user_roles, asp_net_user_claims, asp_net_user_logins, asp_net_user_tokens,
              tenants, instituciones, refresh_tokens
              TO profeapp_app;
            -- Roles: la API los siembra si faltan (base nueva) pero nunca los cambia ni borra.
            GRANT SELECT, INSERT ON asp_net_roles TO profeapp_app;
            GRANT SELECT ON asp_net_role_claims, "__EFMigrationsHistory" TO profeapp_app;
            -- Los pagos se agregan y se leen: nunca se editan ni se borran.
            GRANT SELECT, INSERT ON pagos TO profeapp_app;
            REVOKE UPDATE, DELETE, TRUNCATE ON pagos FROM profeapp_app;
            -- Claims de Identity usan columnas identity.
            GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO profeapp_app;
          END IF;
        END $$;
        """;
}
