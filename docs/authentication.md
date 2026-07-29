# Autenticación JWT

Este documento explica cómo quedó implementada la autenticación, cómo preparar el entorno local y cómo comprobar el flujo completo.

## Estado de la implementación

La API dispone de:

- `POST /api/auth/login`: valida correo y contraseña y devuelve un token JWT.
- `GET /api/auth/me`: devuelve la identidad contenida en un token válido.
- validación de DTO con `ValidationPipe`.
- contraseñas verificadas con bcrypt.
- rechazo de usuarios inactivos.
- tokens con expiración configurable.
- validación de variables de entorno al iniciar NestJS.

## Flujo de autenticación

1. El cliente envía correo y contraseña a `POST /api/auth/login`.
2. `AuthService` busca el usuario en PostgreSQL mediante Prisma.
3. La API comprueba que el usuario exista y esté activo.
4. bcrypt compara la contraseña recibida con `users.password_hash`.
5. Si las credenciales son válidas, la API firma un JWT.
6. El cliente envía ese token como `Bearer` para acceder a rutas protegidas.

El token contiene estas propiedades:

```json
{
  "sub": "id-del-usuario",
  "email": "usuario@example.com",
  "role": "OWNER"
}
```

## Archivos principales

```text
src/auth/
├── auth.controller.ts
├── auth.module.ts
├── auth.service.ts
├── decorators/
│   └── current-user.decorator.ts
├── dto/
│   └── login.dto.ts
├── guards/
│   └── jwt-auth.guard.ts
└── interfaces/
    └── jwt-payload.interface.ts

src/config/
├── auth.config.ts
└── env.validation.ts
```

## Variables de entorno

Agrega estas variables al archivo local `.env`:

```env
JWT_SECRET=replace_with_at_least_32_random_characters
JWT_EXPIRES_IN_SECONDS=3600
```

- `JWT_SECRET`: clave privada usada para firmar y verificar tokens. Debe tener al menos 32 caracteres.
- `JWT_EXPIRES_IN_SECONDS`: duración del token en segundos. `3600` equivale a una hora.

El archivo `.env` está ignorado por Git. Nunca se debe subir el secreto real al repositorio.

## Generar un JWT_SECRET en Windows PowerShell

Este procedimiento funciona también en versiones de PowerShell/.NET que no permiten llamar `RandomNumberGenerator.GetBytes()` como método estático:

```powershell
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$rng.Dispose()

$jwtSecret = [System.BitConverter]::ToString($bytes).Replace('-', '')
```

Escribe o reemplaza el valor en `.env`:

```powershell
$envContent = Get-Content .env -Raw

if ($envContent -match '(?m)^JWT_SECRET=') {
  $envContent = $envContent -replace `
    '(?m)^JWT_SECRET=.*$', `
    "JWT_SECRET=$jwtSecret"
} else {
  $envContent += "`r`nJWT_SECRET=$jwtSecret"
}

if ($envContent -match '(?m)^JWT_EXPIRES_IN_SECONDS=') {
  $envContent = $envContent -replace `
    '(?m)^JWT_EXPIRES_IN_SECONDS=.*$', `
    'JWT_EXPIRES_IN_SECONDS=3600'
} else {
  $envContent += "`r`nJWT_EXPIRES_IN_SECONDS=3600"
}

[System.IO.File]::WriteAllText(
  (Resolve-Path .env),
  $envContent,
  [System.Text.UTF8Encoding]::new($false)
)
```

Comprueba la configuración sin mostrar el secreto completo:

```powershell
$jwtLine = Get-Content .env |
  Where-Object { $_ -match '^JWT_SECRET=' }

$jwtValue = $jwtLine -replace '^JWT_SECRET=', ''

[PSCustomObject]@{
  JWT_SECRET_CONFIGURED = -not [string]::IsNullOrWhiteSpace($jwtValue)
  JWT_SECRET_LENGTH     = $jwtValue.Length
  JWT_EXPIRATION        = (
    Get-Content .env |
    Where-Object { $_ -match '^JWT_EXPIRES_IN_SECONDS=' }
  )
}
```

El resultado esperado es:

```text
JWT_SECRET_CONFIGURED : True
JWT_SECRET_LENGTH     : 64
JWT_EXPIRATION        : JWT_EXPIRES_IN_SECONDS=3600
```

## Preparar la contraseña del administrador local

El seed inicial crea el usuario:

```text
admin@mendotech.lat
```

El valor original `LOCAL_DEVELOPMENT_ONLY` es solo un marcador y no es un hash bcrypt válido. Antes de iniciar sesión se debe establecer una contraseña local.

### 1. Define temporalmente la contraseña

