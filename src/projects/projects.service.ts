import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../database/prisma.service';
import { CreateProjectDto } from './dto/create-project.dto';
import { ListProjectsQueryDto } from './dto/list-projects-query.dto';
import { UpdateProjectDto } from './dto/update-project.dto';

interface ProjectRecord {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  status: string;
  visibility_public: boolean;
  production_url: string | null;
  staging_url: string | null;
  logo_url: string | null;
  featured: boolean;
  created_by: string | null;
  created_at: Date;
  updated_at: Date;
}

@Injectable()
export class ProjectsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(ownerId: string, dto: CreateProjectDto) {
    const name = this.normalizeName(dto.name);
    const slug = dto.slug ?? this.createSlug(name);

    try {
      const project = await this.prisma.projects.create({
        data: {
          name,
          slug,
          description: this.normalizeNullableText(dto.description),
          status: dto.status ?? 'DEVELOPMENT',
          visibility_public: dto.visibilityPublic ?? false,
          production_url: this.normalizeNullableText(dto.productionUrl),
          staging_url: this.normalizeNullableText(dto.stagingUrl),
          logo_url: this.normalizeNullableText(dto.logoUrl),
          featured: dto.featured ?? false,
          created_by: ownerId,
        },
      });

      return this.toResponse(project);
    } catch (error) {
      this.handlePersistenceError(error);
    }
  }

  async findAll(ownerId: string, query: ListProjectsQueryDto) {
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;
    const search = query.search?.trim();

    const where = {
      created_by: ownerId,
      ...(query.status
        ? { status: query.status }
        : query.includeArchived
          ? {}
          : { status: { not: 'ARCHIVED' as const } }),
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' as const } },
              { slug: { contains: search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [projects, total] = await this.prisma.$transaction([
      this.prisma.projects.findMany({
        where,
        orderBy: [{ featured: 'desc' }, { updated_at: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.projects.count({ where }),
    ]);

    return {
      data: projects.map((project) => this.toResponse(project)),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  async findOne(ownerId: string, projectId: string) {
    const project = await this.findOwnedProject(ownerId, projectId);
    return this.toResponse(project);
  }

  async update(ownerId: string, projectId: string, dto: UpdateProjectDto) {
    if (Object.values(dto).every((value) => value === undefined)) {
      throw new BadRequestException('Debe enviar al menos un campo para actualizar.');
    }

    await this.findOwnedProject(ownerId, projectId);

    const data = {
      ...(dto.name !== undefined ? { name: this.normalizeName(dto.name) } : {}),
      ...(dto.slug !== undefined ? { slug: dto.slug } : {}),
      ...(dto.description !== undefined
        ? { description: this.normalizeNullableText(dto.description) }
        : {}),
      ...(dto.status !== undefined ? { status: dto.status } : {}),
      ...(dto.visibilityPublic !== undefined
        ? { visibility_public: dto.visibilityPublic }
        : {}),
      ...(dto.productionUrl !== undefined
        ? { production_url: this.normalizeNullableText(dto.productionUrl) }
        : {}),
      ...(dto.stagingUrl !== undefined
        ? { staging_url: this.normalizeNullableText(dto.stagingUrl) }
        : {}),
      ...(dto.logoUrl !== undefined
        ? { logo_url: this.normalizeNullableText(dto.logoUrl) }
        : {}),
      ...(dto.featured !== undefined ? { featured: dto.featured } : {}),
    };

    try {
      const project = await this.prisma.projects.update({
        where: { id: projectId },
        data,
      });

      return this.toResponse(project);
    } catch (error) {
      this.handlePersistenceError(error);
    }
  }

  async archive(ownerId: string, projectId: string) {
    await this.findOwnedProject(ownerId, projectId);

    const project = await this.prisma.projects.update({
      where: { id: projectId },
      data: { status: 'ARCHIVED' },
    });

    return this.toResponse(project);
  }

  private async findOwnedProject(ownerId: string, projectId: string) {
    const project = await this.prisma.projects.findFirst({
      where: {
        id: projectId,
        created_by: ownerId,
      },
    });

    if (!project) {
      throw new NotFoundException('Proyecto no encontrado.');
    }

    return project;
  }

  private normalizeName(value: string): string {
    const name = value.trim();

    if (name.length < 2) {
      throw new BadRequestException(
        'El nombre del proyecto debe tener al menos 2 caracteres.',
      );
    }

    return name;
  }

  private normalizeNullableText(value?: string): string | null {
    if (value === undefined) {
      return null;
    }

    const normalized = value.trim();
    return normalized === '' ? null : normalized;
  }

  private createSlug(value: string): string {
    const slug = value
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 160)
      .replace(/-+$/g, '');

    if (!slug) {
      throw new BadRequestException(
        'No fue posible generar un slug válido para el proyecto.',
      );
    }

    return slug;
  }

  private handlePersistenceError(error: unknown): never {
    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      (error as { code?: unknown }).code === 'P2002'
    ) {
      throw new ConflictException('Ya existe un proyecto con ese slug.');
    }

    throw error;
  }

  private toResponse(project: ProjectRecord) {
    return {
      id: project.id,
      name: project.name,
      slug: project.slug,
      description: project.description,
      status: project.status,
      visibilityPublic: project.visibility_public,
      productionUrl: project.production_url,
      stagingUrl: project.staging_url,
      logoUrl: project.logo_url,
      featured: project.featured,
      createdBy: project.created_by,
      createdAt: project.created_at,
      updatedAt: project.updated_at,
    };
  }
}
