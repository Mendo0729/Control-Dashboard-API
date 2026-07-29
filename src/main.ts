import 'reflect-metadata';

import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);

  const port = configService.getOrThrow<number>('app.port');
  const apiPrefix = configService.getOrThrow<string>('app.apiPrefix');

  app.setGlobalPrefix(apiPrefix);
  app.enableShutdownHooks();

  await app.listen(port, '0.0.0.0');

  console.log(
    `Control Dashboard API disponible en http://localhost:${port}/${apiPrefix}`,
  );
}

void bootstrap();
