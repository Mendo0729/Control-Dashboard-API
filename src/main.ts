import 'reflect-metadata';

import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  const port = Number(process.env.PORT ?? 3000);
  const apiPrefix = process.env.API_PREFIX ?? 'api';

  app.setGlobalPrefix(apiPrefix);
  app.enableShutdownHooks();

  await app.listen(port, '0.0.0.0');

  console.log(`Control Dashboard API disponible en http://localhost:${port}/${apiPrefix}`);
}

void bootstrap();
