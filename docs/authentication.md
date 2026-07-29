# Autenticación JWT

## Variables de entorno

```env
JWT_SECRET=replace_with_at_least_32_random_characters
JWT_EXPIRES_IN_SECONDS=3600
```

## Iniciar sesión

```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "usuario@example.com",
  "password": "password_del_usuario"
}
```

La respuesta incluye un `accessToken` y los datos públicos del usuario.

## Consultar el usuario autenticado

```http
GET /api/auth/me
Authorization: Bearer <accessToken>
```

Las credenciales inválidas, los usuarios inactivos y los tokens inválidos o expirados devuelven `401 Unauthorized`.