```powershell
$adminPassword = Read-Host "Contraseña local para admin"
$env:DEV_ADMIN_PASSWORD = $adminPassword
```

Usa al menos ocho caracteres.

### 2. Crea un script temporal

```powershell
$scriptPath = Join-Path $PWD ".set-admin-password.cjs"

@'
require("dotenv").config();

const bcrypt = require("bcrypt");
const { Client } = require("pg");

async function main() {
  const password = process.env.DEV_ADMIN_PASSWORD;

  if (!password || password.length < 8) {
    throw new Error("La contraseña debe tener al menos 8 caracteres.");
  }

  if (!process.env.DATABASE_URL) {
    throw new Error("DATABASE_URL no está configurada.");
  }

  const client = new Client({
    connectionString: process.env.DATABASE_URL,
  });

  try {
    await client.connect();

    const hash = await bcrypt.hash(password, 12);

    const result = await client.query(
      `UPDATE users
       SET password_hash = $1,
           updated_at = NOW()
       WHERE email = $2
       RETURNING id, name, email, role, is_active`,
      [hash, "admin@mendotech.lat"],
    );

    if (result.rowCount === 0) {
      throw new Error("No se encontró el usuario admin@mendotech.lat.");
    }

    console.log(result.rows);
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
'@ | Set-Content -Path $scriptPath -Encoding UTF8
```

### 3. Actualiza la contraseña

```powershell
node $scriptPath
```

La salida debe mostrar el administrador con `role: 'OWNER'` e `is_active: true`.

Elimina el archivo temporal:

```powershell
Remove-Item $scriptPath
```

La base de datos almacena únicamente el hash bcrypt, no la contraseña en texto plano.

## Iniciar la API

```powershell
npm install
npx prisma generate
npm run typecheck
npm run build
npm run start:dev
```

La salida esperada incluye:

```text
Found 0 errors
Mapped {/api/auth/login, POST} route
Mapped {/api/auth/me, GET} route
Nest application successfully started
Control Dashboard API disponible en http://localhost:3000/api
```

## Probar el inicio de sesión

Mantén NestJS ejecutándose y abre otra ventana de PowerShell:

```powershell
$body = @{
  email    = "admin@mendotech.lat"
  password = $env:DEV_ADMIN_PASSWORD
} | ConvertTo-Json

$login = Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:3000/api/auth/login `
  -ContentType "application/json" `
  -Body $body

$login
```

Respuesta esperada:

```json
{
  "accessToken": "token-jwt",
  "tokenType": "Bearer",
  "user": {
    "id": "id-del-usuario",
    "email": "admin@mendotech.lat",
    "fullName": "Abdiel Mendoza",
    "role": "OWNER"
  }
}
```

## Probar la ruta protegida

```powershell
Invoke-RestMethod `
  -Method Get `
  -Uri http://localhost:3000/api/auth/me `
  -Headers @{
    Authorization = "Bearer $($login.accessToken)"
  }
```

Sin token, con un token modificado o con un token expirado, la API devuelve `401 Unauthorized`.

## Limpiar datos temporales de PowerShell

Después de las pruebas:

```powershell
Remove-Item Env:DEV_ADMIN_PASSWORD
$adminPassword = $null
$body = $null
$login = $null
$jwtSecret = $null
$jwtValue = $null
```

Esto no elimina el hash almacenado en PostgreSQL ni las variables guardadas en `.env`. Solo limpia la sesión actual de PowerShell.

## Errores resueltos durante la implementación

### `JWT_SECRET` vacío o inexistente

Síntoma:

```text
La variable de entorno JWT_SECRET es obligatoria.
```

Solución: generar el secreto, guardarlo en `.env` y reiniciar NestJS.

### Campo Prisma incorrecto

Síntoma:

```text
TS2339: Property 'full_name' does not exist
```

Causa: el modelo `users` expone `name`, no `full_name`.

Solución aplicada:

```typescript
fullName: user.name
```

### Error de comillas con `node -e`

Síntoma:

```text
SyntaxError: missing ) after argument list
```

Causa: PowerShell alteró las comillas del código JavaScript multilínea enviado a `node -e`.

Solución: escribir el código en un archivo `.cjs` temporal y ejecutarlo con `node`.

## Resultado final

La etapa de autenticación queda completada cuando se cumplen estas comprobaciones:

- `npm run typecheck` termina sin errores.
- `npm run build` termina sin errores.
- NestJS inicia y registra las rutas `/api/auth/login` y `/api/auth/me`.
- el administrador puede iniciar sesión con una contraseña bcrypt.
- el token permite consultar `/api/auth/me`.
- credenciales o tokens inválidos devuelven `401 Unauthorized`.
