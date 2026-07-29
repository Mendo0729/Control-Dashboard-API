import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUrl,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import {
  PROJECT_STATUSES,
  ProjectStatus,
} from '../project-status.constants';

export class UpdateProjectDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(150)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, {
    message:
      'slug solo puede contener letras minúsculas, números y guiones simples.',
  })
  slug?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  description?: string;

  @IsOptional()
  @IsIn(PROJECT_STATUSES)
  status?: ProjectStatus;

  @IsOptional()
  @IsBoolean()
  visibilityPublic?: boolean;

  @IsOptional()
  @IsUrl({ require_protocol: true })
  @MaxLength(2048)
  productionUrl?: string;

  @IsOptional()
  @IsUrl({ require_protocol: true })
  @MaxLength(2048)
  stagingUrl?: string;

  @IsOptional()
  @IsUrl({ require_protocol: true })
  @MaxLength(2048)
  logoUrl?: string;

  @IsOptional()
  @IsBoolean()
  featured?: boolean;
}
