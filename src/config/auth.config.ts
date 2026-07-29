import { registerAs } from '@nestjs/config';

export default registerAs('auth', () => ({
  jwtSecret: process.env.JWT_SECRET,
  jwtExpiresInSeconds: Number(process.env.JWT_EXPIRES_IN_SECONDS ?? 3600),
}));
